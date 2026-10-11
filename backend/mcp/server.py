"""MCP server exposing the Obsidian vault mirror to Claude.

Authentication uses FastMCP's GoogleProvider, a subclass of its OAuthProxy: it
presents a DCR-compliant OAuth interface to claude.ai (401 + RFC 9728 resource
metadata, RFC 8414 authorization-server metadata, PKCE S256) while using one
pre-registered Google client upstream. claude.ai custom connectors accept only
OAuth or no authentication -- static bearer headers are beta-gated to specific
organizations -- so for a writable server on the public internet this is the
only workable shape.

Writes land in /srv/vaults, livesync-bridge pushes them into CouchDB, and the
LiveSync plugin pulls them down to every device.
"""

from __future__ import annotations

import datetime
import functools
import importlib.util
import os
from pathlib import Path
from typing import Annotated, Any

from cryptography.fernet import Fernet
from fastmcp import FastMCP
from fastmcp.exceptions import ToolError
from fastmcp.server.auth.providers.google import GoogleProvider
from fastmcp.server.dependencies import get_access_token
from fastmcp.server.middleware import Middleware, MiddlewareContext
from key_value.aio.stores.disk import DiskStore
from key_value.aio.wrappers.encryption import FernetEncryptionWrapper
from pydantic import Field

import vaults
from vaults import VaultError


def _load_lint():
    """The vault-lint skill's lint.py, the only lint implementation.

    The image copies it in as vault_lint.py. In a checkout (tests, local runs)
    it is loaded from skills/ instead, so there is never a second copy.
    """
    try:
        import vault_lint  # type: ignore[import-not-found]

        return vault_lint
    except ImportError:
        here = Path(__file__).resolve()
        if len(here.parents) < 3:
            raise
        path = here.parents[2] / "skills" / "vault-lint" / "scripts" / "lint.py"
        spec = importlib.util.spec_from_file_location("vault_lint", path)
        if not path.is_file() or spec is None or spec.loader is None:
            raise
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module


vault_lint = _load_lint()


def _require(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"{name} is required (see .env.example)")
    return value


BASE_URL = _require("FASTMCP_SERVER_BASE_URL")
ALLOWED_EMAIL = _require("ALLOWED_EMAIL").lower()

auth = GoogleProvider(
    client_id=_require("GOOGLE_CLIENT_ID"),
    client_secret=_require("GOOGLE_CLIENT_SECRET"),
    # Must match the Authorized redirect URI registered in Google Cloud
    # Console, which is this value plus /auth/callback.
    base_url=BASE_URL,
    required_scopes=["openid", "https://www.googleapis.com/auth/userinfo.email"],
    # Both of these must survive restarts. The signing key backs the tokens
    # Claude holds; the client store holds Claude's dynamically registered
    # OAuth client. Lose either and the connector needs re-authorizing.
    jwt_signing_key=_require("JWT_SIGNING_KEY"),
    client_storage=FernetEncryptionWrapper(
        key_value=DiskStore(directory=os.environ.get("OAUTH_CLIENT_STORE_DIR", "/data/oauth-clients")),
        fernet=Fernet(_require("OAUTH_STORAGE_ENCRYPTION_KEY")),
    ),
)


class SingleUserOnly(Middleware):
    """Reject every account but the one allowed Google identity.

    A successful Google sign-in only proves *some* Google identity, so the
    email claim is the actual authorization check. Gating on_call_tool covers
    every path that touches a vault; listing tools exposes nothing by itself.
    """

    async def on_call_tool(self, context: MiddlewareContext, call_next):
        token = get_access_token()
        if token is None:
            raise ToolError("Not authenticated.")

        claims = token.claims or {}
        email = str(claims.get("email") or "").strip().lower()
        if not email:
            raise ToolError("Token carries no email claim; cannot authorize.")
        if claims.get("email_verified") is False:
            raise ToolError("This Google account's email is not verified.")
        if email != ALLOWED_EMAIL:
            raise ToolError("This connector is restricted to a single account.")

        return await call_next(context)


