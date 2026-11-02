# Specifications

cog-lisp is built **spec-first**: we write down what a phase must do — and how
we'll know it's done — before we write the code. A spec is the contract; the code
is the implementation of the contract; the acceptance suite is the proof.

## How we use these

1. **Write the spec.** Scope, decisions, interfaces, and **acceptance criteria**
   that are mechanically checkable.
2. **Settle open questions** with the project owner before (or early during)
   implementation.
3. **Implement against the spec.** Code references the spec section it satisfies.
4. **Prove it** with a headless acceptance script under `tests/`, following the
   `poc/answer.st` convention: build, assert, print `PASS`/`FAIL` per check, end
   with a `RESULT: n/n` line, and `Smalltalk snapshot: false andQuit: true`.
5. **When reality disagrees with the spec, change the spec first**, then the code.
   The spec is never allowed to silently drift from what ships.

## Status lifecycle

`Draft` → `Accepted` (owner signed off, open questions resolved) →
`Implemented` (code + passing acceptance suite) → `Superseded` (replaced; links
to successor).

## Index

| Phase | Spec | Status |
|------:|------|--------|
| 1 | [Reader & Printer](phase-1-reader-printer.md) | Implemented (77/77) |
| 2 | [Core Data Model](phase-2-core-data-model.md) | Implemented (49/49) |
| 3 | [Compiler Core](phase-3-compiler-core.md) | Implemented (31/31) |
| 4 | [Runtime & Primitives](phase-4-runtime-primitives.md) | Accepted |

Later phases (2–7, see the [project plan](../README.md#project-plan)) get their
specs here as we reach them.
