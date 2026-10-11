# Vault skills

Thirteen Claude skills that read and write a knowledge vault following the
schema in [`../vault/template/CLAUDE.md`](../vault/template/CLAUDE.md). They run
on Claude Code and on claude.ai (web, iPhone, iPad), through the vault MCP
server or on a local folder.

## Skills

| Skill | Writes to | Purpose |
|---|---|---|
| `vault-init-area` | new area | Create a topic or a project |
| `vault-where` | nothing | Decide the type and the area of a piece of information |
| `vault-capture-finding` | findings/ | Create one finding |
| `vault-capture-decision` | decisions/ | Create one decision; supersede an old one |
| `vault-capture-record` | records/ | Create one dated event in a project |
| `vault-capture-question` | questions/ | Open, answer or drop a question |
| `vault-update-concept` | concepts/ | Rewrite one concept |
| `vault-task` | tasks/ | Create, update, complete, list tasks |
| `vault-ingest` | sources/ | Create one source note |
| `vault-brief` | outputs/ (optional) | Answer from the vault; file the answer on request |
| `vault-lint` | lint-report.md | Run structural lint; propose semantic fixes |
| `vault-session` | many | Review a session; write approved items |
| `vault-learning-path` | learning-path.md | Maintain the ordered tutorial of a topic |

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

## How they reach the vault

Every skill first reads `references/access.md`, then the vault's root
`CLAUDE.md`.

- **MCP mode** is used whenever the vault MCP connector is available. The skill
  calls `list_vaults`, uses the only vault or asks which one, and takes dates
  from `vault_now`. This is the mode on claude.ai.
- **Filesystem mode** is the fallback. The vault root is the one line in
  `~/.config/vault/root`, and dates come from `date -u`.

Both modes keep the current area in the note `_state/current-area.md`, so
every device agrees on it. All dates and times are UTC.

## Install on Claude Code

From the terminal:

```bash
claude plugin marketplace add elk-cloner/obsidian-livesync-mcp
claude plugin install vault@obsidian-livesync-mcp
```

The skills then appear as `vault:vault-brief`, `vault:vault-task`, and so on.
To try a checkout without installing anything:

```bash
claude --plugin-dir ./skills
```

For MCP mode, add the connector (`https://mcp.<domain>/mcp`) in claude.ai; Claude
Code picks up claude.ai connectors. Otherwise set up a local folder as in
[`../vault/README.md`](../vault/README.md).

## Install on claude.ai

1. Remove the old `vault-*` skills first, in **Settings → Capabilities →
   Skills**. Several new skills reuse their names.
2. Build the zips:

   ```bash
   python3 skills/tools/build.py package
   ```

   That writes one zip per skill into `dist/`.
3. Upload each zip in **Settings → Capabilities → Skills**.
4. Make sure the vault connector is added and enabled in the same account.

Re-upload the changed zips after pulling skill changes.

## Editing the skills

- Shared rules live once in [`_shared/access.md`](_shared/access.md). Each
  skill carries a copy in `references/`, because a claude.ai zip cannot reach
  outside its own folder. After editing `_shared/`, run:

  ```bash
  python3 skills/tools/build.py sync
  ```

- `python3 skills/tools/build.py check` fails if a copy drifted, or if a
  `SKILL.md` breaks the claude.ai limits: name lowercase with hyphens, at most
  64 characters, matching the folder and starting with `vault-`; description at
  most 1,024 characters.
- `vault-lint/scripts/lint.py` is the only lint implementation. The MCP server
  builds it into its image for the `lint_vault` tool, so a change here reaches
  the server on its next `docker compose build mcp`.
- The vault `CLAUDE.md` wins over any skill. Change the schema there first.