mcp = FastMCP(
    name="Obsidian Vaults",
    instructions=(
        "Read and write the user's self-hosted Obsidian knowledge vaults. "
        "Call list_vaults first if the vault is not already known; paths are "
        "relative to a vault root. Before writing to a vault, read its root "
        "CLAUDE.md: it is the schema and the write rules every note follows. "
        "All dates and times in a vault are UTC; get them from vault_now, "
        "never from the conversation. Edits propagate to all the user's "
        "devices within seconds, so read a note before overwriting it."
    ),
    auth=auth,
)
mcp.add_middleware(SingleUserOnly())


def _guard(fn):
    """Surface VaultError as a clean tool error instead of a stack trace."""

    @functools.wraps(fn)
    def wrapper(*args, **kwargs):
        try:
            return fn(*args, **kwargs)
        except VaultError as exc:
            raise ToolError(str(exc)) from exc
        except OSError as exc:
            raise ToolError(f"filesystem error: {exc.strerror or exc}") from exc

    return wrapper


VaultName = Annotated[str, Field(description="Vault name as returned by list_vaults.")]
NotePath = Annotated[str, Field(description="Path relative to the vault root, e.g. 'findings/foo.md'.")]


@mcp.tool(title="List vaults", annotations={"read_only_hint": True})
@_guard
def list_vaults() -> list[str]:
    """List every vault available on the server."""
    return vaults.list_vaults()


@mcp.tool(title="List notes", annotations={"read_only_hint": True})
@_guard
def list_notes(
    vault: VaultName,
    subpath: Annotated[str, Field(description="Limit to this folder. Empty means the whole vault.")] = "",
    extension: Annotated[str, Field(description="Filter by file extension, e.g. '.md'. Empty means all.")] = ".md",
) -> list[str]:
    """List note paths in a vault, alphabetically ordered.

    A folder that does not exist yet lists as empty: folders only appear with
    their first note, because sync carries notes, not empty folders.
    """
    return vaults.list_files(vault, subpath, extension)


@mcp.tool(title="Current time (UTC)", annotations={"read_only_hint": True})
def vault_now() -> dict[str, str]:
    """The current UTC date and time, in the formats the vault schema uses.

    Use `date` for created/updated fields and file names, and `log_time` for
    log.md lines. Every device and the server agree on it, unlike a date taken
    from the conversation or a local clock.
    """
    now = datetime.datetime.now(datetime.timezone.utc)
    return {
        "date": now.strftime("%Y-%m-%d"),
        "log_time": now.strftime("%Y-%m-%d %H:%M"),
        "iso": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "timezone": "UTC",
    }


@mcp.tool(title="Read note", annotations={"read_only_hint": True})
@_guard
def read_note(vault: VaultName, path: NotePath) -> str:
    """Read a note's full text."""
    base, target = vaults.resolve(vault, path)
    return vaults.read_text(target, base)


@mcp.tool(title="Note info", annotations={"read_only_hint": True})
@_guard
def note_info(vault: VaultName, path: NotePath) -> dict[str, Any]:
    """Size and modification time for a note, without reading it."""
    base, target = vaults.resolve(vault, path)
    if not target.exists():
        return {"path": vaults.relpath(target, base), "exists": False}
    stat = target.stat()
    return {
        "path": vaults.relpath(target, base),
        "exists": True,
        "is_file": target.is_file(),
        "bytes": stat.st_size,
        "modified": int(stat.st_mtime),
    }


