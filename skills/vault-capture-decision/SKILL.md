---
name: vault-capture-decision
description: Capture a decision with its context, alternatives and consequences to the knowledge vault as an append-only note, and manage the supersede chain when the user changes their mind. Use when the user says 'I've decided', 'we're going with', 'log this choice', 'record why I chose', or commits to an approach, tool, model, study order or interpretation. Works for topic-level decisions (how to think) and project-level ones (how this code does it). Not for facts (vault-capture-finding) or events (vault-capture-record).
---

# vault-capture-decision

Before you start: read `references/access.md` in this skill's folder. Then read the vault root `CLAUDE.md`.
This document describes only what is specific to this skill.

## Procedure

### Step 1: Resolve the area

- If the decision is about how this project does it: project.
- If the decision is about how the user approaches the subject: topic.

### Step 2: Check for an active decision on the same question

Search `decisions/` of the area.
If an active decision exists on the same question, this is a supersede. Go to step 5 after step 4.

### Step 3: Draft the note

File: `decisions/YYYY-MM-DD-<slug>.md`.

```markdown
---
type: decision
title: <what was decided>
area:
topics: []
projects: []
status: active
created: <today>
updated: <today>
tags: []
supersedes:              # "[[old]]" if this replaces a decision
superseded_by:
relates:
  depends_on: []         # findings or concepts that justify the decision
---
# <title>

## Context
<the situation that forced a choice>

## Decision
<what was chosen>

## Alternatives considered
- <option>: <why not>

## Consequences
<what becomes easier; what becomes harder>
```

### Step 4: Confirm and write

1. Show the full note and the path.
2. Wait for approval.
3. Write the note.
4. Append a log line.

### Step 5: Supersede the old decision

1. Set the old note to `status: superseded` and `superseded_by: "[[<new>]]"`. This is the only permitted edit.
2. Append a log line for the old note.
3. Search the vault for links to the old note. List them to the user.

## Rules

1. Alternatives are required. If the user gives none, ask once. If still none, write "none considered".
2. Fill `depends_on` with the findings or concepts that justify the decision, if they exist. Semantic lint uses this field.
