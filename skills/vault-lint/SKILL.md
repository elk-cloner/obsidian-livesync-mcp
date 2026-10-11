---
name: vault-lint
description: Check the knowledge vault's health. Structural lint runs a script that finds missing frontmatter, invalid statuses, broken wikilinks, orphans, findings without a source, superseded decisions still linked as active, tasks blocked by a non-open question, and outputs whose sources changed; it writes lint-report.md. Semantic lint is an LLM pass that proposes (never applies) concept reviews, contradictions between findings, and decisions whose basis moved. Use when the user says 'lint the vault', 'check the vault', 'is the vault healthy', 'what's stale', or on a schedule. Nothing is changed without approval.
---

# vault-lint

Before you start: read `references/access.md` in this skill's folder. Then read the vault root `CLAUDE.md`.
This document describes only what is specific to this skill.

## Part A: Structural lint

### Step 1: Run the checks

Use the access mode from `references/access.md`.

- MCP: call `lint_vault` with the vault name. The server runs the script, writes `lint-report.md` into the vault, and returns the counts and the first items of each check.
- Filesystem: run the script that ships with this skill. It writes `<vault>/lint-report.md` and prints a summary. It needs PyYAML.

```bash
python3 "<this skill's folder>/scripts/lint.py" "$(cat ~/.config/vault/root)"
```

Both modes run the same script.

The script checks:

1. Required fields present; `type` valid.
2. `status` valid for the type.
3. Every link resolves to a note or to an area.
4. Orphans: notes with no inbound link and empty `topics` and `projects`. Sources, tasks and records are exempt.
5. Findings with an empty `source`.
6. Decisions with `status: superseded` that another note still links to as active.
7. Tasks with `blocked_by` that points to a question that is not `open`.
8. Outputs whose `drew_on` notes have `updated` after the output's `created`.
9. Concepts with three or more findings created after the concept's `updated`.
10. `area` that does not match the folder.

### Step 2: Report

1. Show the counts per check.
2. Show the first items per check.

### Step 3: Offer fixes

Offer mechanical fixes first. List them. Apply them on one yes. Append a log line for each.

- Fill `area` from the folder.
- Set `status: stale` on outputs from check 8.
- Set `needs_review: true` on concepts from check 9.

Hand the other items to the matching skill:

- A broken link to a missing concept: `vault-update-concept` or `vault-capture-question`.
- A finding without a source: `vault-ingest`.
- A task blocked by a closed question: `vault-task`.

## Part B: Semantic lint

Scope semantic lint to one area unless the user asks for more. It is expensive.

For the area:

1. **Contradictions.** Read the findings that share a concept, in pairs. List the pairs that cannot both be true. Propose a retraction or a question.
2. **Concepts behind their findings.** For each concept, read the findings created after its `updated`. State in one sentence whether the page still holds. Propose `needs_review: true` where it does not.
3. **Decisions whose basis moved.** For each active decision, check its `depends_on` notes for later changes or retractions. Propose a supersede or a re-confirmation.
4. **Stale outputs.** For each output with `status: draft` or `final`, read `drew_on`. Propose `status: stale` where the answer would differ now.
5. **Area CLAUDE.md drift.** Compare "Current state" and "Known gaps" with the open questions and the recent findings. Propose a rewrite of those two sections.

Present the proposals as a numbered list with the evidence for each.
Apply only the proposals that the user approves.
Append a log line for each applied change.

## Scheduling

Run structural lint on demand, or at the start of `vault-session`.
`_bases/lint-report.base` shows the parts of the result that Bases can express.
Run semantic lint on demand, or once a month per area.
