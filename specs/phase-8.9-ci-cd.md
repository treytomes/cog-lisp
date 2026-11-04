# Phase 8.9 — CI/CD (and running on Linux)

| | |
|---|---|
| **Status** | Accepted (2026-11-04): the leanings of section 8 are the decisions |
| **Depends on** | Phase 8 (complete) |
| **Replaces** | README "After Phase 8: CI/CD", which assumed a Windows runner |

## 1. Goal

Every push and pull request is tested automatically, and a tagged release
publishes everything needed to try cog-lisp without building it: the image, the
launch scripts, the LISP library, the examples and the VS Code extension.

## 2. Which runner

**Linux is the primary runner, with a Windows job beside it.**

- **Cost does not decide it.** The repository is public, and GitHub-hosted
  standard runners are free for public repositories. (For a private repository,
  Windows minutes are billed at about twice the Linux rate; check current
  pricing before going private.)
- **Linux is faster to start and has better tooling**: bash throughout, the
  `timeout` command, cheap caching, and containers for local reproduction.
- **But cog-lisp runs only on Windows today** (section 3). Supporting Linux is part
  of this phase, and a Windows job keeps the Windows-only code tested: the
  console layer, the `.bat` scripts, the VS Code extension's launch path.
- **One image serves both.** A Spur image runs on any platform's VM, so the release
  image is built once, on Linux, and the Windows job checks that the same file
  runs there (AC-6).

## 3. Running on Linux: what has to change

What is already portable: the reader, both compilers, the runtime, every LISP
test, the examples and their `.expected` files (no Windows paths in them). What
is not:

### 3.1 The console and stdin layer
`LispTextOutput` (`src/coglisp-runtime.st`) and `LispStdin`
(`src/coglisp-shell.st`) call `kernel32.dll` through uFFI: `GetStdHandle`,
`GetFileType`, `WriteConsoleW`, `ReadConsoleW`, `PeekNamedPipe`. Every program's
output goes through `LispTextOutput`, so today nothing prints on Linux.

- **Choose at run time, not at build time** (the image is shared):
  `OSPlatform current isWindows` selects the Windows code as it is; anything
  else, the Unix code.
- **Output on Unix:** UTF-8 to `Stdio stdout` / `Stdio stderr`. Terminals there
  take UTF-8, so no console API is needed.
- **Input on Unix:** first verify how `Stdio stdin` behaves on the Linux VM (the
  Windows gotcha, "never blocks and cannot tell no-input-yet from end-of-input",
  may not hold). If it does not block, read with libc's `read(0, buffer, n)`
  through uFFI: it blocks until data or end of input, answers 0 at end, and a
  terminal in canonical mode does echo and line editing itself, as `ReadConsoleW`
  does on Windows.
- The behaviors stay what they are on Windows and are tested the same way:
  delayed pipe input, file input, end of input, UTF-8 both ways, and the REPL at a
  terminal (in CI, a pseudo-terminal from `script`).

### 3.2 Scripts
- `bootstrap-pharo.sh` picks the VM by `uname -s`: `pharo-vm-Linux-x86_64-stable.zip`
  on Linux, the Windows zip under Git Bash. The image zip is the same.
- `build-image.sh` and `cog-lisp.sh` run the VM found for the platform: `pharo`
  on Linux, `PharoConsole.exe` on Windows, both with `--headless`.
- New bash versions, kept in step with the `.bat` files (as CLAUDE.md already asks):
  `tests/run-all.sh`, `tests/phase-5-runner.sh`, `bench/run-benchmarks.sh`. The
  runner's delayed-input test uses `sleep 2` where the `.bat` uses `ping`.

### 3.3 The VS Code extension
It finds and launches `cog-lisp.bat`. On Linux and macOS it uses `cog-lisp.sh`
instead (`process.platform`), so the released `.vsix` works wherever the image
does.

### 3.4 Verifying it while developing
This machine has no WSL (retired 2026-09-22). Docker Desktop is installed
(29.4.1), with its engine stopped as of 2026-11-04: once started, Linux behavior
is checked in a container (`docker run` with the repository mounted). Otherwise,
push a branch and read the CI run.

## 4. Workflows

### 4.1 `ci.yml`: every push and pull request
- **`linux`** (`ubuntu-latest`): restore the cached Pharo downloads (keyed by
  `PHARO_VERSION`), `./bootstrap-pharo.sh`, `./build-image.sh`, `tests/run-all.sh`
  with the LISP compiler, then `npm ci && npm test` in `vscode/`.
