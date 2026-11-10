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

The phases, in order ([the project plan](../PROJECT-PLAN.md) describes each):

| Phase | Spec | Status |
|------:|------|--------|
| 1 | [Reader & Printer](phase-1-reader-printer.md) | Implemented (77/77) |
| 2 | [Core Data Model](phase-2-core-data-model.md) | Implemented (49/49) |
| 3 | [Compiler Core](phase-3-compiler-core.md) | Implemented (31/31) |
| 4 | [Runtime & Primitives](phase-4-runtime-primitives.md) | Implemented (44/44) |
| 5 | [REPL, Runner & Image](phase-5-repl-runner.md) | Implemented (28/28 + 30/30) |
| 6 | [Tail Calls & Optimization](phase-6-optimization.md) | Implemented (127/127 + bench 12/12) |
| 7 | [Macros & Derived Forms](phase-7-macros.md) | Implemented (115/115) |
| 7.5 | [Review & Tooling](phase-7.5-review-and-tooling.md), with [the review of Phases 1–7](review-phases-1-7.md) | Implemented (114/114 review checks; all suites 627/627; extension checked in VS Code) |
| 7.6 | [Smalltalk Interop](phase-7.6-smalltalk-interop.md) | Implemented (82/82; all suites 719/719) |
| 7.7 | [Conditions & Restarts](phase-7.7-conditions-restarts.md) | Implemented (55/55; all suites 785/785) |
| 7.8 | [Strings, Characters, Vectors & Hash Tables](phase-7.8-native-data.md) | Implemented (58/58; all suites 853/853) |
| 7.9 | [Self-Hosting Groundwork](phase-7.9-self-hosting-groundwork.md) | Implemented (46/46; all suites 948/948; compile speed short of target, §12) |
| 8 | [Self-Hosting](phase-8-self-hosting.md) | Implemented (steps 8.1–8.6) |
| 8.9 | [CI/CD, and running on Linux](phase-8.9-ci-cd.md) | Implemented |
| 9 | [Finishing the language](phase-9-language.md): seeded builds, the numeric tower, hygienic macros, generalized `set!` | Implemented (9.1–9.4) |
| 10 | [Knowing the language](phase-10-documentation-and-editor.md): documentation, the reference, the manual, the language server, the site, the agent skill | Implemented (10.1–10.7) |
| 11 | [A world of its own: the pure LISP image](phase-11-pure-image.md) | Accepted in outline; each step specified before it starts |

Steps between phases, from reviewing `lisp-expert` and the GitHub issues
(all 2026-11-09):

| Spec | What | Status |
|------|------|--------|
| [startup-anywhere.md](startup-anywhere.md) | Two runs on one image, a read-only install, a read-only folder | Done |
| [library-path.md](library-path.md) | `require` and `*env*`: cog-lisp's libraries from any folder | Done |
| [format.md](format.md) | `format`, built in | Done |
| [coverage.md](coverage.md) | Code coverage | Done |
| [https-and-json.md](https-and-json.md) | JSON, then HTTP and HTTPS over the system's curl | Done |
| [lisp-expert-libraries.md](lisp-expert-libraries.md) | lisp-expert's libraries moved in: list built-ins, `datetime`, `pretty` | Done |
| [lisp-expert-review.md](lisp-expert-review.md) | SRFI 1's `any`, `every`, `find` and more; `parameterize`; ISO dates; lisp-expert onto them | Done |
| [cl-issues.md](cl-issues.md) | Issues #1 (documented, deferred), #2, #3, #4, #6 | Done |
| [vscode-spelling.md](vscode-spelling.md) | Issue #7: cog-lisp's names in the spell checker | Done |
| [formatter.md](formatter.md) | Issue #8: the source formatter | Done |
