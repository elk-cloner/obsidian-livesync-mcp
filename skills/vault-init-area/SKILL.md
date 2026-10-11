---
name: vault-init-area
description: Create a new topic or project area in the knowledge vault with the base folder layout, an area CLAUDE.md, README.md, a dashboard Base, and (for topics) a learning-path stub; also sets the current-area marker. Use when the user starts learning a new subject or starts a project they want tracked: 'set up a topic for X', 'new project folder for Y', 'start tracking Z'. Not for individual notes; use the capture skills for those.
---

# vault-init-area

Before you start: read `references/access.md` in this skill's folder. Then read the vault root `CLAUDE.md`.
This document describes only what is specific to this skill.

## Procedure

### Step 1: Collect the inputs

Ask for the missing items in one message:

- kind: `topic` or `project`
- slug: lowercase, hyphens
- scope: one sentence
- project only: repo path or URL; the topics it uses
- topic only: the sources in use; the projects it feeds

Do not create the area with empty fields that the user will not fill.

### Step 2: Create the folder

```
<kind>s/<slug>/
  CLAUDE.md
  README.md
  <slug>.base
  sources/  findings/  decisions/  concepts/  questions/  tasks/  outputs/
  learning-path.md            topic only
  records/                    project only
  concepts/architecture.md    project only, status: draft
```

Copy `_bases/topic-dashboard.base` or `_bases/project-dashboard.base` to `<slug>.base`.
Replace `<slug>` in its folder filter with the new slug.

Empty folders:

- On the filesystem, create each empty folder with a `.gitkeep` file.
- With the MCP tools, do not create empty folders. A folder appears with its first note. The sync layer does not carry empty folders or dotfiles.

With the MCP tools, "copy" means: read the template with `read_note`, then create the new note with `write_note`.

### Step 3: Copy the templates

1. Copy `_templates/area-topic/` or `_templates/area-project/` into the new folder.
2. For a project, move `architecture.md` into `concepts/`.
3. Replace every `<slug>`, `<topic>`, `<project>` placeholder with the values from step 1.
4. Fill "Scope" (topic) or "What it is" and "Repo" (project) from the user's answers.
5. Write `README.md` in plain prose. State why the area exists and where to start.

### Step 4: Finish

1. Append a log line.
2. Set the marker to the new area.
3. If the user named sources, offer `vault-ingest` for each one.
4. If a linked area exists, add this area to the link list in that area's `CLAUDE.md`.

## Rules

- Do not create placeholder notes.
- Do not create an index file.
