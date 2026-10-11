# Vault schema

Schema version: 3

This document is the contract between the vault and every skill.
Read this document before you write to the vault.
If a skill and this document disagree, obey this document.

Writing rules for this document and for all skills: see section 11.

## 1. Glossary

Use these terms. Do not use synonyms for them.

| Term | Meaning |
|---|---|
| vault | The one Obsidian folder that holds everything. |
| area | One folder under `topics/` or under `projects/`. |
| topic | An area that holds what I understand about a subject. |
| project | An area that holds what I built. |
| note | One markdown file with frontmatter. |
| type | The value of the `type` field of a note. |
| field | One key in the frontmatter of a note. |
| link | A `[[slug]]` reference to a note or to an area. |
| relation | A typed link in the `relates` field. |
| skill | One procedure that reads or writes the vault. |
| log | The file `log.md` at the vault root. |
| dashboard | One `.base` file (Obsidian Bases). |
| marker | The note `_state/current-area.md`. It names the current area. |
| create | Make a new note. |
| append | Add text to the end of a note. Do not change existing text. |
| rewrite | Replace the body of a note. |
| retract | Set a finding to `status: retracted`. |
| supersede | Create a new note that replaces an old note, and mark the old note. |

## 2. Layout

```
topics/<topic>/       areas of type topic
projects/<project>/   areas of type project
_templates/           one template per type
_bases/               dashboards
_attachments/         images, PDFs, clipped files
_state/               the marker; nothing else
log.md                append-only operation log
lint-report.md        output of the lint script
```

Topics and projects are peers.
A project can use many topics.
A topic can feed many projects.
Link them with the `topics` field and the `projects` field. Do not nest them.

Every area has this layout:

```
CLAUDE.md     scope, current state, gaps
README.md     entry point for a human
<area>.base   dashboard of the area
sources/      inputs: books, courses, articles, repos, papers
findings/     facts; append-only
decisions/    choices with reasons; append-only
concepts/     synthesized understanding; rewritten in place
questions/    open questions
tasks/        work to do
outputs/      filed briefs and answers
```

A topic also has `learning-path.md`.
A project also has `records/` and `concepts/architecture.md`.

## 3. Placement rule

Put a note in the area that its content is about.
Do not put a note in the area that you were working in.

- If the content is true without this project, put it in the topic.
- If the content is about this repository, this dataset or this deployment, put it in the project.
- A decision about how to think goes in the topic.
- A decision about how this code does it goes in the project.

Fill the `topics` field and the `projects` field on every note. These fields carry the cross-link.

## 4. Types

| type | mutability | folder | status values |
|---|---|---|---|
| source | append | sources/ | unread, reading, read, reference |
| finding | append-only | findings/ | unverified, verified, retracted |
| decision | append-only | decisions/ | active, superseded |
| concept | rewrite | concepts/ | draft, current, needs_review |
| question | append | questions/ | open, answered, dropped |
| task | update | tasks/ | todo, doing, blocked, done |
| record | append-only | records/ | none |
| output | append | outputs/ | draft, final, stale |
| learning-path | rewrite | area root | draft, current |

Append-only means: do not change the body after you create the note.
To correct a finding, retract it and create a new finding with `supersedes`.
To change a decision, supersede it.
Only one edit is permitted on an append-only note: the status change that retracts or supersedes it.

## 5. Fields

### 5.1 Required on every note

```yaml
type: finding
title: One declarative sentence
area: topics/graph-theory
topics: [graph-theory]
projects: []
status: unverified
created: 2026-10-11
updated: 2026-10-11
tags: []
```

Rules:
- `area` is the folder that holds the note.
- `topics` lists the topics that the note concerns. The list can be empty for a pure project note.
- `projects` lists the projects that the note applies to. The list can be empty.
- `created` and `updated` are ISO dates in UTC.

### 5.2 Required per type

| type | fields |
|---|---|
| source | `kind` (book, course, paper, article, repo, video), `author`, `url`, `location_scheme` (chapter, page, section, timestamp, commit, path) |
| finding | `source` (link or empty), `location`, `confidence` (low, medium, high), `supersedes`, `relates` |
| decision | `supersedes`, `superseded_by`, `relates` |
| concept | `needs_review` (true, false), `based_on` (list of links), `relates` |
| question | `blocks` (list of task links), `answered_by` (finding link or empty) |
| task | `kind` (read, exercise, build, review, investigate), `blocked_by` (question link or empty), `due` |
| record | `date` (event date), `kind` (milestone, experiment, incident, meeting, result) |
| output | `question` (text), `drew_on` (list of links) |

### 5.3 Relations

```yaml
relates:
  supports: []
  contradicts: []
  refines: []
  depends_on: []
```

Use only these four relation types and `supersedes`.
Do not add a relation type in a note. Propose it in this document first.

## 6. File names

- finding, decision, record, output: `YYYY-MM-DD-<slug>.md`
- all other types: `<slug>.md`
- A slug is lowercase ASCII with hyphens.
- A record uses the event date, not the creation date.

## 7. Time

1. Write every date and every time in UTC.
2. If the MCP tools are available, get the date and the time from `vault_now`.
3. If you work on the filesystem, run `date -u`.
4. Do not guess a date. Do not use a local time zone.

`created`, `updated`, `date`, `due`, file names and log lines all follow this rule.

## 8. Marker

The marker is the note `_state/current-area.md`. Every device reads the same marker.

```markdown
---
area: topics/graph-theory
updated: 2026-10-11
---
```

1. Set the marker when the user switches area or creates an area.
2. Do not write anything else under `_state/`.

## 9. Write rules for skills

1. Read the `CLAUDE.md` of the area before you write to the area.
2. Create or append by default.
3. Rewrite only these notes: `concepts/*`, `learning-path.md`, `README.md` of an area, `CLAUDE.md` of an area, the marker.
4. Before you rewrite a concept, show the change to the user. Wait for approval.
5. After every write, append one line to the log. The time is UTC:
   `- YYYY-MM-DD HH:MM | <skill> | <created|updated|retracted|superseded> | [[<slug>]]`
   Do not log a marker change.
6. Do not maintain an index file. Dashboards read the fields.
7. Fill `topics` and `projects` on every note. If you cannot infer them, ask.
8. Do not delete a note. Retract it, supersede it, or set `status: dropped`.
9. Do not create a link to a note that does not exist.

## 10. Lint

Structural lint is a script. It is deterministic. It writes `lint-report.md`. It checks:
missing fields, invalid status, broken links, orphans, findings without `source`,
superseded decisions that are still linked as active, tasks blocked by a question that is not open,
outputs whose `drew_on` notes changed, concepts with three or more newer findings, `area` that does not match the folder.

Semantic lint is a skill procedure. It proposes changes. It does not apply them without approval. It checks:
contradictions between findings, concepts that are behind their findings, decisions whose basis changed,
outputs that are stale, area `CLAUDE.md` that is behind the notes.

## 11. Writing rules for operating documents

These rules apply to this document, to every area `CLAUDE.md`, and to every skill.
They do not apply to the body of a note.

1. Write one instruction per sentence.
2. Use the imperative for procedures: "Read the note." Not: "The note should be read."
3. Use the active voice and the present tense.
4. Keep a sentence under 20 words.
5. Put the condition first: "If X, do Y." Not: "Do Y unless X."
6. Use the glossary terms. Do not use a synonym for a glossary term.
7. Use "do not" for prohibitions. Do not use "never" or "avoid".
8. Write lists for sequences and for options. Write prose for explanations only.
