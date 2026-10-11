#!/usr/bin/env python3
"""Structural lint for the knowledge vault.

Usage: lint.py <vault-root> [--json]

Writes <vault-root>/lint-report.md and prints a summary. Exits 1 if it found
issues. The checks are listed in the vault CLAUDE.md, section "Lint".

This is the only implementation. The vault-lint skill runs it as a script on a
local folder, and the MCP server imports lint() for its lint_vault tool, so it
must depend on nothing but the standard library and PyYAML.
"""
from __future__ import annotations

import datetime
import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover - depends on the environment
    sys.exit("PyYAML required: pip install pyyaml")

TYPES = {
    "finding": {"unverified", "verified", "retracted"},
    "decision": {"active", "superseded"},
    "concept": {"draft", "current", "needs_review"},
    "question": {"open", "answered", "dropped"},
    "task": {"todo", "doing", "blocked", "done"},
    "record": {"none"},
    "source": {"unread", "reading", "read", "reference"},
    "output": {"draft", "final", "stale"},
    "learning-path": {"draft", "current"},
}
REQUIRED = ["type", "title", "area", "topics", "projects", "status", "created", "updated"]
# Top-level folders that hold no notes. Hidden folders (.obsidian, .git,
# .trash) are skipped everywhere, along with symlinks.
SKIP_DIRS = {"_templates", "_bases", "_attachments", "_state"}
# Operating documents, not notes.
SKIP_FILES = {"lint-report.md", "log.md", "CLAUDE.md", "README.md"}
LINK = re.compile(r"\[\[([^\]|#]+)(?:[#|][^\]]*)?\]\]")
REPORT_NAME = "lint-report.md"


def utc_today() -> datetime.date:
    """The vault schema is UTC throughout, whatever the machine's zone."""
    return datetime.datetime.now(datetime.timezone.utc).date()


def parse(path: Path):
    text = path.read_text(encoding="utf-8", errors="replace")
    if not text.startswith("---"):
        return None, text
    end = text.find("\n---", 3)
    if end == -1:
        return None, text
    try:
        fm = yaml.safe_load(text[3:end]) or {}
    except yaml.YAMLError as e:
        return {"__error__": str(e)}, text[end + 4:]
    if not isinstance(fm, dict):
        return {"__error__": "frontmatter is not a mapping"}, text[end + 4:]
    return fm, text[end + 4:]


def links_in(obj) -> set[str]:
    out: set[str] = set()
    if isinstance(obj, str):
        out.update(m.group(1).strip() for m in LINK.finditer(obj))
    elif isinstance(obj, dict):
        for v in obj.values():
            out |= links_in(v)
    elif isinstance(obj, list):
        for v in obj:
            out |= links_in(v)
    return out


def as_date(v):
    if isinstance(v, datetime.date):
        return v if not isinstance(v, datetime.datetime) else v.date()
    try:
        return datetime.date.fromisoformat(str(v)[:10])
    except Exception:
        return None


def iter_notes(root: Path):
    """Markdown files under root, skipping hidden entries and symlinks."""
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        here = Path(dirpath)
        rel_dir = here.relative_to(root)
        dirnames[:] = sorted(
            d for d in dirnames
            if not d.startswith(".")
            and not (here / d).is_symlink()
            and not (rel_dir == Path(".") and d in SKIP_DIRS)
        )
        for name in sorted(filenames):
            if name.startswith(".") or not name.endswith(".md") or name in SKIP_FILES:
                continue
            path = here / name
            if path.is_symlink():
                continue
            yield path


