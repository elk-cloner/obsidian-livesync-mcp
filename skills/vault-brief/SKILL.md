---
name: vault-brief
description: Answer a question from the user's own knowledge vault (concepts, findings, decisions, records, questions), separate what the vault says from what it lacks, then offer to file the answer as an output note so good syntheses compound. Use when the user asks 'what do I know about X', 'brief me on Y', 'where did I land on Z', 'what have I learned about', 'catch me up on', or wants their own notes synthesized rather than a general answer. Reading is cross-area: a project question pulls in the topics it uses. Read-only unless the user accepts the offer to file.
---

# vault-brief

Before you start: read `references/access.md` in this skill's folder. Then read the vault root `CLAUDE.md`.
This document describes only what is specific to this skill.

## Procedure

### Step 1: Set the scope

1. Resolve the area the user named, or the current area.
2. Read its `CLAUDE.md`. Add the areas it links under "Topics that this project uses" or "Projects that use this topic".

### Step 2: Read

Read in this order. Stop when the question is answered.

1. The area `CLAUDE.md`: current state and gaps.
2. The concepts that match the question.
3. The findings in `based_on` of those concepts, and the findings found by search on the key terms. Skip retracted findings.
4. The active decisions on the subject.
5. The open questions on the subject.
6. For a project: the last few records.

Filesystem: `grep -ril`. MCP: `search_notes`.

### Step 3: Write the brief

Use three sections:

1. **What the vault says.** Synthesize. Link every note that you used. Prefer concepts. Cite findings for specifics. Name decisions as decisions.
2. **Confidence.** Name findings with `status: unverified` or `confidence: low`. Name concepts with `needs_review: true`. Name contradictions.
3. **What the vault does not say.** List the gaps relative to the question. Link the open questions that cover them.

Do not fill a gap from general knowledge inside these sections.
If general knowledge helps, add a fourth section with the heading "Not from the vault".

Keep the length proportional. A narrow question gets one paragraph.

### Step 4: Offer to file

Ask once: "File this brief?"
If yes, create `outputs/YYYY-MM-DD-<slug>.md`:

```markdown
---
type: output
title: <the question as a title>
area:
topics: []
projects: []
status: draft
created: <today>
updated: <today>
tags: []
question: "<the question as asked>"
drew_on: ["[[concept-a]]", "[[finding-b]]", "[[decision-c]]"]
---
# <title>

## Question asked

## Answer
<sections 1 to 3 of the brief>

## Sources inside the vault
<one line per note in drew_on: what it contributed>
```

Append a log line. Lint uses `drew_on` to mark the output `stale` later.

### Step 5: Follow-ups

- If the brief found a gap with no question note: offer `vault-capture-question`.
- If the brief found a concept that is missing or behind: say so in one line.

## Rules

1. Every claim in "What the vault says" must link to a note.
2. The only write is the filed output, and only after a yes.
