# Vault schema

The structure every knowledge vault on this server follows. The backend moves
the files; this schema says what the files look like; the skills in
[`../skills`](../skills) do the reading and writing.

| Path | What it is |
|---|---|
| [`template/`](template) | What `seed-vault.sh` copies into a new vault |
| [`template/CLAUDE.md`](template/CLAUDE.md) | The schema itself: the contract between the vault and every skill |
| [`template/README.md`](template/README.md) | The human start page inside a vault |
| [`examples/`](examples) | One topic and one project with every note type in use. Never seeded |

## The idea in one paragraph

One vault holds two kinds of areas. `topics/<slug>/` is what you understand
about a subject. `projects/<slug>/` is what you built with it. Both hold the
same note types (sources, findings, decisions, concepts, questions, tasks,
outputs), and projects add dated records and a living architecture page.
Notes cross-link through their `topics` and `projects` fields, so the Bases
dashboards in `_bases/` can show which findings were applied where, and what
you learned but never used. Findings and decisions are append-only; concepts
are rewritten as understanding grows. The full rules are in
[`template/CLAUDE.md`](template/CLAUDE.md).

## Time

Every date and time in a vault is UTC: frontmatter, file names, and the log.
Claude gets it from the MCP server's `vault_now` tool, or from `date -u` on a
local folder, so a phone and a laptop in different zones always agree.
Dashboards filter on the `created` and `updated` fields, never on file times,
which sync rewrites per device.

## Start a vault on the server

1. Add the vault: `sudo ./scripts/add-vault.sh <name>`, twice, as in
   [`backend/docs/vaults.md`](../backend/docs/vaults.md).
2. Seed it: `sudo ./scripts/seed-vault.sh <name>` (from `backend/`).
3. On each device, set two Obsidian options, because device settings do not
   sync:
   - **Settings → Core plugins → Templates → Template folder location:** `_templates`
   - **Settings → Files and links → Default location for new attachments:** `_attachments`
4. Create the first area by asking Claude: "set up a topic for <subject>"
   (the `vault-init-area` skill).

When the schema here changes, refresh a vault's copy with
`sudo ./scripts/seed-vault.sh <name> --upgrade`. It replaces only the root
`CLAUDE.md`, `_templates/` and `_bases/`.

## Use a local folder instead

The skills also work on a plain folder, with no server and no Obsidian:

```bash
mkdir -p ~/knowledge && cp -R vault/template/. ~/knowledge/
sed -i.bak "s/YYYY-MM-DD HH:MM | seed-vault/$(date -u '+%Y-%m-%d %H:%M') | seed-vault/" ~/knowledge/log.md && rm ~/knowledge/log.md.bak
mkdir -p ~/.config/vault && echo ~/knowledge > ~/.config/vault/root
```

The template's `.gitignore` and `.gitkeep` files are for this case: the folder
can be a git repository of its own. On the server they are inert, because
LiveSync does not sync dotfiles.

## Dotfiles and empty folders

LiveSync syncs notes, not folders, and skips files whose names start with a
dot. So on devices:

- `.obsidian/` settings from the template never arrive. Set the two options above by hand.
- `.gitignore` and `.gitkeep` stay on the server copy only.
- An empty folder does not exist until it holds a note. The skills create
  folders by writing the first note into them.

## Upgrading the schema

`CLAUDE.md` carries a `Schema version:` line, and the skills refuse to write to
a vault whose version they do not expect. To change the schema, edit
`template/`, bump the version if the change breaks existing notes or skills,
update the skills to match, then run `seed-vault.sh --upgrade` on each vault.
