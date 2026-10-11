#!/usr/bin/env python3
"""Check markdown files against the writing rules in docs/style.md.

Usage: python3 docs/tools/ste_check.py <file or folder>...

Errors (exit 1): a forbidden word, a sentence that is too long, a paragraph
with more than six sentences. Warnings (exit 0): a possible passive verb, a
sentence or heading that starts with an "-ing" word. A script cannot judge
meaning, so a warning is a prompt to look, not a verdict.

Code blocks, inline code, quoted text, link targets and HTML comments are skipped. A line
that ends with <!-- ste-ignore --> is skipped.
"""
import fnmatch
import re
import sys
from pathlib import Path

PROCEDURE_MAX = 20   # numbered list items
DESCRIPTION_MAX = 25
PARAGRAPH_MAX = 6

FORBIDDEN = ["should", "simply", "just", "please", "easily", "obviously",
             "basically", "really", "very", "etc", "never", "avoid", "utilize"]

# Files that follow their own rules (the vault schema, the skills, notes).
EXCLUDE = ["*/SKILL.md", "*/references/*", "skills/_shared/*", "vault/examples/*",
           "vault/template/_templates/*", "vault/template/CLAUDE.md",
           "vault/template/log.md", "*/.claude/*", "*/dist/*", "*/node_modules/*"]

ABBREVIATIONS = {"e.g.": "eg", "i.e.": "ie", "vs.": "vs", "approx.": "approx"}
IRREGULAR = ("written|done|made|given|shown|known|taken|seen|built|kept|sent|held|"
             "found|left|put|read|run|set|lost|cut|begun|chosen|driven|hidden|stolen")
PASSIVE = re.compile(rf"\b(is|are|was|were|be|been|being)\s+(\w+ed|{IRREGULAR})\b", re.I)
FORBIDDEN_RE = re.compile(r"\b(" + "|".join(FORBIDDEN) + r")\b\.?", re.I)
ING_START = re.compile(r"^[^A-Za-z]*([A-Z][a-z]+ing)\b")
ING_OK = {"During", "Nothing", "Something", "Anything", "Everything", "String", "Thing",
          "Setting", "Settings", "Morning", "Evening", "Spring", "Ring", "King", "Bring",
          "Ping", "Missing", "Pending", "Existing", "Following", "Incoming", "Outgoing",
          "Remaining", "Matching", "Running", "Blocking", "Warning", "Warnings", "Logging",
          "Staging", "Testing", "Meaning", "Building", "Routing", "Thinking", "Writing", "Reading"}


def clean(text):
    """Remove the parts of a line that are not prose."""
    text = re.sub(r"<!--.*?-->", " ", text)
    text = re.sub(r"`[^`]*`", "CODE", text)
    text = re.sub(r"!\[([^\]]*)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"<[^>]+>", " ", text)
    text = re.sub(r"https?://\S+", "URL", text)
    text = re.sub(r"[\"“][^\"”]{0,80}[\"”]", "QUOTE", text)   # quoted examples and messages
    text = re.sub(r"[*_]{1,3}", "", text)
    for abbreviation, word in ABBREVIATIONS.items():
        text = text.replace(abbreviation, word)
    return text


def sentences(text):
    parts = re.split(r"(?<=[.!?:])\s+(?=[A-Z0-9\"'(])", text.strip())
    return [p for p in parts if re.search(r"[A-Za-z]", p)]


def words(sentence):
    return re.findall(r"[A-Za-z0-9][A-Za-z0-9'’/.\-]*", sentence)


def blocks(lines):
    """Yield (kind, first_line_number, text) for each prose block.

    kind is "procedure" (numbered item), "item" (bullet), "cell" (table),
    "heading" or "paragraph".
    """
    fence = False
    current = None   # [kind, line, [texts]]
    for number, raw in enumerate(lines, 1):
        line = raw.rstrip("\n")
        stripped = line.strip()
        if stripped.startswith(("```", "~~~")):
            fence = not fence
            if current:
                yield current
                current = None
            continue
        if fence or stripped.endswith("<!-- ste-ignore -->"):
            continue
        if not stripped:
            if current:
                yield current
                current = None
            continue
        if stripped.startswith("#"):
            if current:
                yield current
                current = None
            yield ["heading", number, [stripped.lstrip("#")]]
            continue
        if stripped.startswith("|"):
            if current:
                yield current
                current = None
            if re.fullmatch(r"[|:\-\s]+", stripped):
                continue
            for cell in stripped.strip("|").split("|"):
                yield ["cell", number, [cell]]
            continue
        numbered = re.match(r"\d+[.)]\s+(.*)", stripped)
        bullet = re.match(r"[-*+]\s+(.*)", stripped)
        if numbered or bullet:
            if current:
                yield current
            kind = "procedure" if numbered else "item"
            current = [kind, number, [(numbered or bullet).group(1)]]
            continue
        if stripped.startswith(">"):
            stripped = stripped.lstrip("> ")
        if current is None:
            current = ["paragraph", number, []]
        current[2].append(stripped)
    if current:
        yield current


def check_file(path):
    problems = []
    lines = path.read_text(encoding="utf-8").splitlines()
    for kind, number, texts in blocks(lines):
        text = clean(" ".join(texts))
        where = f"{path}:{number}"
        for match in FORBIDDEN_RE.finditer(text):
            problems.append(("E", where, f'forbidden word "{match.group(1)}"'))
        if kind == "heading":
            first = ING_START.match(text)
            if first and first.group(1) not in ING_OK:
                problems.append(("W", where, f'heading starts with "-ing" word "{first.group(1)}"'))
            continue
        found = sentences(text)
        limit = PROCEDURE_MAX if kind == "procedure" else DESCRIPTION_MAX
        for sentence in found:
            count = len(words(sentence))
            if count > limit:
                problems.append(("E", where, f"{count} words (max {limit}): {sentence[:70]}..."))
            if PASSIVE.search(sentence):
                problems.append(("W", where, f'possible passive "{PASSIVE.search(sentence).group(0)}"'))
            first = ING_START.match(sentence)
            if first and first.group(1) not in ING_OK:
                problems.append(("W", where, f'starts with "-ing" word "{first.group(1)}"'))
        if kind == "paragraph" and len(found) > PARAGRAPH_MAX:
            problems.append(("E", where, f"paragraph has {len(found)} sentences (max {PARAGRAPH_MAX})"))
    return problems


def markdown_files(arguments):
    root = Path.cwd()
    for argument in arguments:
        path = Path(argument)
        candidates = sorted(path.rglob("*.md")) if path.is_dir() else [path]
        for candidate in candidates:
            relative = "/" + str(candidate.resolve().relative_to(root)) if candidate.resolve().is_relative_to(root) else str(candidate)
            if any(fnmatch.fnmatch(relative, "*/" + pattern.lstrip("*/")) or fnmatch.fnmatch(relative, pattern)
                   for pattern in EXCLUDE):
                continue
            yield candidate


def main(argv):
    if len(argv) < 2:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    errors = warnings = 0
    for path in markdown_files(argv[1:]):
        for level, where, message in check_file(path):
            print(f"{where}: {level} {message}")
            errors += level == "E"
            warnings += level == "W"
    print(f"{errors} error(s), {warnings} warning(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
