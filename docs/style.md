# Writing style

All documentation in this repository uses a project subset of
**ASD-STE100 Simplified Technical English** (STE). STE makes text easy to read
for all readers, also for readers whose first language is not English.

The vault schema (`vault/template/CLAUDE.md`, section 11) and the skills use
the same rules.

Run the checker before you commit a document:

```bash
python3 docs/tools/ste_check.py README.md docs backend vault skills
```

## 1. Words

1. Use one word for one meaning. Use the terms in the glossary (section 6).
   Do not use a synonym for a glossary term.
2. Use the simple word: "use", not "utilize". "Start", not "initiate".
3. You can use technical names as they are: commands, file names, settings,
   product names and error messages. Write them as `code` if you can.
4. Do not use these words: "should", "simply", "just", "please", "easily",
   "obviously", "basically", "really", "very", "etc.".
5. Do not use a group of more than three nouns. Write "the folder of the
   vault", not "the vault mirror folder path".
6. Use "a", "an" and "the". Do not leave them out.

## 2. Verbs

1. Use the imperative in a procedure: "Run the script."
2. Use the active voice: "The bridge writes the file." Not: "The file is
   written by the bridge."
3. Use the simple present tense. Use the past or the future only if the
   meaning needs them.
4. Do not use an "-ing" word as a noun or as a verb. Write "To add a vault",
   not "Adding a vault".
5. Use "do not" for a prohibition. Do not use "never" or "avoid".

## 3. Sentences

1. Write one instruction in one sentence.
2. Keep a procedure sentence to 20 words or less.
3. Keep a description sentence to 25 words or less.
4. Put the condition first: "If the check fails, run `doctor.sh`."
5. Put a warning before the step that it applies to, not after it.

## 4. Procedures

1. Write a procedure as a numbered list. One step is one action.
2. If it helps the reader, give each step three parts:
   - **Do this:** the action.
   - **Result:** what the reader sees when the action is correct.
   - **If it fails:** what to do, or the document to read.
3. Mark who does a step. The **SCRIPT** label means a script does it. The
   **YOU** label means the reader does it by hand.

## 5. Descriptions

1. Start with the most important information.
2. Write one topic in one paragraph.
3. Keep a paragraph to six sentences or less.
4. Use a table or a list for a comparison or for options.

## 6. Glossary

| Term | Meaning |
|---|---|
| server | The VPS that runs the backend. |
| backend | The services in `backend/`: CouchDB, the bridge, the MCP server, Caddy and the timers. |
| vault | One Obsidian vault. It has one CouchDB database and one folder on the server. |
| device | A computer, phone or tablet that runs Obsidian with Self-hosted LiveSync. |
| first device | The device that connects to a new vault first. It writes the LiveSync settings of the vault. |
| database | The CouchDB database of one vault. Its content is end-to-end encrypted. |
| bridge | The livesync-bridge service. It copies notes between the database and the mirror. |
| mirror | The plain-file copy of a vault on the server: `/srv/vaults/<vault>`. |
| MCP server | The service that gives Claude access to the mirror. |
| connector | The entry for the MCP server in claude.ai. |
| Setup URI | One encrypted string that sets up LiveSync on a device. |
| passphrase | The end-to-end encryption key, `LIVESYNC_PASSPHRASE`. |
| schema | The vault structure in `vault/template/`. `seed-vault.sh` copies it into a vault. |
| skill | One Claude skill in `skills/`. |
| history | The git repository of a vault in `/srv/git/<vault>.git`. |
| backup | The nightly copy of every mirror to Google Drive. |

## 7. Exceptions

If a sentence must break a rule, put `<!-- ste-ignore -->` at the end of the
line. Use this only for a quoted message or a name that you cannot change.
