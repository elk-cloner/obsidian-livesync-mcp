---
name: vault-learning-path
description: Maintain a topic's learning-path.md: the sequenced tutorial someone else could follow to learn the subject, where each step links the concept taught, the source it came from, the findings that mattered, and the project task where it was applied. Use when the user says 'add this to the learning path', 'where does this fit in the path', 'update the path', 'how does my path look', or after a capture skill asks whether a finding is a waypoint. Topics only; projects link into it through the apply step.
---

# vault-learning-path

Before you start: read `references/access.md` in this skill's folder. Then read the vault root `CLAUDE.md`.
This document describes only what is specific to this skill.

## The page

File: `topics/<topic>/learning-path.md`. Frontmatter: `type: learning-path`, `status: draft | current`.
The body is an ordered list of steps. Write the body of each step in plain prose.

```markdown
## Step N: <what you can do after this step>

- Concept: [[<concept>]]
- Source: [[<source>]] (<location>)
- Findings: [[<f1>]], [[<f2>]]
- Apply: [[<project task or record>]]
- Why this comes here: <prerequisites and sequencing>
- Pitfall: <optional>
```

## Add a step

1. Read the page and the area `CLAUDE.md`.
2. Place the step by prerequisites, not by the date it was learned.
3. If the new step needs a concept with no step yet, say so. Offer to add that step first.
4. Check that every linked note exists. `Concept` and `Source` are required. `Apply` is optional.
5. If the concept note does not exist, offer `vault-update-concept` first.
6. Insert the step. Renumber the steps. Set `updated: <today>`.
7. Show the new step with its neighbors. Wait for approval. Write. Append a log line.

## Reorder or rewrite

1. Show the full page as it would read. Mark the moved steps.
2. Wait for approval. Write. Append a log line.

## Review

Read the page end to end. Report three things:

1. Jumps: a step uses something that no earlier step taught.
2. Steps without `Apply`: learned but not practiced. Cross-check `_bases/learned-not-applied.base`.
3. Open questions that sit between steps.

Propose. Do not change the page in a review.

## Rules

1. Write for a reader who is not the user. Write the "Why" line in full sentences.
2. A step is a capability gained. Three findings can make one step. Not every finding is a step.
3. Set `status: current` only when the user says the path covers what they know.
