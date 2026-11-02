---
name: lean-on-pharo
description: Guiding design tenet — build cog-lisp by reusing Pharo's architecture, not reinventing it.
metadata:
  type: feedback
---

The project's standing design tenet (restated by the user 2026-11-02): **lean
hard on the existing Pharo architecture as the foundation for the LISP
environment** — reuse Pharo's machinery rather than reinvent it.

**Why:** it is the fastest path to the [[north-star-vision]] (a living,
Smalltalk-like world) and keeps the system small, native, and reflective. Every
phase so far embodies it.

**How to apply — when a design choice arises, prefer the option that rides
existing Pharo infrastructure:**
- VM: Cog+Spur; compiled LISP is ordinary `CompiledMethod`s it JITs.
- Closures → Smalltalk `BlockClosure`s; lexical capture is Smalltalk's.
- Locals → Smalltalk block temps/args; scoping is Smalltalk's (see
  [[phase-2-env-model-decision]]).
- Codegen → translate LISP to a Smalltalk AST and let the **Opal** compiler do
  semantic analysis, closure conversion, and bytecode generation (Phase 3).
- Persistence → the image; reflection → Smalltalk's MOP.

We write the *translation*; Pharo provides the *machinery*. Reach for a
hand-rolled mechanism only when riding Pharo's would actively block a goal (e.g.
raw SistaV1 for a hot path in Phase 6).
