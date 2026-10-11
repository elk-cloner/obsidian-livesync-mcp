"""Sandboxed, atomic file access over the plain-file vault mirror.

Every path reaching a tool is untrusted input. All resolution happens in this
module and nowhere else, so there is exactly one place to audit.
"""

from __future__ import annotations

import os
import re
import tempfile
from collections.abc import Iterator
from pathlib import Path, PurePosixPath

VAULT_ROOT = Path(os.environ.get("VAULT_ROOT", "/srv/vaults")).resolve()

MAX_READ_BYTES = int(os.environ.get("MAX_READ_BYTES", 1_000_000))
MAX_WRITE_BYTES = int(os.environ.get("MAX_WRITE_BYTES", 1_000_000))
MAX_LIST_ENTRIES = int(os.environ.get("MAX_LIST_ENTRIES", 2_000))
MAX_SEARCH_HITS = int(os.environ.get("MAX_SEARCH_HITS", 200))

# Unreachable through any tool, whatever the caller asks for.
#   .obsidian -- device config is deliberately not synced
#   .git      -- history repos live outside the tree; a stray .git here would
#                confuse both the bridge and the commit timer
#   .trash    -- written by trash_note(), never read back through a path
RESERVED = frozenset({".git", ".obsidian", ".trash"})

TRASH_DIR = ".trash"


class VaultError(Exception):
    """A rejected request. The message is safe to return to the caller."""


def _is_plain_name(name: str) -> bool:
    return bool(name) and name not in {".", ".."} and "/" not in name and "\x00" not in name


def list_vaults() -> list[str]:
    """Vault directory names, excluding hidden entries and symlinks."""
    if not VAULT_ROOT.is_dir():
        raise VaultError(f"vault root {VAULT_ROOT} is not a directory")
    return sorted(
        entry.name
        for entry in VAULT_ROOT.iterdir()
        if entry.is_dir() and not entry.is_symlink() and not entry.name.startswith(".")
    )


def vault_dir(vault: str) -> Path:
    """Resolved root of one vault."""
    if not _is_plain_name(vault) or vault.startswith("."):
        raise VaultError(f"invalid vault name: {vault!r}")
    directory = VAULT_ROOT / vault
    if directory.is_symlink() or not directory.is_dir():
        raise VaultError(f"unknown vault: {vault!r}")
    return directory.resolve()


def resolve(vault: str, path: str, *, allow_reserved: bool = False) -> tuple[Path, Path]:
    """Map an untrusted (vault, path) pair to a real path inside that vault.

    Returns (base, target). The target need not exist yet; writes rely on that.
    """
    base = vault_dir(vault)

    if "\x00" in path:
        raise VaultError("path contains a null byte")
    pure = PurePosixPath(path)
    if pure.is_absolute():
        raise VaultError("path must be relative to the vault root")

    parts = [part for part in pure.parts if part != "."]
    if not parts:
        raise VaultError("path is empty")
    if any(part == ".." for part in parts):
        raise VaultError("path may not traverse upward")
    if not allow_reserved and any(part in RESERVED for part in parts):
        raise VaultError(f"path is inside a reserved directory ({', '.join(sorted(RESERVED))})")

    # A symlink at any depth could point outside the vault, so test every
    # component rather than trusting the resolved string.
    for depth in range(len(parts)):
        if base.joinpath(*parts[: depth + 1]).is_symlink():
            raise VaultError("refusing to follow a symlink")

    target = base.joinpath(*parts)

    # Belt and braces: confirm the deepest existing ancestor really sits inside
    # the vault, which also catches a swapped-out vault root.
    probe = target
    while not probe.exists():
        probe = probe.parent
    real = probe.resolve()
    if real != base and base not in real.parents:
        raise VaultError("path escapes the vault")

    return base, target


def relpath(target: Path, base: Path) -> str:
    return target.relative_to(base).as_posix()


def iter_files(base: Path, start: Path) -> Iterator[Path]:
    """Walk visible, non-symlinked files under `start`, skipping reserved dirs."""
    for root, dirnames, filenames in os.walk(start):
        dirnames[:] = sorted(
            name
            for name in dirnames
            if name not in RESERVED
            and not name.startswith(".")
            and not Path(root, name).is_symlink()
        )
        for name in sorted(filenames):
            if name.startswith("."):
                continue
            candidate = Path(root, name)
            if candidate.is_symlink():
                continue
            yield candidate


