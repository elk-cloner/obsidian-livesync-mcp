# Knowledge vault

Start here if you are a human. If you are Claude, read `CLAUDE.md` first.

## What this is

One vault, two kinds of folders:

- `topics/` is what I understand. Each topic is a subject I am learning: sources, findings, decisions, concepts, open questions, a learning path.
- `projects/` is what I built with it. Each project has the same note types plus a dated `records/` log and a living architecture page.

They cross-link through frontmatter, so a dashboard can show which findings from a topic were applied in which project, and which concepts I learned but never used.

Worked examples live in the repository this vault was seeded from, under `vault/examples/`: a topic (`graph-theory`) and a project (`route-planner`). They show every note type in use and how a topic and a project link to each other.

## How to create a topic

1. Copy `_templates/area-topic/` to `topics/<slug>/`.
2. Create the folders `sources/ findings/ decisions/ concepts/ questions/ tasks/ outputs/`.
3. Copy `_bases/topic-dashboard.base` to `topics/<slug>/<slug>.base` and change its folder filter.
4. Fill in `CLAUDE.md` (scope, sources, projects that use it) and `README.md`.
5. If a project uses this topic, add the topic to that project's `CLAUDE.md`.

Or ask Claude: "set up a topic for <subject>" runs the `init-area` skill, which does the same.

## How to create a project

1. Copy `_templates/area-project/` to `projects/<slug>/`. Move `architecture.md` into `concepts/`.
2. Create the folders `sources/ findings/ decisions/ concepts/ questions/ tasks/ outputs/ records/`.
3. Copy `_bases/project-dashboard.base` to `projects/<slug>/<slug>.base` and change its folder filter.
4. Fill in `CLAUDE.md` (what it is, repo, topics it uses) and `README.md`.
5. Add the project to the `CLAUDE.md` of each topic it uses.

Or ask Claude: "new project folder for <name>".

## How to navigate

- `_bases/now.base` shows what I am doing right now across everything.
- Each area has a `README.md` that tells its story and a `CLAUDE.md` that states its current state and gaps.
- `log.md` is the chronological record of every change a skill made. Times are UTC.
- `_state/current-area.md` names the area Claude works in by default.
- `lint-report.md` is written by the lint script; `_bases/lint-report.base` shows it.

## Conventions in one paragraph

A note lives where its content belongs, not where I was when I wrote it. Findings and decisions are never edited, only retracted or superseded. Concepts are rewritten in place as understanding grows. Every note carries `topics:` and `projects:` so the graph is queryable, not just browsable.
