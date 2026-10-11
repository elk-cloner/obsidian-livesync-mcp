---
name: vault-capture-record
description: Capture a dated event in a project to the knowledge vault: a milestone, an experiment and its result, an incident, a meeting, a measurement. Use when the user reports something that happened: 'ran the benchmark, got X', 'deployed v2 today', 'ingestion broke last night', 'first end-to-end run worked'. Records are append-only and live only in projects. If the event also establishes a general fact, file that fact separately with capture-finding. Not for topics, decisions or tasks.
---

# vault-capture-record

Before you start: read `references/access.md` in this skill's folder. Then read the vault root `CLAUDE.md`.
This document describes only what is specific to this skill.

## Procedure

### Step 1: Resolve the project

A record goes in a project only.
If the current area is a topic, ask which project the event belongs to.

### Step 2: Draft the note

File: `records/YYYY-MM-DD-<slug>.md`. Use the event date in the file name.

```markdown
---
type: record
title: <what happened>
area: projects/<project>
topics: []                 # topics whose methods were used
projects: [<project>]
status: none
created: <today>
updated: <today>
tags: []
date: <event date>
kind: milestone | experiment | incident | meeting | result
---
# <title>

## What happened

## Result / numbers
<exact values with units; comparison to the previous value if known>

## Follow-ups
<tasks created, or "none">
```

### Step 3: Confirm and write

1. Show the full note and the path.
2. Wait for approval.
3. Write the note.
4. Append a log line.

### Step 4: Follow-ups

Give each follow-up as one line. Give it only if the condition is true.

- If the result is a general truth: offer `vault-capture-finding`.
- If the event produced work: offer `vault-task`.
- If the event changed the architecture: offer `vault-update-concept` for `concepts/architecture.md`.
- If the event answered an open question: offer `vault-capture-question`.

## Rules

1. Write numbers exactly as the user gave them. Do not round them.
2. For an experiment, state what was varied and what was held fixed. If the user did not say, ask once. Do not invent it.
