---
type: concept
title: Architecture
area: projects/route-planner
topics: [graph-theory]
projects: [route-planner]
status: draft
created: 2026-01-01
updated: 2026-01-01
tags: [example]
needs_review: false
based_on: ["[[2026-01-01-use-adjacency-list]]", "[[2026-01-02-graph-loader-works]]"]
relates:
  depends_on: ["[[weighted-graph]]"]
  refines: []
---
# Architecture

## Current understanding

Living page. Rewritten whenever the system's shape changes; the history is in git, not here.

## Components

- Loader: reads a CSV of road segments into an adjacency list.
- Search: (not built yet).
- CLI: parses two points and prints the route.

## Data flow

CSV file → loader → in-memory graph → search → route → CLI output.

## Known weak points

- No handling of negative weights.
