# Knowledge vault

This is the start page for a human. If you are Claude, read `CLAUDE.md` first.

## Content of the vault

This vault has two kinds of folders:

- `topics/` holds what I understand. Each topic is a subject that I learn. It has sources, findings, decisions, concepts, open questions and a learning path.
- `projects/` holds what I built with it. Each project has the same note types. It also has a dated `records/` log and a living architecture page.

The notes link to each other through their frontmatter. Thus a dashboard can show which findings from a topic I applied in which project. It can also show which concepts I learned but did not use.

The repository that seeded this vault has worked examples in `vault/examples/`: a topic (`graph-theory`) and a project (`route-planner`). They use every note type. They also show how a topic and a project link to each other.

## Create a topic

1. Copy `_templates/area-topic/` to `topics/<slug>/`.
2. Create the folders `sources/ findings/ decisions/ concepts/ questions/ tasks/ outputs/`.
3. Copy `_bases/topic-dashboard.base` to `topics/<slug>/<slug>.base`. Change its folder filter.
4. Write the `CLAUDE.md` (scope, sources, projects that use the topic) and the `README.md`.
5. If a project uses this topic, add the topic to the `CLAUDE.md` of that project.

Or ask Claude: "set up a topic for <subject>". The `vault-init-area` skill does the same steps.

## Create a project

1. Copy `_templates/area-project/` to `projects/<slug>/`. Move `architecture.md` into `concepts/`.
2. Create the folders `sources/ findings/ decisions/ concepts/ questions/ tasks/ outputs/ records/`.
3. Copy `_bases/project-dashboard.base` to `projects/<slug>/<slug>.base`. Change its folder filter.
4. Write the `CLAUDE.md` (what the project is, the repo, the topics it uses) and the `README.md`.
5. Add the project to the `CLAUDE.md` of each topic that it uses.

Or ask Claude: "new project folder for <name>".

## Find your way

- `_bases/now.base` shows my current work in all areas.
- Each area has a `README.md` and a `CLAUDE.md`. The `README.md` tells the story of the area. The `CLAUDE.md` gives its current state and its gaps.
- `log.md` is the chronological record of each change that a skill made. The times are UTC.
- `_state/current-area.md` names the default area for Claude.
- The lint script writes `lint-report.md`. `_bases/lint-report.base` shows it.

## Rules

- Put a note where its content belongs. Do not put it where you were when you wrote it.
- Do not edit a finding or a decision. Retract it or supersede it.
- Rewrite a concept in place when your understanding grows.
- Give each note `topics:` and `projects:`. Then you can query the graph, not only browse it.