- **`linux-smalltalk`**: `tests/run-all.sh` again with
  `COGLISP_COMPILER=smalltalk` (Phase 8 promises both pass).
- **`windows`** (`windows-latest`): `bootstrap-pharo.bat`, `tests\run-all.bat`.
- On failure, each job uploads the suite outputs (the run-all temp folder) as an
  artifact, so a failure can be read without rerunning it.
- Every job has `timeout-minutes` (a hung headless VM must not run for six hours),
  and the scripts kill a VM that outlives its suite.

### 4.2 `release.yml`: a tag `v*`
1. Run everything in 4.1; nothing is published unless all of it passes.
2. On Linux, build `cog-lisp.image` and its `.changes`, and package the
   extension (`npx @vscode/vsce package`).
3. On Windows, run the examples against **that** image (AC-6).
4. Publish a GitHub release with:
   - `cog-lisp-<version>-linux-x86_64.tar.gz` and
     `cog-lisp-<version>-windows-x86_64.zip`: the image, `.changes` and `.sources`,
     the platform's Pharo VM (MIT-licensed), the launch script, `lib/`,
     `examples/`, `README.md` and the licenses;
   - `cog-lisp-<version>.vsix`.

### 4.3 Not in CI
Benchmarks are not gated: shared runners are too noisy for timing checks (Phase
6 already found a busy machine distorts them). `run-benchmarks.sh` can run by
hand (`workflow_dispatch`) and upload `results.md` as an artifact.

## 5. Security

- The only credential is `GITHUB_TOKEN`. Workflows default to
  `permissions: contents: read`; only the release job gets `contents: write`.
- Pull requests from forks run the tests with the read-only token and never
  publish.
- Actions are pinned to a full commit SHA, with the version in a comment.
- Pharo downloads come from `files.pharo.org` over HTTPS; the cache keeps CI
  working, and fast, when that site is slow or down.

## 6. Acceptance criteria

- AC-1 `tests/run-all.sh` passes on Linux with the LISP compiler and with
  `COGLISP_COMPILER=smalltalk`, the same total as `run-all.bat`.
- AC-2 `tests\run-all.bat` still passes on Windows, both ways.
- AC-3 On Linux, stdin and output behave as on Windows: delayed pipe input, file
  input, end of input, UTF-8 text both ways (`λ` in and out), and the REPL at a
  pseudo-terminal reads lines and ends on Ctrl+D.
- AC-4 A push runs `ci.yml`, and every job passes on `master`.
- AC-5 A failing check fails its job (shown once on a throwaway branch, then
  deleted).
- AC-6 The image built on Linux runs the examples on Windows with matching
  `.expected` output.
- AC-7 A tag `v*` publishes a release with both bundles and the `.vsix`; on a
  clean machine, unpacking a bundle and running `cog-lisp` on an example works.
- AC-8 The VS Code extension launches `cog-lisp.sh` on Linux; `npm test` passes on
  both runners.
- AC-9 README and CLAUDE.md describe Linux support, the workflows, and the Linux
  gotchas found.
- AC-10 **The owner installs a release on a Linux laptop** from the release page
  alone (README instructions, no repository checkout): the REPL works at a real
  terminal, an example runs, and the `.vsix` launches the REPL in VS Code. This is
  the one check CI cannot make, since a runner is not a machine a user set up.
  Problems found become fixes and checks before the phase is called done.

## 7. Examples

| Example | Proves |
|---|---|
| (none new) | Every existing example runs on Linux and Windows against one image: the examples are the cross-platform check. |

## 8. Decisions (owner, 2026-11-04: the leanings below are accepted)

1. **How often does the Windows job run?** Leaning: every push, like the Linux
   jobs. It is free for a public repository, and the Windows-only code is where a
   change in shared code could break unnoticed. The alternative is pushes to
   `master` and tags only, for faster pull-request feedback.
2. **Both compilers on every push?** Leaning: yes. It is a second Linux job,
   about 2–3 minutes, running in parallel.
3. **Release bundles include the Pharo VM?** Leaning: yes. Without it, trying
   cog-lisp means a separate download first. The VM is MIT-licensed; its license
   goes in the bundle.
4. **Numbering:** "8.9" places this between Phase 8 and Phase 9, as 7.5–7.9 sit
   between 7 and 8.
5. **macOS:** out of scope (the VM exists, but there is no machine to verify it
   on). The `.sh` scripts and Unix stdio code should make it a small follow-up.
