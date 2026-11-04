---
name: examples-become-manual
description: Owner values an example program per feature; the examples/ set will become the cog-lisp user manual.
metadata:
  type: feedback
---

Every feature lands with a runnable example in `examples/` (with a `.expected` file the runner suite checks), and the owner wants this to continue: the examples will become the backbone of a cog-lisp user manual (said 2026-11-04).

**Why:** they prove each feature works and double as documentation, one chapter per feature.

**How to apply:** in every spec, include an Examples section with one example per feature; write examples in a teaching order with plain comments, deterministic output, and building on earlier ones. Related: [[expert-system-goal]].
