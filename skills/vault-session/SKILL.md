---
name: vault-session
description: End-of-session review for the knowledge vault: read the whole conversation, propose a batch of writes (findings, decisions, records, questions, task updates, concept reviews, area CLAUDE.md state), and apply only what the user approves. Use when the user says 'wrap up', 'capture this session', 'save what we covered', 'end of session', or a long learning or build session winds down with several things worth filing. It runs structural lint before proposing and refreshes the area's Current state and Known gaps. Not for single captures (use the vault-capture-* skills).
---

# vault-session

Before you start: read `references/access.md` in this skill's folder. Then read the vault root `CLAUDE.md`.
This document describes only what is specific to this skill.

## Procedure

### Step 1: Resolve the areas

Identify the areas that this session touched. A session often touches one topic and one project.

### Step 2: Run structural lint

Run Part A of `vault-lint` (the `lint_vault` tool, or its script on the filesystem). Show the counts. Do not fix anything yet.

### Step 3: Draft the batch

Review the conversation. For each candidate item, decide the type and the area with the `vault-where` rules.
Group the items by area, then by type, in this order:

1. findings: new, or `supersedes` an existing one
2. decisions: new, or supersede
3. records: projects only
4. questions: opened; answered, with the finding that answers each one
5. tasks: created; status changed; completed
6. concepts: `needs_review: true`; a rewrite only if the user consolidated out loud
7. learning-path steps: topics only
8. area `CLAUDE.md`: new "Current state" paragraph; new "Known gaps" list

### Step 4: Present the plan

Show a numbered list. For each item give: type, area, file name, one line of content, `topics`, `projects`.
Show the full body of a finding or a decision on request.
Ask the user to approve by number, all, or none.

### Step 5: Apply

Write the approved items with the formats of the single-item skills, in this order:
sources, findings, decisions, records, questions, tasks, concepts, learning path, area `CLAUDE.md`.
Append a log line for each write.

### Step 6: Report

State what was written, by area. State what was skipped. State the lint issues that remain.

## Rules

1. Propose only what the user said or did. If the assistant explained something and the user did not adopt it, do not propose it as a finding. Propose a question or a source note instead.
2. Do not propose every remark. A session yields two to six items in most cases.
3. Rewrite "Current state" as one paragraph. Do not append to it.
4. Do not create an index file.
