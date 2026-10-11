---
name: vault-task
description: Create, update, complete, or list tasks in the knowledge vault. Use when the user says 'add a task', 'I need to', 'mark that done', 'what am I working on', 'what's blocked', or plans work in a topic (read, exercise, review) or a project (build, investigate). Tasks carry a kind, topics and projects, and can be blocked by an open question. Completion prompts for capture so what was learned is not lost. Not for facts, decisions or events.
---

# vault-task

Before you start: read `references/access.md` in this skill's folder. Then read the vault root `CLAUDE.md`.
This document describes only what is specific to this skill.

## Create

File: `tasks/<slug>.md`.

```markdown
---
type: task
title: <imperative>
area:
topics: []
projects: []
status: todo
created: <today>
updated: <today>
tags: []
kind: read | exercise | build | review | investigate
blocked_by:            # "[[<question>]]" or empty
due:                   # YYYY-MM-DD or empty
---
# <title>

## Goal

## Done when
- [ ]

## Notes
```

1. If the task waits for a question, set `status: blocked` and `blocked_by`. If the question has no note, run `vault-capture-question` first.
2. If the goal is clear, write without confirmation. Otherwise show the note first.
3. Append a log line.

## Update

1. Change `status`, `due`, `blocked_by`, or append to "Notes".
2. Set `updated: <today>`.
3. Append a log line.

`doing` means work in progress now. If the user sets a sixth task to `doing`, say so.

## Complete

1. Set `status: done` and `updated: <today>`.
2. Tick the "Done when" items that were met. Name the items that were not met.
3. Ask one question: "Anything to capture from this? (finding, decision, record, question)". If yes, hand off to that skill.
4. If `kind` is `read`, ask whether to add a learning-path step.
5. If a project task produced a result, offer `vault-capture-record`.
6. Append a log line.

## List

1. If the user can open Obsidian, point to `_bases/now.base`, `_bases/open-tasks.base` or the area dashboard.
2. If the user asks in chat, read `tasks/` of the area, or of all areas.
3. Show a table: title, kind, status, blocked_by, due. Group by area when the list spans areas.

## Rules

1. Write one task per note.
2. Do not delete a task. For an abandoned task: set `status: done` and append "dropped: <why>" to "Notes".
3. Do not maintain a task index.
