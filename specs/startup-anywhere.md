# Starting anywhere: the changes file, the current folder, and two runs at once

| | |
|---|---|
| **Status** | Accepted (2026-11-09), with the decisions as proposed |
| **Found by** | Reviewing `~/projects/lisp-expert` (2026-11-09), whose runner works around both bugs |
| **Fixes** | the collision of two VMs on one image (CLAUDE.md, 2026-11-06); a read-only install; a read-only current folder |

## 1. The bugs, as measured (2026-11-09)

cog-lisp fails at start-up, with a long Smalltalk stack, in three situations.
Each was reproduced on a Linux bundle in Docker, run as a user who does not own
it, and the first also on Windows.

| Case | What fails |
|---|---|
| **A second VM on the same image** (a REPL is open, and *Run File* or a terminal runs a program) | `Error: Cannot open non source file: cog-lisp.changes` |
| **An install the user cannot write to** (`/opt`, another user's, a sandbox) | the same error |
| **A current folder the user cannot write to** | `PrimitiveFailed: primitive #createDirectory: in UnixStore failed` |

Both errors also leave files behind:
- the first two put an **empty `cog-lisp.changes`** and a `PharoDebug.log` in the
  current folder (this happened in `lisp-expert` on Windows);
- the third creates `pharo-local/` there whenever it can.

**Cause of the first two** (read in the image, 2026-11-09):
- `PharoFilesOpener>>locateSources:forImage:` looks for the changes file in two
  places: the image's folder and the current folder.
- `SourceFile>>newSourceStreamReadOnly:` tries **every** place for writing
  before it tries any for reading.
- When the image's changes file cannot be written (the first VM holds it, or
  the folder is read-only), opening the current folder's "succeeds" by creating
  a new, empty file.
- `SourceFile>>tryOpenReadOnly:` then refuses a source file of size 0.
- The read-only open of the real file, which would have worked, is never
  reached.

This is why `lisp-expert`'s runner `cd`s into the install first. From there,
the current folder's changes file *is* the real one, and it opens read-only.

**Cause of the third:**
- At start-up, `PharoOptionsHandler>>runPreferences` resumes the stored
  settings, and `SystemSettingsPersistence` builds the settings tree.
- `StPlaygroundPresenter class>>settingsOn:` then calls
  `defaultCacheDirectory ensureCreateDirectory`: `pharo-local/play-cache`, in
  the current folder.
- cog-lisp has no use for the Playground or for stored settings.

## 2. Requirements

- **R-1. Only the image's folder** holds the changes and sources files.
  - cog-lisp's image overrides `PharoFilesOpener>>locateSources:forImage:` to
    look in `FileLocator imageDirectory` alone, never in the current folder.
  - The override lives in `src/coglisp-shell.st`, with the start-up code.
- **R-2. A changes file that cannot be written is opened read-only**, and one
  that cannot be opened at all (Windows may refuse while another VM holds it) is
  left out: the image runs without it.
  - Either way, **nothing is printed**. Pharo's `informProblemInChanges:` would
    otherwise tell stdout, and a program's output must stay byte-exact.
  - What a run without the changes file loses: the source text of the Smalltalk
    methods filed in from `src/`, which then show decompiled. cog-lisp's own
    procedures keep their source in the image, so `procedure-source` is
    unaffected.
- **R-3. No stored settings at start-up.** Both launchers (`cog-lisp.bat`,
  `cog-lisp.sh`) pass `--no-default-preferences` after the image name.
  - Checked: with it, a run in a read-only folder works, even with the install
    read-only too.
  - `build-image` passes it too, so a build cannot depend on a person's stored
    settings.
