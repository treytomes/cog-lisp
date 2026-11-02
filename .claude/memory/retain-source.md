---
name: retain-source
description: "Compiled Lisp code must always keep its original source text, stored in the image itself."
metadata:
  node_type: memory
  type: feedback
  originSessionId: 5dcb1131-e89e-4241-a508-976cd71439d3
  modified: 2026-11-02T19:42:52.503Z
---

Requirement from the user (2026-11-02): **retain the source code associated with
compiled code.**

**Why:** the image must be able to show (and eventually rewrite) its own
definitions; an agent growing in the image needs to read its own body
([[north-star-vision]]).

**How to apply:**
- Every `LispProcedure` carries the exact text it was compiled from (Phase 5
  §5.2: the reader records list source ranges; the compiler passes the text to
  the procedure). `(procedure-source f)` returns it.
- Store source **in image objects**, not in Pharo's `.sources`/`.changes` files,
  so it survives `save-image` and a future pure Lisp image
  ([[pure-lisp-image-goal]]).
- Any new code path that compiles Lisp (macros, self-hosted compiler, eval of
  generated forms) must keep or synthesize source, never drop it silently.
