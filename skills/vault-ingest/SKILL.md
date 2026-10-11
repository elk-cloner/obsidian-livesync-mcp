---
name: vault-ingest
description: Turn an input (a book, course, paper, article, repository, video, or clipped web page) into a source note in the knowledge vault so findings can cite it with a location. Use when the user starts reading or using something ('I'm starting this textbook', 'ingest this paper', 'add this repo as a source', 'clip this article'), or when a finding cites a source that has no note yet. Produces metadata and a reading-notes stub; it does not summarize the source unless asked. Raw files go to _attachments and are linked.
---

# vault-ingest

Before you start: read `references/access.md` in this skill's folder. Then read the vault root `CLAUDE.md`.
This document describes only what is specific to this skill.

## Procedure

### Step 1: Resolve the area

- A source that teaches a subject goes in that topic.
- A repo that is part of a project goes in that project.
- If two topics use one book, put the note in the primary topic. Link it from the `CLAUDE.md` of the other topic.

### Step 2: Collect the metadata

If the input is a URL and a fetch tool is available, fetch the title and the author.
Otherwise ask. Do not guess the author or the year.

### Step 3: Choose the location scheme

| kind | location_scheme |
|---|---|
| book | chapter |
| paper, PDF | page |
| article | section |
| video, course | timestamp |
| repo | commit or path |

### Step 4: Store a raw file

If the user supplied a file (PDF, clipped markdown): store it at `_attachments/sources/<slug>.<ext>`. Embed it in the note.

### Step 5: Create the note

File: `sources/<slug>.md`.

```markdown
---
type: source
title:
area:
topics: []
projects: []
status: unread | reading | read | reference
created: <today>
updated: <today>
tags: []
kind: book | course | paper | article | repo | video
author:
url:
location_scheme:
---
# <title>

## What it is
<two sentences>

## Why I am reading it
<link the task, project or question>

## Reading notes
<informal and chronological; findings get their own notes and link here>
```

### Step 6: Finish

1. Add the source to "Sources in use" in the area `CLAUDE.md`.
2. Append a log line.
3. Offer a `kind: read` task via `vault-task`.
4. If the user asks for a summary, write it under "What it is". Do not create findings from it.

## Rules

1. Create a source note for any input that a finding will cite, even one article.
2. Use `status: reference` for inputs that the user consults but does not read in full.
3. Do not create findings on the user's behalf. The vault records what the user established.