- **R-4. Nothing is written to the current folder** by a run that succeeds: no
  `cog-lisp.changes`, no `pharo-local/`, no `PharoDebug.log`.
  - Nor beside the image: Epicea (Pharo's log of code changes) created
    `pharo-local/ombu-sessions` there at every start-up (found while building,
    2026-11-09). The build turns Epicea off and takes it off the start-up list;
    cog-lisp keeps its own source.
- **R-5. Two runs at once on one image work**: a REPL left open, and a program,
  or the language server, started beside it.
  - The extension's server keeps its private copy of the image (10.5), because
    a copy also survives a rebuild.
  - The rule in CLAUDE.md, that two VMs on one image collide, is rewritten.
- **R-6. The build is unchanged.** It writes the changes file, which is
  writable there.
  - If the changes file is read-only when a build runs, the build stops with a
    clear message instead of losing method sources.

## 3. The spike first

Two things are not known yet. Each is settled by an experiment before R-2 is
built:
- **On Windows**, can a second VM open the changes file read-only while the
  first holds it for writing? If it can, two runs both keep their method
  sources. If not, the second runs without the file, which R-2 allows.
- **Does `informProblemInChanges:` print to stdout headless?** If it does, R-2
  silences it. If it does not, R-2 only has to keep it that way.

## 4. Acceptance criteria

- **AC-1:** on Linux, in Docker, run as a user who does not own the bundle,
  `examples/hello.lisp` runs and prints exactly its `.expected` in all four of
  these cases, and the current folder is left unchanged:
  - the current folder writable and the install read-only;
  - the current folder read-only;
  - the home folder read-only;
  - all three read-only.
- **AC-2:** on Windows and on Linux, while another run holds the image, a program
  run from the same checkout succeeds, with exact output, and the first run
  finishes undisturbed.
  - The holder is a program that waits six seconds, so the `.bat` runner can run
    both at once in a pipe (`A | B`).
  - On Linux a REPL holds it too, and still answers afterwards.
- **AC-3:** a run writes nothing to its current folder, on both platforms. On
  Linux, as a user other than root, a run from a read-only folder works. (A
  Windows folder cannot simply be made read-only, so there the check that
  nothing is written stands for it.)
- **AC-4:** every suite passes. `build-image` still records method sources: a
  method filed in from `src/` shows its source, not a decompilation.
- **AC-5:** `release/smoke-test.sh` runs a bundle that is made read-only
  (`chmod -R a-w`) from a read-only folder.

The checks go in `tests/phase-5-runner.bat` and `.sh`, which already run
programs and REPL sessions. The cases in Docker run in `release/smoke-test.sh`
on CI's Linux runner.

## 5. As built (2026-11-09)

- **The spike's answers:**
  - **Windows:** a second VM opens the changes file read-only while the first
    holds it for writing. It read 2,095,431 bytes; only opening it for writing
    failed. So two runs both keep their method sources.
  - **The notice:** with the changes file opened read-only, stdout was exactly
    the program's output and stderr was empty. `informProblemInChanges:` says
    nothing headless, so nothing needs silencing.
- **The changes:**
  - R-1: `PharoFilesOpener>>locateSources:forImage:` is overridden in
    `src/coglisp-shell.st`, to look in the image's folder only.
  - R-3: `--no-default-preferences` is passed after the image name by
    `cog-lisp.bat`/`.sh`, `build-image.bat`/`.sh`, `tests/run-all.bat`/`.sh` and
    `bench/run-benchmarks.bat`/`.sh`.
  - R-4: `build/build.st` disables Epicea, resets it, and unregisters
    `EpMonitor` and `EpLostChangesDetector` from start-up.
  - R-6: `build/build.st` stops if the seed's changes file is read-only.
- **R-6 cannot show its message until the seed has this fix.** The VM running the
  build *is* the seed, so a seed of v0.2.2 or earlier, held by another VM, still
  fails at start-up with the old error before `build.st` runs. Either way the
  build fails cleanly.
  - Found on the way: `build-image` deletes the old `pharo/cog-lisp.image` before
    building, so a failed build leaves none. That was so before, and is left for
    another change.
- **Checks:**
  - Linux, in Docker, as a user who does not own the bundle: all four cases of
    AC-1 pass, with exact output, empty stderr, and the current folder
    unchanged.
  - Windows: `tests/phase-5-runner.bat` passes 132/132, with AC-2 and AC-3.
  - `tests/phase-5-runner.sh` gains AC-2 (including the REPL case) and AC-3.
  - `release/smoke-test.sh` gains AC-5: a read-only bundle, run from a read-only
    folder, as a user other than root (CI's runner).

## 6. Risks

- **Pharo's start-up order.** The changes file is opened by a start-up handler
  that runs before cog-lisp's code. The override must be installed in the saved
  image (it is: the build saves it), and it must not depend on anything loaded
  later.
- **The seed rule** (CLAUDE.md): the new `src/` must still run the seed's
  compiler for one build. An override of a Pharo method does not touch the
  compiler.

## 7. Decisions (owner, 2026-11-09: as proposed)

1. **Where this sits in the plan.** Proposed: now, before Phase 11, as a small
   step of its own. It hurts every user who keeps a REPL open.
2. **Whether the language server goes back to the checkout's image** once two
   runs can share it. Proposed: no. The copy also means a rebuild never pulls
   the image out from under a running server.
