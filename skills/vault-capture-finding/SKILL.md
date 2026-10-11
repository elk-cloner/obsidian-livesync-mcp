---
name: vault-capture-finding
description: Capture one atomic finding (a fact, observation, insight, surprise) to the knowledge vault as an append-only note with source, location, confidence and cross-links to topics and projects. Use when the user says 'capture this', 'note this down', 'file this as a finding', 'interesting, save that', or shares a discrete piece of knowledge worth keeping. The skill places it in a topic or a project by the nature of the content. Not for decisions (vault-capture-decision), dated events (vault-capture-record), open questions (vault-capture-question), or end-of-session batches (vault-session).
---

# vault-capture-finding

Before you start: read `references/access.md` in this skill's folder. Then read the vault root `CLAUDE.md`.
This document describes only what is specific to this skill.

## Procedure

### Step 1: Resolve the area

Apply the placement rule of the vault `CLAUDE.md`.
If the content is a general truth, use the topic, even in a project session.
If the type or the area is unclear, apply `vault-where`.

### Step 2: List the link targets

List `sources/` and `concepts/` of the area.
If `topics` or `projects` point to another area, list its `concepts/` too.

### Step 3: Draft the note

File: `findings/YYYY-MM-DD-<slug>.md`. Slug: three to six words from the title.

```markdown
---
type: finding
title: <one declarative sentence>
area: <topics/... or projects/...>
topics: [<topic>]
projects: [<project>]          # [] if not applied yet
status: unverified             # verified only if the user confirmed it
created: <today>
updated: <today>
tags: []
source: "[[<source>]]"         # empty if none
location: "<chapter, page, timestamp or commit>"
confidence: low | medium | high
supersedes:                    # "[[old-finding]]" if this corrects one
relates:
  supports: []
  contradicts: []
  refines: []
  depends_on: []
---
# <title>

## Statement
<one or two sentences in the user's words>

## Evidence
<where it comes from; why the user believes it>

## Implications
<what it changes; can be empty>
```

### Step 4: Fill the relations

Fill `relates` only with notes that you listed in step 2.
If the finding conflicts with an existing finding or concept, put that note in `contradicts`. Tell the user.

### Step 5: Confirm and write

1. Show the full note and the path.
2. Wait for approval.
3. Write the note.
4. Append a log line.

### Step 6: Follow-ups

Give each follow-up as one line. Give it only if the condition is true.

- If a concept that this finding touches has no note: suggest `vault-update-concept`.
- If three or more findings were created against one concept after its `updated` date: suggest a concept review.
- If `contradicts` is not empty: suggest `needs_review: true` on the contradicted concept.
- If the finding is a learning waypoint: offer `vault-learning-path`.

## Rules

1. Write one finding per note. If the user gives two findings, ask to split them.
2. Keep the user's words. Correct grammar. Do not add interpretation.
3. Do not edit an existing finding. To correct it: create a new finding with `supersedes`, then set the old finding to `status: retracted`.
4. If the user says they verified the finding, set `status: verified`.
