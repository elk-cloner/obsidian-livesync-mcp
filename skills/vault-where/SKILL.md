---
name: vault-where
description: Decide where a piece of information belongs in the knowledge vault: which area (topic or project), which note type, and whether it is new or an update to an existing note. Use whenever the user says 'where should this go', 'is this a finding or a decision', 'topic or project', or hands over something to file without saying what it is. Other vault skills use it when placement is unclear. Read-only.
---

# vault-where

Before you start: read `references/access.md` in this skill's folder. Then read the vault root `CLAUDE.md`.
This document describes only what is specific to this skill.

## Procedure

### Step 1: Decide the type

Apply the first rule that matches:

1. A fact that is true independent of the user's choices: finding.
2. A choice the user made, with reasons: decision.
3. An event on a date in a project: record.
4. Something the user does not know yet: question.
5. A change in how the user understands a subject: concept update.
6. Work to do: task.
7. A book, paper, article, repo, course or video: source.
8. An answer synthesized from the vault: output.

If a dated experiment also establishes a general fact, propose a record and a finding.

### Step 2: Decide the area

Ask: is this still true or relevant if the current project does not exist?

- If yes, the area is the topic.
- If no, the area is the project.

### Step 3: Check for an existing note

Search the target folder for the slug and for the key terms.
Filesystem: `grep -ril`. MCP: `search_notes`.

- If a finding, decision or record matches: propose a new note with `supersedes`. Do not propose an edit.
- If a concept, task or question matches: propose an update of that note.

### Step 4: Decide the cross-links

- If a project note uses a method from a topic, put that topic in `topics`.
- If a topic note was applied in a project, put that project in `projects`.

### Step 5: Report

Give one line each: type, area, file name, `topics`, `projects`, and the skill to call.
Do not write.

## Examples

| Input | Type | Area | Cross-links |
|---|---|---|---|
| Dijkstra requires non-negative edge weights | finding | topics/graph-theory | projects: [route-planner] if it came up there |
| Our road CSV has duplicate segments | finding | projects/route-planner | topics: [graph-theory] |
| We store the graph as an adjacency list | decision | projects/route-planner | topics: [graph-theory] |
| Does A* need non-negative weights too? | question | topics/graph-theory | |
| Loader passes: 120 edges in 12 ms | record (milestone) | projects/route-planner | topics: [graph-theory] |
