---
type: concept
title: Weighted graph
area: topics/graph-theory
topics: [graph-theory]
projects: [route-planner]
status: draft
created: 2026-01-01
updated: 2026-01-01
tags: [example]
needs_review: false
based_on: ["[[2026-01-01-dijkstra-needs-non-negative-weights]]"]
relates:
  depends_on: []
  refines: []
---
# Weighted graph

## Current understanding

A graph whose edges carry a number (distance, time, cost). Shortest-path algorithms minimize the sum of edge weights along a path.

## Key points

- Weights can be any number, but most shortest-path algorithms assume they are non-negative.

## Where I am unsure

- See [[negative-edge-weights]].

## Applied in

- [[route-planner]]: road segments are edges weighted by travel time.
