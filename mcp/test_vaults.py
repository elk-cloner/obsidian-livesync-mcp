"""Adversarial checks on the vault sandbox.

Run with: python test_vaults.py   (no test framework needed)
Every case here is an attempt to read or write outside a vault.
"""
import os, sys, pathlib, tempfile

root = tempfile.mkdtemp(prefix="vaulttest-")
os.environ["VAULT_ROOT"] = root
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

V = pathlib.Path(root)
(V / "demo").mkdir()
(V / "demo" / "findings").mkdir()
(V / "demo" / "findings" / "a.md").write_text("alpha beta\nGAMMA line\n")
(V / "demo" / ".obsidian").mkdir()
(V / "demo" / ".obsidian" / "workspace.json").write_text("{}")
(V / "demo" / ".hiddennote.md").write_text("hidden")
(V / "secret.md").write_text("outside any vault")
(V / "demo" / "link").symlink_to(V / "secret.md")
(V / "demo" / "escapedir").symlink_to(V)
(V / ".dotvault").mkdir()

import vaults
from vaults import VaultError

passed = failed = 0
def ok(label, cond):
    global passed, failed
    if cond: passed += 1; print(f"  PASS {label}")
    else: failed += 1; print(f"  FAIL {label}")

def rejects(label, fn):
    try:
        fn(); ok(label, False)
    except VaultError as e:
        ok(f"{label}  [{e}]", True)

print("-- vault discovery")
ok("lists demo only (hidden vault excluded)", vaults.list_vaults() == ["demo"])
rejects("unknown vault", lambda: vaults.vault_dir("nope"))
rejects("dot-prefixed vault", lambda: vaults.vault_dir(".dotvault"))
rejects("vault name with slash", lambda: vaults.vault_dir("demo/findings"))
rejects("vault name '..'", lambda: vaults.vault_dir(".."))

print("-- path traversal")
rejects("../ escape", lambda: vaults.resolve("demo", "../secret.md"))
rejects("nested ../", lambda: vaults.resolve("demo", "findings/../../secret.md"))
rejects("absolute path", lambda: vaults.resolve("demo", "/etc/passwd"))
rejects("null byte", lambda: vaults.resolve("demo", "a\x00b.md"))
rejects("empty path", lambda: vaults.resolve("demo", ""))

print("-- symlinks")
rejects("symlink leaf -> outside", lambda: vaults.resolve("demo", "link"))
rejects("symlink dir in middle", lambda: vaults.resolve("demo", "escapedir/secret.md"))

print("-- reserved dirs")
rejects(".obsidian blocked", lambda: vaults.resolve("demo", ".obsidian/workspace.json"))
rejects(".git blocked", lambda: vaults.resolve("demo", ".git/config"))
rejects(".trash blocked", lambda: vaults.resolve("demo", ".trash/x.md"))

print("-- happy path")
base, target = vaults.resolve("demo", "findings/a.md")
ok("resolves inside vault", target == (V / "demo" / "findings" / "a.md").resolve())
ok("reads text", vaults.read_text(target, base).startswith("alpha"))
ok("relpath", vaults.relpath(target, base) == "findings/a.md")

print("-- listing skips hidden + reserved")
listed = sorted(vaults.relpath(p, base) for p in vaults.iter_files(base, base))
ok(f"iter_files == ['findings/a.md'] (got {listed})", listed == ["findings/a.md"])

print("-- atomic write")
base, target = vaults.resolve("demo", "new/deep/note.md")
n = vaults.write_atomic(target, "written\n")
ok("creates parents and writes", target.read_text() == "written\n" and n == 8)
leftovers = list((V / "demo" / "new" / "deep").glob(".livesync-mcp-*"))
ok(f"no staging files left behind (got {leftovers})", not leftovers)

print("-- write size cap")
vaults.MAX_WRITE_BYTES = 10
rejects("oversize write refused", lambda: vaults.write_atomic(target, "x" * 11))
vaults.MAX_WRITE_BYTES = 1_000_000

print("-- search")
base = vaults.vault_dir("demo")
hits = vaults.search(base, base, "gamma", regex=False, max_hits=10)
ok(f"case-insensitive substring hit (got {hits})",
   len(hits) == 1 and hits[0]["path"] == "findings/a.md" and hits[0]["line"] == 2)
hits = vaults.search(base, base, r"^alpha", regex=True, max_hits=10)
ok("regex anchored hit", len(hits) == 1 and hits[0]["line"] == 1)
rejects("invalid regex", lambda: vaults.search(base, base, "a[", regex=True, max_hits=5))
rejects("empty query", lambda: vaults.search(base, base, "", regex=False, max_hits=5))
hits = vaults.search(base, base, "a", regex=False, max_hits=1)
ok("max_hits honoured", len(hits) == 1)

print("-- trash")
base, target = vaults.resolve("demo", "findings/a.md")
dest = vaults.trash(target, base)
ok(f"moved into .trash (got {dest})", dest == ".trash/findings/a.md")
ok("original gone", not target.exists())
ok("trashed file readable", (base / ".trash/findings/a.md").read_text().startswith("alpha"))

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
