---
name: pure-lisp-image-goal
description: End goal that the stock Pharo image is not needed; cog-lisp runs from a pure Lisp image (Phase 10, a long phase; seeded builds are Phase 9).
metadata:
  node_type: memory
  type: project
  originSessionId: 5dcb1131-e89e-4241-a508-976cd71439d3
  modified: 2026-11-05T03:45:41.225Z
---

The user's end goal (stated 2026-11-02): when cog-lisp is done, the **stock Pharo
image should not be necessary** — a pure Lisp image.

**Why:** cog-lisp should be its own world, not a guest inside Pharo (see
[[north-star-vision]]).

**How to apply:**
- The VM always needs a small Smalltalk-shaped kernel (nil/true/false,
  SmallInteger, Array, CompiledMethod, BlockClosure, …); "pure" means everything
  else is audited and the user-visible world is Lisp. Say this plainly if it comes up.
- Phase split (owner, 2026-11-04): **Phase 9** finishes the language (seeded builds
  from a pinned cog-lisp image, which retire the Smalltalk reader/compiler; the
  numeric tower; hygienic macros). **Phase 10** is the pure image, and the owner
  expects to **take a long time on it**: each step gets its own detailed spec first.
- **The runtime is rewritten in LISP** (owner, 2026-11-04; Phase 10.1, via
  `define-class`/`define-method`), rather than keeping Opal as a build tool.
- **Do not strip subsystems blindly** (user, 2026-11-02). **Networking and graphics
  are wanted** (2026-11-04: Phase 10.6/10.7 add them from LISP); networking is how
  an AI agent gets into the world. The Phase 10 audit (owner signs it off) decides
  keep, reimplement in Lisp (preferred where practical), or remove.
- **Complex numbers are a library, addable at any time** (owner, 2026-11-04): the
  numeric tower must stay open to new number types.
- This is a real tension with [[lean-on-pharo]]: lean on Pharo to get there, but
  don't add run-time dependencies that a pure image couldn't carry.
