---
name: pure-lisp-image-goal
description: End goal that the stock Pharo image is not needed; cog-lisp runs from a pure Lisp image (Phase 9).
metadata:
  node_type: memory
  type: project
  originSessionId: 5dcb1131-e89e-4241-a508-976cd71439d3
  modified: 2026-11-02T19:53:32.784Z
---

The user's end goal (stated 2026-11-02): when cog-lisp is done, the **stock Pharo
image should not be necessary** — a pure Lisp image.

**Why:** cog-lisp should be its own world, not a guest inside Pharo (see
[[north-star-vision]]).

**How to apply:**
- The VM always needs a small Smalltalk-shaped kernel (nil/true/false,
  SmallInteger, Array, CompiledMethod, BlockClosure, …); "pure" means everything
  else goes and the user-visible world is Lisp. Say this plainly if it comes up.
- Phase 5 rule: nothing at **run time** may depend on the stock image; it is used
  only to build `cog-lisp.image`.
- Removing the stock image at **build** time comes later (Phase 9): images built
  from an existing cog-lisp image, or from Pharo's bootstrap tooling.
- **Do not strip subsystems blindly** (user, 2026-11-02). Networking and UI may
  be needed — networking is how an AI agent gets into the world. Phase 9 audits
  each subsystem: keep, reimplement in Lisp (preferred where practical), or
  remove.
- Removing the Opal dependency needs Phase 6 (direct bytecode) and Phase 8 (the
  compiler in Lisp). This is a real tension with [[lean-on-pharo]]: lean on Pharo
  to get there, but don't add run-time dependencies that a pure image couldn't
  carry.
