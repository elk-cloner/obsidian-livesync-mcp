# Obsidian knowledge vault: self-hosted sync, schema, and Claude skills

A knowledge vault you own, that Claude can read and write from any surface.
Three parts, kept together because each depends on the others:

| Part | What it is | Start here |
|---|---|---|
| [`backend/`](backend) | Self-hosted sync for Obsidian (CouchDB + LiveSync), a plain-file mirror on the server, git history, Drive backup, and an MCP server that gives Claude access | [`backend/README.md`](backend/README.md) |
| [`vault/`](vault) | The vault schema: folder layout, note types, frontmatter, templates, dashboards, and worked examples | [`vault/README.md`](vault/README.md) |
| [`skills/`](skills) | Claude skills that capture, synthesize and lint notes according to the schema, on Claude Code and claude.ai | [`skills/README.md`](skills/README.md) |

## How they fit

```
 Obsidian on your devices ──LiveSync──▶ CouchDB ◀──bridge──▶ /srv/vaults/<vault>  (plain files)
                                                                  ▲
 Claude (web, phone, Claude Code) ──skills──▶ MCP server ─────────┘
                                                 │
                       vault/template ──seed-vault.sh──▶ CLAUDE.md, _templates, _bases
```

- The **backend** moves files between your devices, the server mirror, and Claude.
- The **schema** is seeded into each vault as its root `CLAUDE.md` plus templates
  and dashboards. Every note follows it.
- The **skills** tell Claude how to work inside the schema: which note type a
  piece of information is, where it goes, and what to confirm before writing.
  The MCP server adds two tools they rely on: `vault_now` for UTC timestamps
  and `lint_vault` for structural checks.

The skills also work on a plain local folder without the backend; see
[`vault/README.md`](vault/README.md).

## Set it up, in order

1. **Backend:** [`backend/docs/setup.md`](backend/docs/setup.md). One-time
   server setup with no vaults.
2. **A vault:** [`backend/docs/vaults.md`](backend/docs/vaults.md). Add it with
   `add-vault.sh`, then put the schema in with `seed-vault.sh`.
3. **Devices:** [`backend/docs/onboarding.md`](backend/docs/onboarding.md), and
   the two per-device Obsidian settings in [`vault/README.md`](vault/README.md).
4. **Skills:** [`skills/README.md`](skills/README.md), for Claude Code and
   claude.ai.

## Tests

```bash
python backend/mcp/test_vaults.py        # MCP path sandbox
python backend/mcp/test_lint.py          # lint on the template and examples (needs PyYAML)
python3 skills/tools/build.py check      # skills valid and self-contained
```

Configuration, schema and code only: **no vault content ever lives in this repo.**
