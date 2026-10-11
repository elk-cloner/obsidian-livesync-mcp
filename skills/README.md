# Vault skills

This folder has thirteen Claude skills. They read and write a knowledge vault
that follows the schema in
[`../vault/template/CLAUDE.md`](../vault/template/CLAUDE.md).

The skills run on Claude Code and on claude.ai (web, iPhone, iPad). They use
the vault MCP server or a local folder.

## Skills

| Skill | Writes to | Purpose |
|---|---|---|
| `vault-init-area` | new area | Create a topic or a project |
| `vault-where` | nothing | Find the type and the area of a piece of information |
| `vault-capture-finding` | findings/ | Create one finding |
| `vault-capture-decision` | decisions/ | Create one decision; supersede an old decision |
| `vault-capture-record` | records/ | Create one dated event in a project |
| `vault-capture-question` | questions/ | Open, answer or drop a question |
| `vault-update-concept` | concepts/ | Rewrite one concept |
| `vault-task` | tasks/ | Create, update, complete and list tasks |
| `vault-ingest` | sources/ | Create one source note |
| `vault-brief` | outputs/ (optional) | Answer from the vault; file the answer if you ask |
| `vault-lint` | lint-report.md | Run structural lint; propose semantic fixes |
| `vault-session` | many | Review a session; write the approved items |
| `vault-learning-path` | learning-path.md | Keep the ordered tutorial of a topic |

## Which skill

| You say | Skill |
|---|---|
| Something is true | `vault-capture-finding` |
| I chose something | `vault-capture-decision` |
| Something happened in a project | `vault-capture-record` |
| I do not know something | `vault-capture-question` |
| My understanding changed | `vault-update-concept` |
| I must do something | `vault-task` |
| I started to read or use something | `vault-ingest` |
| What do I know about X | `vault-brief` |
| Is the vault healthy | `vault-lint` |
| Wrap up | `vault-session` |
| Where does this go | `vault-where` |

## Access to the vault

Each skill first reads `references/access.md`. Then it reads the root
`CLAUDE.md` of the vault. The skill uses one of two access modes:

| Mode | When | Vault | Dates |
|---|---|---|---|
| **MCP mode** | The vault connector is available. This is the mode on claude.ai. | The skill calls `list_vaults`. If there is one vault, it uses that vault. If not, it asks which vault. | From `vault_now` |
| **Filesystem mode** | The connector is not available. | The root of the vault is the one line in `~/.config/vault/root`. | From `date -u` |

In both modes, the note `_state/current-area.md` holds the current area. Thus
all devices agree on the current area. All dates and times are UTC.

## Install on Claude Code

1. Run these commands in a terminal:

   ```bash
   claude plugin marketplace add elk-cloner/obsidian-livesync-mcp
   claude plugin install vault@obsidian-livesync-mcp
   ```

   **Result:** The skills show as `vault:vault-brief`, `vault:vault-task`
   and so on.
2. For MCP mode, add the connector (`https://mcp.<domain>/mcp`) in claude.ai.
   Claude Code uses the connectors of claude.ai.
3. For filesystem mode, set up a local folder. Read
   [`../vault/README.md`](../vault/README.md).

To update an installed plugin, run these commands:

```bash
claude plugin marketplace update obsidian-livesync-mcp
claude plugin update vault@obsidian-livesync-mcp
```

To try the skills of a checkout with no installation, run this command:

```bash
claude --plugin-dir ./skills
```

## Install on claude.ai

Several new skills use the names of old skills. Thus you must remove the old
skills before you upload the new skills.

1. In **Settings → Capabilities → Skills**, remove the old `vault-*` skills.
2. Download the zips from the latest release:
   <https://github.com/elk-cloner/obsidian-livesync-mcp/releases/latest>.
   - The link to one zip is
     `https://github.com/elk-cloner/obsidian-livesync-mcp/releases/latest/download/<skill>.zip`.
   - **If it fails:** Build the zips from a checkout. Run
     `python3 skills/tools/build.py package`. This command writes one zip for
     each skill into `dist/`.
3. In **Settings → Capabilities → Skills**, upload each zip.
4. Make sure that the same account has the vault connector, and that the
   connector is enabled.

If the skills change, upload the changed zips again.

## Edit the skills

- The shared rules are in one file:
  [`_shared/access.md`](_shared/access.md). Each skill has a copy in
  `references/`, because a claude.ai zip cannot read files outside its own
  folder. After you edit `_shared/`, run this command:

  ```bash
  python3 skills/tools/build.py sync
  ```

- `python3 skills/tools/build.py check` fails in these conditions:
  - A copy in `references/` is different from `_shared/`.
  - A `SKILL.md` breaks the claude.ai limits. The name must be lowercase with
    hyphens, at most 64 characters, the same as the folder, and start with
    `vault-`. The description must be at most 1,024 characters.
- `vault-lint/scripts/lint.py` is the only lint implementation. The MCP server
  puts it into its image for the `lint_vault` tool. Thus a change here goes to
  the server at the next `docker compose build mcp`.
- The vault `CLAUDE.md` has priority over each skill. Change the schema there
  first.

## Release (maintainers)

A GitHub workflow (`.github/workflows/skills-release.yml`) publishes the
skills. To release a new version:

1. In `skills/.claude-plugin/plugin.json`, increase `version`.
2. Commit the change.
3. Tag the commit and push the tag:

   ```bash
   git tag skills-vX.Y.Z && git push origin skills-vX.Y.Z
   ```

   **Result:** The workflow starts. It does these steps:
   - **SCRIPT:** It checks that the tag agrees with the version
     (`python3 skills/tools/build.py check --tag skills-vX.Y.Z`).
   - **SCRIPT:** It builds the zips.
   - **SCRIPT:** It creates a GitHub release for the tag, with the zips.

   **If it fails:** If a release for the tag exists, the workflow stops. It
   does not overwrite a release. Delete the release, or tag a new version.
