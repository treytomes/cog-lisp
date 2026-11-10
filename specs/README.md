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

## Numbering

Each spec's file name starts with a two-digit number, `NN-name.md`, in the order
of development (owner, 2026-11-10), so a listing of this folder reads as the
project's history: the phases first, then each step in the order it was done.
Specs not yet built come last, in the order they are planned (Phase 11, a long
one, is last of all). A new spec takes the next number; numbers are never reused
or changed once a spec is done. Cite a spec by its full name
(`specs/27-namespaces.md`).

## Index

The phases, in order ([the project plan](../PROJECT-PLAN.md) describes each):

| Phase | Spec | Status |
|------:|------|--------|
| 1 | [Reader & Printer](00-phase-1-reader-printer.md) | Implemented (77/77) |
| 2 | [Core Data Model](01-phase-2-core-data-model.md) | Implemented (49/49) |
| 3 | [Compiler Core](02-phase-3-compiler-core.md) | Implemented (31/31) |
| 4 | [Runtime & Primitives](03-phase-4-runtime-primitives.md) | Implemented (44/44) |
| 5 | [REPL, Runner & Image](04-phase-5-repl-runner.md) | Implemented (28/28 + 30/30) |
| 6 | [Tail Calls & Optimization](05-phase-6-optimization.md) | Implemented (127/127 + bench 12/12) |
| 7 | [Macros & Derived Forms](06-phase-7-macros.md) | Implemented (115/115) |
| 7.5 | [Review & Tooling](07-phase-7.5-review-and-tooling.md), with [the review of Phases 1–7](08-review-phases-1-7.md) | Implemented (114/114 review checks; all suites 627/627; extension checked in VS Code) |
| 7.6 | [Smalltalk Interop](09-phase-7.6-smalltalk-interop.md) | Implemented (82/82; all suites 719/719) |
| 7.7 | [Conditions & Restarts](10-phase-7.7-conditions-restarts.md) | Implemented (55/55; all suites 785/785) |
| 7.8 | [Strings, Characters, Vectors & Hash Tables](11-phase-7.8-native-data.md) | Implemented (58/58; all suites 853/853) |
| 7.9 | [Self-Hosting Groundwork](12-phase-7.9-self-hosting-groundwork.md) | Implemented (46/46; all suites 948/948; compile speed short of target, §12) |
| 8 | [Self-Hosting](13-phase-8-self-hosting.md) | Implemented (steps 8.1–8.6) |
| 8.9 | [CI/CD, and running on Linux](14-phase-8.9-ci-cd.md) | Implemented |
| 9 | [Finishing the language](15-phase-9-language.md): seeded builds, the numeric tower, hygienic macros, generalized `set!` | Implemented (9.1–9.4) |
| 10 | [Knowing the language](16-phase-10-documentation-and-editor.md): documentation, the reference, the manual, the language server, the site, the agent skill | Implemented (10.1–10.7) |
| 11 | [A world of its own: the pure LISP image](31-phase-11-pure-image.md) | Accepted in outline; each step specified before it starts |

Steps between phases (from 2026-11-09), from reviewing `lisp-expert`, the
GitHub issues and the owner's requests:

| Spec | What | Status |
|------|------|--------|
| [17-startup-anywhere.md](17-startup-anywhere.md) | Two runs on one image, a read-only install, a read-only folder | Done |
| [18-library-path.md](18-library-path.md) | `require` and `*env*`: cog-lisp's libraries from any folder | Done |
| [19-format.md](19-format.md) | `format`, built in | Done |
| [20-coverage.md](20-coverage.md) | Code coverage | Done |
| [21-https-and-json.md](21-https-and-json.md) | JSON, then HTTP and HTTPS over the system's curl | Done |
| [22-lisp-expert-libraries.md](22-lisp-expert-libraries.md) | lisp-expert's libraries moved in: list built-ins, `datetime`, `pretty` | Done |
| [23-lisp-expert-review.md](23-lisp-expert-review.md) | SRFI 1's `any`, `every`, `find` and more; `parameterize`; ISO dates; lisp-expert onto them | Done |
| [24-cl-issues.md](24-cl-issues.md) | Issues #1 (documented, deferred), #2, #3, #4, #6 | Done |
| [25-vscode-spelling.md](25-vscode-spelling.md) | Issue #7: cog-lisp's names in the spell checker | Done |
| [26-formatter.md](26-formatter.md) | Issue #8: the source formatter | Done |
| [27-namespaces.md](27-namespaces.md) | Libraries and namespaces: `library`, `require`'s imports, private names | Done |
| [28-versioning.md](28-versioning.md) | One version, from the git tag, for the image and the extension | Accepted |
| [29-console.md](29-console.md) | Rich console output and input, in the manner of Spectre.Console | Accepted |
| [30-site-theme.md](30-site-theme.md) | A theme of its own for the site: dark, typographic, a terminal's | Done |
