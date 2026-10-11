---
type: decision
title: Store the graph as an adjacency list
area: projects/route-planner
topics: [graph-theory]
projects: [route-planner]
status: active
created: 2026-01-01
updated: 2026-01-01
tags: [example]
supersedes:
superseded_by:
relates:
  depends_on: ["[[weighted-graph]]"]
---
# Store the graph as an adjacency list

## Context

Road networks are sparse. Most nodes have two to four neighbors.

## Decision

Use an adjacency list (dict of node → list of (neighbor, weight)).

## Alternatives considered

- Adjacency matrix: wastes memory on a sparse graph.
- Edge list: slow neighbor lookup.

## Consequences

Neighbor lookup is fast. Edge existence checks are slower; acceptable here.