def lint(root: Path | str, today: datetime.date | None = None):
    """Run every structural check.

    Returns (report_markdown, issues, note_count). issues maps a check name to
    a list of human-readable items. Nothing is written.
    """
    root = Path(root).resolve()
    today = today or utc_today()

    notes = {}
    for p in iter_notes(root):
        rel = p.relative_to(root)
        fm, body = parse(p)
        notes[rel.with_suffix("").as_posix()] = {
            "path": rel.as_posix(), "fm": fm, "body": body, "slug": p.stem,
        }
    by_slug = defaultdict(list)
    for key, n in notes.items():
        by_slug[n["slug"]].append(key)

    areas = {
        d.name: f"{kind}/{d.name}"
        for kind in ("topics", "projects")
        if (root / kind).is_dir()
        for d in (root / kind).iterdir()
        if d.is_dir() and not d.is_symlink() and not d.name.startswith(".")
    }

    def resolve(target):
        t = target.strip()
        if t in notes:
            return t
        if t.endswith(".md") and t[:-3] in notes:
            return t[:-3]
        hits = by_slug.get(t.split("/")[-1], [])
        if len(hits) == 1:
            return hits[0]
        if t in areas or t in areas.values():
            return "__area__"  # link to a topic or project folder
        return None

    issues = defaultdict(list)
    inbound = defaultdict(set)

    for key, n in notes.items():
        fm = n["fm"]
        if fm is None:
            issues["missing_frontmatter"].append(n["path"])
            continue
        if "__error__" in fm:
            issues["bad_yaml"].append(f'{n["path"]}: {fm["__error__"]}')
            continue
        t = fm.get("type")
        if t not in TYPES:
            issues["invalid_type"].append(f'{n["path"]}: {t!r}')
            continue
        miss = [k for k in REQUIRED if k not in fm]
        if miss:
            issues["missing_fields"].append(f'{n["path"]}: {", ".join(miss)}')
        if str(fm.get("status")) not in TYPES[t]:
            issues["invalid_status"].append(f'{n["path"]}: {fm.get("status")!r} for {t}')
        parts = Path(n["path"]).parts
        folder = "/".join(parts[:2]) if len(parts) >= 3 else ""
        if folder and fm.get("area") and fm["area"] != folder:
            issues["area_mismatch"].append(f'{n["path"]}: area={fm["area"]} folder={folder}')
        if t == "finding" and not fm.get("source") and fm.get("status") != "retracted":
            issues["finding_without_source"].append(n["path"])
        for target in links_in(fm) | links_in(n["body"]):
            r = resolve(target)
            if r is None:
                issues["broken_link"].append(f'{n["path"]} -> [[{target}]]')
            elif r != "__area__":
                inbound[r].add(key)

    for key, n in notes.items():
        fm = n["fm"] or {}
        if "__error__" in fm or fm.get("type") not in TYPES:
            continue
        t = fm["type"]
        if t not in ("source", "task", "record", "learning-path") and not inbound[key] \
                and not fm.get("topics") and not fm.get("projects"):
            issues["orphan"].append(n["path"])
        if t == "decision" and fm.get("status") == "superseded":
            for src in inbound[key]:
                sfm = notes[src]["fm"] or {}
                if str(sfm.get("supersedes", "")).find(n["slug"]) == -1 and sfm.get("type") != "decision":
                    issues["superseded_decision_still_linked"].append(f'{n["path"]} <- {notes[src]["path"]}')
        if t == "task" and fm.get("blocked_by"):
            q = resolve(next(iter(links_in(fm["blocked_by"])), ""))
            if q is None or q == "__area__" or (notes[q]["fm"] or {}).get("status") != "open":
                issues["task_blocked_by_non_open_question"].append(n["path"])
        if t == "output" and fm.get("status") in ("draft", "final"):
            created = as_date(fm.get("created"))
            for target in links_in(fm.get("drew_on", [])):
                r = resolve(target)
                if r and r != "__area__" and created:
                    upd = as_date((notes[r]["fm"] or {}).get("updated"))
                    if upd and upd > created:
                        issues["output_stale_candidate"].append(f'{n["path"]} (changed: {notes[r]["path"]})')
                        break
        if t == "concept" and not fm.get("needs_review"):
            upd = as_date(fm.get("updated"))
            newer = [
                s for s in inbound[key]
                if (notes[s]["fm"] or {}).get("type") == "finding"
                and (c := as_date((notes[s]["fm"] or {}).get("created"))) and upd and c > upd
            ]
            if len(newer) >= 3:
                issues["concept_behind_findings"].append(f'{n["path"]} ({len(newer)} newer findings)')

    lines = ["# Lint report", "",
             f"Generated {today.isoformat()} (UTC) by the lint script. {len(notes)} notes checked.", ""]
    total = 0
    for check, items in sorted(issues.items()):
        total += len(items)
        lines.append(f"## {check} ({len(items)})")
        lines += [f"- {i}" for i in items]
        lines.append("")
    if total == 0:
        lines.append("No issues.")
    report = "\n".join(lines) + "\n"
    return report, dict(issues), len(notes)


def main(argv: list[str]) -> int:
    args = [a for a in argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        sys.exit(__doc__)
    root = Path(args[0]).resolve()
    if not root.is_dir():
        sys.exit(f"not a folder: {root}")
    report, issues, count = lint(root)
    (root / REPORT_NAME).write_text(report, encoding="utf-8")
    total = sum(len(v) for v in issues.values())
    if "--json" in argv:
        print(json.dumps(issues, indent=2))
    else:
        print(f"{count} notes, {total} issues -> {root / REPORT_NAME}")
        for check, items in sorted(issues.items()):
            print(f"  {check}: {len(items)}")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
