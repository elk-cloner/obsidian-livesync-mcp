"""Checks on the vault lint, the code behind the lint_vault tool.

Run with: python test_lint.py   (needs PyYAML; no test framework)

The lint lives in skills/vault-lint/scripts/lint.py. This loads it the same
way server.py does in a checkout, so the tool and the skill test one file.
"""
import importlib.util
import shutil
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
LINT = REPO / "skills" / "vault-lint" / "scripts" / "lint.py"

spec = importlib.util.spec_from_file_location("vault_lint", LINT)
vault_lint = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vault_lint)

passed = failed = 0


def ok(label, cond):
    global passed, failed
    if cond:
        passed += 1
        print(f"  PASS {label}")
    else:
        failed += 1
        print(f"  FAIL {label}")


def seeded(with_examples):
    """A temp vault: the template, plus the example areas if asked."""
    root = Path(tempfile.mkdtemp(prefix="linttest-")) / "vault"
    shutil.copytree(REPO / "vault" / "template", root)
    if with_examples:
        shutil.copytree(REPO / "vault" / "examples", root, dirs_exist_ok=True)
    return root


print("-- clean vaults")
report, issues, count = vault_lint.lint(seeded(False))
ok(f"template alone: no notes, no issues (got {count}, {issues})", count == 0 and not issues)

root = seeded(True)
report, issues, count = vault_lint.lint(root)
ok(f"template + examples: notes found (got {count})", count > 0)
ok(f"template + examples: no issues (got {issues})", not issues)
ok("report says no issues", "No issues." in report)
ok("report is dated in UTC", "(UTC)" in report)

print("-- planted problems")
finding = root / "topics/graph-theory/findings/2026-01-01-dijkstra-needs-non-negative-weights.md"
text = finding.read_text()
finding.write_text(text.replace("status: verified", "status: maybe").replace("[[weighted-graph]]", "[[no-such-note]]"))
report, issues, count = vault_lint.lint(root)
ok(f"invalid status caught (got {issues.get('invalid_status')})", len(issues.get("invalid_status", [])) == 1)
ok(f"broken link caught (got {issues.get('broken_link')})",
   any("no-such-note" in item for item in issues.get("broken_link", [])))

stray = root / "topics/graph-theory/concepts/misplaced.md"
stray.write_text(text.replace("area: topics/graph-theory", "area: projects/route-planner"))
_, issues, _ = vault_lint.lint(root)
ok("area mismatch caught", any("misplaced.md" in i for i in issues.get("area_mismatch", [])))

print("-- skipped content")
(root / ".trash").mkdir()
(root / ".trash" / "junk.md").write_text("no frontmatter")
(root / "_state").mkdir()
(root / "_state" / "current-area.md").write_text("---\narea: topics/graph-theory\n---\n")
(root / "loose.md").symlink_to(finding)
_, issues, _ = vault_lint.lint(root)
missing = issues.get("missing_frontmatter", [])
ok(f"hidden folders, _state and symlinks are not linted (got {missing})", not missing)

print("-- CLI")
out = vault_lint.main(["lint.py", str(root)])
ok("CLI exits 1 when issues exist", out == 1)
ok("CLI writes lint-report.md", (root / vault_lint.REPORT_NAME).is_file())

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
