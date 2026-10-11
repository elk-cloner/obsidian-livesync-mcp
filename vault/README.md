# Vault schema

This folder holds the schema: the structure of every knowledge vault on this
server. The backend moves the files. The schema tells what the files look
like. The skills in [`../skills`](../skills) read and write the files.

To set up the server and the first vault from the start, read
[`../docs/quickstart.md`](../docs/quickstart.md).

| Path | Content |
|---|---|
| [`template/`](template) | The files that `seed-vault.sh` copies into a new vault. |
| [`template/CLAUDE.md`](template/CLAUDE.md) | The schema itself: the contract between the vault and every skill. |
| [`template/README.md`](template/README.md) | The start page for a human, inside each vault. |
| [`examples/`](examples) | One topic and one project that use every note type. `seed-vault.sh` does not copy them. |

## Areas and notes

One vault has two kinds of areas:

- `topics/<slug>/` holds what you understand about a subject.
- `projects/<slug>/` holds what you built with it.

The two kinds of areas use the same note types: sources, findings, decisions,
concepts, questions, tasks and outputs. A project also has dated records and
a living architecture page.

Notes link to each other through their `topics` and `projects` fields. Thus
the Bases dashboards in `_bases/` can show where you applied each finding.
They can also show what you learned but did not use.

Findings and decisions are append-only. You rewrite a concept when your
understanding grows. The full rules are in
[`template/CLAUDE.md`](template/CLAUDE.md).

## Time

Every date and time in a vault is UTC: the frontmatter, the file names and the
log. Thus a phone and a laptop in different time zones always agree.

- Claude gets the time from the `vault_now` tool of the MCP server.
- On a local folder, Claude gets the time from `date -u`.

The dashboards filter on the `created` and `updated` fields. They do not use
the file times, because sync changes the file times on each device.

## Start a vault on the server

Run the scripts from `backend/`.

1. **YOU:** Add the vault: `sudo ./scripts/add-vault.sh <name>`. For the
   details, read [`backend/docs/vaults.md`](../backend/docs/vaults.md).
   - **SCRIPT:** The script waits while you connect the first device. Then it
     connects the vault to the server.
   - **SCRIPT:** If the vault has no `CLAUDE.md`, the script asks
     `Seed the knowledge vault schema now? [Y/n]`. Push Enter to seed it.
   - With the `--no-seed` option, or with no terminal, the script does not
     ask. It shows the seed command.
2. **YOU:** If you did not seed the schema in step 1, seed it now:
   `sudo ./scripts/seed-vault.sh <name>`.
3. **YOU:** On each device, set the two Obsidian settings below. Device
   settings do not sync.
   - **Settings → Core plugins → Templates → Template folder location:** `_templates`
   - **Settings → Files and links → Default location for new attachments:** `_attachments`
4. **YOU:** Create the first area. Ask Claude: "set up a topic for <subject>".
   The `vault-init-area` skill does this.

If the schema in this folder changes, refresh the copy in a vault:
`sudo ./scripts/seed-vault.sh <name> --upgrade`. This command replaces only
the root `CLAUDE.md`, `_templates/` and `_bases/`.

## Use a local folder

The skills also work on a plain folder. This needs no server and no Obsidian.
Run these commands from the root of the repository:

```bash
mkdir -p ~/knowledge && cp -R vault/template/. ~/knowledge/
sed -i.bak "s/YYYY-MM-DD HH:MM | seed-vault/$(date -u '+%Y-%m-%d %H:%M') | seed-vault/" ~/knowledge/log.md && rm ~/knowledge/log.md.bak
mkdir -p ~/.config/vault && echo ~/knowledge > ~/.config/vault/root
```

The `.gitignore` and `.gitkeep` files of the template are for a local folder.
With them, the folder can be a git repository of its own. In a vault on the
server, these files have no effect, because LiveSync does not sync dotfiles.

## Dotfiles and empty folders

LiveSync syncs notes, not folders. It does not sync a file if the name starts
with a dot. Thus on the devices:

- The `.obsidian/` settings of the template do not arrive. Set the two
  Obsidian settings above by hand.
- `.gitignore` and `.gitkeep` stay in the mirror on the server.
- An empty folder does not exist until it holds a note. The skills create a
  folder when they write the first note into it.

## Upgrade the schema

`CLAUDE.md` has a `Schema version:` line. A skill does not write to a vault
if the vault has a version that the skill does not expect.

To change the schema:

1. Edit the files in `template/`.
2. If the change breaks existing notes or skills, increase the version.
3. Update the skills to agree with the new schema.
4. On each vault, run `seed-vault.sh --upgrade`.
