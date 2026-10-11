# Vault access

Every vault skill obeys this document.
The vault root `CLAUDE.md` defines the glossary, the schema and the write rules.
If this document and the vault `CLAUDE.md` disagree, obey the vault `CLAUDE.md`.

This file is copied into every skill from `skills/_shared/access.md` in the repository. Edit it there.

## 1. Choose the access mode

Use one mode for the whole session. Do not mix two vault roots.

1. If the vault MCP tools are available (`list_vaults`, `read_note`, `write_note`), use MCP mode.
2. Otherwise use filesystem mode.

## 2. Find the vault

### MCP mode

1. Call `list_vaults`.
2. If it lists one vault, use it.
3. If it lists more than one vault, ask the user which one. Ask once per session.
4. Paths are relative to the vault root.
5. Read with `read_note`, `search_notes` and `list_notes`. Write with `write_note` and `append_note`.
6. Before you overwrite a note, read it with `read_note`.

### Filesystem mode

1. The vault root is the one line in `~/.config/vault/root`.
2. If that file is missing, ask the user for the path. Offer to write the file.
3. Write a new note with a quoted heredoc: `cat > file <<'EOF'`.

### Confirm the schema

Read the vault root `CLAUDE.md` once per session.
If it does not contain the line `Schema version: 3`, stop. Tell the user that this vault does not follow the schema these skills expect.

## 3. Find the area

Resolve the area in this order:

1. The user named the area.
2. The conversation makes the area obvious.
3. The marker names the area. The marker is the note `_state/current-area.md` in both modes.
4. None of the above: list `topics/` and `projects/`. Ask the user. Offer to set the marker.

Before you write to an area, read its `CLAUDE.md`.

## 4. Get the date and the time

All dates and times are UTC. `<today>` in a skill means the UTC date.

- MCP mode: call `vault_now`. Use its `date` for fields and file names. Use its `log_time` for log lines.
- Filesystem mode: run `date -u +%Y-%m-%d` for the date. Run `date -u '+%Y-%m-%d %H:%M'` for a log line.

Do not guess a date. Do not use the date from the conversation. Do not use a local time zone.

## 5. Write

Follow section "Write rules for skills" of the vault `CLAUDE.md`. In short:

1. Create or append by default. Rewrite only the notes that the vault `CLAUDE.md` lists.
2. After every write, append one line to `log.md` at the vault root.
3. Do not delete a note.
4. Do not create a link to a note that does not exist. If a note is missing, leave the field empty. Tell the user which note is missing.

In MCP mode, a folder appears with its first note. Do not create empty folders.
If `list_notes` returns nothing for a folder, the folder has no notes yet.

## 6. Find valid link targets

Before you fill `source`, `relates`, `based_on`, `blocks`, `answered_by` or `drew_on`:

1. List the relevant folders of the area. Filesystem: `ls`. MCP: `list_notes` with `subpath`.
2. If `topics` or `projects` point to another area, list the `concepts/` folder of that area too.
3. Use only the notes that you listed.

## 7. Confirm before you write

- finding, decision, record: show the full note and the path. Wait for approval. Then write.
- concept rewrite: show the change. Wait for approval. Then write.
- task, question, source, status change: write directly if the user asked for it and the content is clear. Otherwise show the note first.
