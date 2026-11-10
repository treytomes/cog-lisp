---
name: reuse-lisp-expert
description: "When cog-lisp gains something lisp-expert already has (format, JSON, ...), copy and adapt lisp-expert's code rather than writing it from scratch."
metadata:
  node_type: memory
  type: feedback
  originSessionId: 5dcb1131-e89e-4241-a508-976cd71439d3
  modified: 2026-11-09T17:06:09.887Z
---

Wherever possible, build cog-lisp features from the code already written in
`~/projects/lisp-expert` (the owner's own project of cog-lisp programs): its
`format.lisp`, `weather/json.lisp`, and the like. Copy, adapt to plain cog-lisp
(no `lib/cl.lisp` in a built-in), and bring its tests along. (Owner, 2026-11-09.)

**Why:** the owner wrote that code (partly with Claude on the web) and wants it
finished and reused, not duplicated by a fresh implementation.

**How to apply:** before implementing a spec item, look in lisp-expert for an
existing version; say in the spec's as-built notes what was copied from where.
Related: [[examples-become-manual]].