def list_files(vault: str, subpath: str = "", extension: str = ".md") -> list[str]:
    """Visible file paths in a vault, optionally under one folder and of one extension.

    A subpath that does not exist yet returns an empty list rather than an
    error: in a synced vault, folders only exist once they hold a note.
    """
    if subpath:
        base, start = resolve(vault, subpath)
        if not start.exists():
            return []
        if not start.is_dir():
            raise VaultError(f"not a folder: {subpath}")
    else:
        base = start = vault_dir(vault)

    suffix = extension.lower()
    found = [
        relpath(path, base)
        for path in iter_files(base, start)
        if not suffix or path.suffix.lower() == suffix
    ]
    if len(found) > MAX_LIST_ENTRIES:
        raise VaultError(f"{len(found)} entries exceeds the {MAX_LIST_ENTRIES} limit; narrow with subpath")
    return found


def read_text(target: Path, base: Path) -> str:
    if not target.is_file():
        raise VaultError(f"not a file: {relpath(target, base)}")
    size = target.stat().st_size
    if size > MAX_READ_BYTES:
        raise VaultError(
            f"{relpath(target, base)} is {size} bytes, over the {MAX_READ_BYTES} byte read limit"
        )
    return target.read_text(encoding="utf-8", errors="replace")


def write_atomic(target: Path, content: str) -> int:
    """Replace `target` with `content` in a way the bridge can never half-see."""
    data = content.encode("utf-8")
    if len(data) > MAX_WRITE_BYTES:
        raise VaultError(f"content is {len(data)} bytes, over the {MAX_WRITE_BYTES} byte write limit")

    target.parent.mkdir(parents=True, exist_ok=True)

    # Stage in the target's own directory so os.replace is atomic, and give the
    # staging file a dot prefix: hidden files are outside the sync scope, so the
    # bridge's watcher ignores it instead of pushing a partial note to CouchDB.
    handle, staged = tempfile.mkstemp(dir=target.parent, prefix=".livesync-mcp-", suffix=".tmp")
    try:
        with os.fdopen(handle, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(staged, target)
    except BaseException:
        try:
            os.unlink(staged)
        except FileNotFoundError:
            pass
        raise
    return len(data)


def trash(target: Path, base: Path) -> str:
    """Move a note into the vault's .trash instead of deleting it.

    .trash is hidden, so it stays server-side and is never replicated to
    devices. It is the git timer and the nightly backup that make this
    recoverable; empty it by hand.
    """
    if not target.is_file():
        raise VaultError(f"not a file: {relpath(target, base)}")

    relative = relpath(target, base)
    destination = base / TRASH_DIR / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        stamp = str(int(target.stat().st_mtime))
        destination = destination.with_name(f"{destination.stem}.{stamp}{destination.suffix}")
    os.replace(target, destination)
    return relpath(destination, base)


def search(base: Path, start: Path, query: str, *, regex: bool, max_hits: int) -> list[dict]:
    """Line-level search across markdown files. Returns at most `max_hits` rows."""
    if not query:
        raise VaultError("query is empty")
    limit = max(1, min(max_hits, MAX_SEARCH_HITS))

    if regex:
        try:
            pattern = re.compile(query, re.IGNORECASE)
        except re.error as exc:
            raise VaultError(f"invalid regular expression: {exc}") from exc
        matches = lambda line: pattern.search(line) is not None  # noqa: E731
    else:
        needle = query.lower()
        matches = lambda line: needle in line.lower()  # noqa: E731

    hits: list[dict] = []
    for candidate in iter_files(base, start):
        if candidate.suffix.lower() != ".md":
            continue
        if candidate.stat().st_size > MAX_READ_BYTES:
            continue
        try:
            text = candidate.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for number, line in enumerate(text.splitlines(), start=1):
            if matches(line):
                hits.append(
                    {"path": relpath(candidate, base), "line": number, "text": line.strip()[:400]}
                )
                if len(hits) >= limit:
                    return hits
    return hits
