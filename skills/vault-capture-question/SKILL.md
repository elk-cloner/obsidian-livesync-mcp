---
name: vault-capture-question
description: Open, answer, or drop a question in the knowledge vault. Use when the user says 'I don't understand X yet', 'open question', 'need to figure out', 'this is the missing piece', or when a new finding answers a question that was open. Questions are the gap list: Bases show them, tasks can be blocked by them, and the learning path draws its next step from them. Not for tasks (vault-task) or facts (vault-capture-finding).
---

# vault-capture-question

Before you start: read `references/access.md` in this skill's folder. Then read the vault root `CLAUDE.md`.
This document describes only what is specific to this skill.

## Open a question

### Step 1: Resolve the area

A question about a method goes in the topic, even if it came up in a project.

### Step 2: Check for a duplicate

Search `questions/` of the area.
If an open question on the same thing exists, append to its "What I have tried" section. Stop.

### Step 3: Create the note

File: `questions/<slug>.md`.

```markdown
---
type: question
title: <the question, ending with ?>
area:
topics: []
projects: []
status: open
created: <today>
updated: <today>
tags: []
blocks: []            # tasks that wait for this answer
answered_by:
---
# <title>

## Question

## Why it matters

## What I have tried / read so far

## Answer (when found)
```

### Step 4: Block tasks

If a task waits for this answer:

1. Set the task to `status: blocked` and `blocked_by: "[[<question>]]"`.
2. Put the task link in the `blocks` field of the question.
3. Append a log line for each note.

## Answer a question

1. If the answer is not a finding yet, run `vault-capture-finding` first.
2. Set `status: answered`, `answered_by: "[[<finding>]]"`, `updated: <today>`.
3. Write one paragraph under "Answer (when found)". Link the finding.
4. For each task in `blocks`: if nothing else blocks it, set it to `status: todo` and clear `blocked_by`.
5. Tell the user which tasks were unblocked.
6. Append a log line for each note.

## Drop a question

1. Set `status: dropped` and `updated: <today>`.
2. Write one line under "Answer (when found)" that says why the question no longer matters.
3. Append a log line.
