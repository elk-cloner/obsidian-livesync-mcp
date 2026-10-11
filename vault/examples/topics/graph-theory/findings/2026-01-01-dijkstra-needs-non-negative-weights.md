---
type: finding
title: Dijkstra requires non-negative edge weights
area: topics/graph-theory
topics: [graph-theory]
projects: [route-planner]
status: verified
created: 2026-01-01
updated: 2026-01-01
tags: [example]
source: "[[graph-textbook]]"
location: "ch. 4"
confidence: high
supersedes:
relates:
  supports: ["[[weighted-graph]]"]
  contradicts: []
  refines: []
  depends_on: []
---
# Dijkstra requires non-negative edge weights

## Statement

Dijkstra's algorithm assumes every edge weight is zero or positive. With a negative edge it can settle a node too early and return a wrong distance.

## Evidence

Textbook chapter 4 gives a three-node counterexample.

## Implications

The route planner must reject or transform negative weights before calling Dijkstra.