@mcp.tool(title="Search notes", annotations={"read_only_hint": True})
@_guard
def search_notes(
    vault: VaultName,
    query: Annotated[str, Field(description="Text to find, or a regular expression if regex is true.")],
    subpath: Annotated[str, Field(description="Limit the search to this folder.")] = "",
    regex: Annotated[bool, Field(description="Treat query as a case-insensitive regular expression.")] = False,
    max_hits: Annotated[int, Field(description="Maximum matching lines to return.", ge=1)] = 50,
) -> list[dict[str, Any]]:
    """Search markdown files line by line, returning path, line number and text."""
    if subpath:
        base, start = vaults.resolve(vault, subpath)
        if not start.is_dir():
            raise VaultError(f"not a folder: {subpath}")
    else:
        base = start = vaults.vault_dir(vault)
    return vaults.search(base, start, query, regex=regex, max_hits=max_hits)


@mcp.tool(title="Write note", annotations={"read_only_hint": False, "destructive_hint": True})
@_guard
def write_note(
    vault: VaultName,
    path: NotePath,
    content: Annotated[str, Field(description="Full new contents of the note.")],
    overwrite: Annotated[bool, Field(description="Required to replace a note that already exists.")] = False,
) -> dict[str, Any]:
    """Create a note, or replace one entirely when overwrite is true.

    Propagates to every device within seconds. Read the note first if you
    intend to preserve any of its current content.
    """
    base, target = vaults.resolve(vault, path)
    existed = target.exists()
    if existed and not overwrite:
        raise VaultError(f"{vaults.relpath(target, base)} already exists; pass overwrite=true to replace it")
    if existed and not target.is_file():
        raise VaultError(f"{vaults.relpath(target, base)} is not a file")

    written = vaults.write_atomic(target, content)
    return {"path": vaults.relpath(target, base), "bytes": written, "replaced": existed}


@mcp.tool(title="Append to note", annotations={"read_only_hint": False, "destructive_hint": False})
@_guard
def append_note(
    vault: VaultName,
    path: NotePath,
    content: Annotated[str, Field(description="Text to append. A newline is inserted if one is missing.")],
) -> dict[str, Any]:
    """Append to a note, creating it if absent. Existing content is preserved."""
    base, target = vaults.resolve(vault, path)
    # Capture this before writing: an existing-but-empty note must not be
    # reported as newly created.
    existed = target.is_file()
    existing = vaults.read_text(target, base) if existed else ""
    if existing and not existing.endswith("\n"):
        existing += "\n"

    written = vaults.write_atomic(target, existing + content)
    return {"path": vaults.relpath(target, base), "bytes": written, "created": not existed}


@mcp.tool(title="Trash note", annotations={"read_only_hint": False, "destructive_hint": True})
@_guard
def trash_note(vault: VaultName, path: NotePath) -> dict[str, Any]:
    """Move a note into the vault's server-side .trash folder.

    Nothing is deleted outright. The note leaves every device, but stays
    recoverable on the server and in git history.
    """
    base, target = vaults.resolve(vault, path)
    return {"trashed_to": vaults.trash(target, base)}


LINT_SAMPLE = 10


@mcp.tool(title="Lint vault", annotations={"read_only_hint": False, "destructive_hint": False})
@_guard
def lint_vault(vault: VaultName) -> dict[str, Any]:
    """Run the vault's structural lint and write lint-report.md at its root.

    Returns the note count, the number of issues per check, and the first few
    items of each check. The full list is in lint-report.md. Nothing else in
    the vault changes.
    """
    base = vaults.vault_dir(vault)
    report, issues, count = vault_lint.lint(base)
    _, target = vaults.resolve(vault, vault_lint.REPORT_NAME)
    vaults.write_atomic(target, report)
    return {
        "notes": count,
        "issues": sum(len(items) for items in issues.values()),
        "checks": {
            check: {"count": len(items), "first": items[:LINT_SAMPLE]}
            for check, items in sorted(issues.items())
        },
        "report": vault_lint.REPORT_NAME,
    }


if __name__ == "__main__":
    # FastMCP serves streamable HTTP at /mcp, so the connector URL is
    # https://mcp.<domain>/mcp.
    mcp.run(transport="http", host="0.0.0.0", port=8000)
