#!/usr/bin/env python3
"""Keep the vault skills self-contained, check them, and package them.

    python3 skills/tools/build.py sync      copy _shared/ into every skill's references/
    python3 skills/tools/build.py check     fail if a copy drifted or a SKILL.md is invalid
    python3 skills/tools/build.py check --tag skills-vX.Y.Z
                                            also fail unless X.Y.Z is the plugin.json version
    python3 skills/tools/build.py package   sync, check, then write dist/<skill>.zip

Why copies: claude.ai uploads each skill as its own zip, and Claude Code does
not promise a plugin skill can read outside its folder. So the shared rules are
edited once in skills/_shared/ and copied into each skill. `check` runs in the
tests, so a forgotten `sync` fails loudly instead of shipping stale rules.

Standard library only.
"""
from __future__ import annotations

import json
import re
import shutil
import sys
import zipfile
from pathlib import Path

SKILLS = Path(__file__).resolve().parent.parent
REPO = SKILLS.parent
SHARED = SKILLS / "_shared"
DIST = REPO / "dist"
PLUGIN_JSON = SKILLS / ".claude-plugin" / "plugin.json"

NAME_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
NAME_MAX = 64
DESCRIPTION_MAX = 1024
PREFIX = "vault-"
SKIP_IN_ZIP = {"__pycache__", ".DS_Store"}
TAG_RE = re.compile(r"^skills-v(\d+\.\d+\.\d+)$")


def skill_dirs() -> list[Path]:
    return sorted(p.parent for p in SKILLS.glob("*/SKILL.md"))


def frontmatter(text: str) -> dict[str, str]:
    """The flat `key: value` lines between the opening and closing ---."""
    if not text.startswith("---\n"):
        return {}
    end = text.find("\n---", 4)
    if end == -1:
        return {}
    fields = {}
    for line in text[4:end].splitlines():
        key, sep, value = line.partition(":")
        if sep and key and not key.startswith((" ", "\t")):
            fields[key.strip()] = value.strip()
    return fields


def sync() -> None:
    for skill in skill_dirs():
        target = skill / "references"
        target.mkdir(exist_ok=True)
        for src in sorted(SHARED.iterdir()):
            if src.is_file():
                shutil.copyfile(src, target / src.name)
    print(f"synced {SHARED.relative_to(REPO)} into {len(skill_dirs())} skills")


def check(tag: str | None = None) -> int:
    problems: list[str] = []
    if tag is not None:
        version = json.loads(PLUGIN_JSON.read_text(encoding="utf-8")).get("version", "")
        match = TAG_RE.match(tag)
        if not match:
            problems.append(f"tag {tag!r} must look like skills-vX.Y.Z (for example skills-v{version or '1.0.0'})")
        elif match.group(1) != version:
            problems.append(f"tag {tag!r} does not match version {version!r} in {PLUGIN_JSON.relative_to(REPO)}")
    shared = {p.name: p.read_bytes() for p in SHARED.iterdir() if p.is_file()}
    skills = skill_dirs()
    if not skills:
        problems.append("no skills found")

    for skill in skills:
        rel = skill.relative_to(REPO)
        text = (skill / "SKILL.md").read_text(encoding="utf-8")
        fm = frontmatter(text)
        name, description = fm.get("name", ""), fm.get("description", "")

        if name != skill.name:
            problems.append(f"{rel}: name {name!r} does not match the folder")
        if not NAME_RE.match(name) or len(name) > NAME_MAX:
            problems.append(f"{rel}: name must be lowercase words joined by hyphens, at most {NAME_MAX} characters")
        if not name.startswith(PREFIX):
            problems.append(f"{rel}: name must start with {PREFIX!r} (claude.ai has no namespaces)")
        if not description:
            problems.append(f"{rel}: description is missing")
        elif len(description) > DESCRIPTION_MAX:
            problems.append(f"{rel}: description is {len(description)} characters, over {DESCRIPTION_MAX}")
        if "../" in text:
            problems.append(f"{rel}: SKILL.md points outside its folder ('../'); claude.ai zips cannot follow that")
        if "references/access.md" not in text:
            problems.append(f"{rel}: SKILL.md does not tell Claude to read references/access.md")

        for fname, content in shared.items():
            copy = skill / "references" / fname
            if not copy.is_file():
                problems.append(f"{rel}/references/{fname}: missing (run: python3 skills/tools/build.py sync)")
            elif copy.read_bytes() != content:
                problems.append(f"{rel}/references/{fname}: differs from _shared (run: python3 skills/tools/build.py sync)")

    for problem in problems:
        print(f"FAIL {problem}")
    if problems:
        return 1
    print(f"ok: {len(skills)} skills valid, shared references in sync")
    return 0


def package() -> int:
    sync()
    if check():
        return 1
    DIST.mkdir(exist_ok=True)
    for skill in skill_dirs():
        out = DIST / f"{skill.name}.zip"
        with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
            # claude.ai wants one top-level folder named like the skill.
            for path in sorted(skill.rglob("*")):
                if path.is_dir() or SKIP_IN_ZIP & set(path.parts):
                    continue
                zf.write(path, Path(skill.name) / path.relative_to(skill))
        print(f"wrote {out.relative_to(REPO)}")
    return 0


def main(argv: list[str]) -> int:
    commands = {"sync": lambda: sync() or 0, "check": check, "package": package}
    if len(argv) == 4 and argv[1] == "check" and argv[2] == "--tag":
        return check(argv[3])
    if len(argv) != 2 or argv[1] not in commands:
        print(__doc__, file=sys.stderr)
        return 2
    return commands[argv[1]]()


if __name__ == "__main__":
    sys.exit(main(sys.argv))
