---
name: vault-update-concept
description: Create or rewrite a concept page in the knowledge vault: the synthesized, current understanding of a subject, or a project's living architecture page. Use when the user says 'update my understanding of X', 'consolidate what I know about Y', 'my model of Z changed', 'rewrite the architecture page', or when enough findings have accumulated against a concept that it needs a review. Concepts are the one mutable layer: rewritten in place, with history in git. Not for atomic facts (vault-capture-finding) or choices (vault-capture-decision).
---

# vault-update-concept

Before you start: read `references/access.md` in this skill's folder. Then read the vault root `CLAUDE.md`.
This document describes only what is specific to this skill.

## Procedure

### Step 1: Read the current concept

Resolve the area. If the concept exists, read it.

### Step 2: Collect the inputs

1. List the findings of the area that link to this concept. Filesystem: `grep -rl "[[<slug>]]" <area>/findings`. MCP: `search_notes`.
2. Read the findings in `based_on`.
3. Read the notes that have this concept in `relates.contradicts`.

### Step 3: Draft the rewrite

The page is a synthesis. Do not paste finding bodies into it.

```markdown
---
type: concept
title:
area:
topics: []
projects: []             # projects where this understanding is applied
status: draft | current | needs_review
created: <original date>
updated: <today>
tags: []
needs_review: false
based_on: ["[[finding-a]]", "[[finding-b]]"]
relates:
  depends_on: []
  refines: []
---
# <title>

## Current understanding
<prose; the best synthesis as of today>

## Key points
- <three to seven>

## Where I am unsure
- <link open questions>

## Applied in
- [[<project>]]: <how>
```

### Step 4: Confirm and write

1. If the concept exists, show the change. If it is new, show the full page.
2. Wait for approval.
3. Write the note.
4. Set `needs_review: false`. Set `status: current` unless the user says it is a draft.
5. Set `based_on` to the findings that you used.
6. Append a log line.

### Step 5: Follow-ups

- If the rewrite resolved a contradiction, name the losing finding. Suggest a retraction via `vault-capture-finding`.
- If "Where I am unsure" names a gap with no question note, offer `vault-capture-question`.

## Project architecture page

`projects/<project>/concepts/architecture.md` is a concept with fixed sections:
Current understanding, Components, Data flow, Known weak points.
Rewrite it with the same procedure. Its `based_on` lists records and decisions.

## Rules

1. Do not remove a claim from the old page without saying so in the change summary.
2. Keep "Where I am unsure" honest. The learning path and `vault-capture-question` read it.
