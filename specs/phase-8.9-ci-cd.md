# Phase 8.9 — CI/CD (and running on Linux)

| | |
|---|---|
| **Status** | Implemented (2026-11-04); CI green on GitHub; the release workflow proven by a dry run; AC-10 (the owner's install) to come with the first tag |
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

## 9. As implemented

- **Linux stdin was measured, not assumed.** In a container with the Linux VM:
  from a pipe, `Stdio stdin next:` blocks until data and answers 0 at the end (as
  `LispStdin` already assumed off Windows), so pipes and files worked unchanged.
  At a terminal it answers 0 bytes at once with `atEnd` false, before input and
  after Ctrl+D alike: the REPL printed its prompt and ended. libc's `read(0, ...)`
  blocks at a terminal, answers each line as typed (UTF-8 intact), and 0 on Ctrl+D;
  fd 0 is in blocking mode. So all Unix input goes through `read` (section 3.1's
  fallback became the only Unix path), and `isatty(0)` marks a terminal, which
  gets the break loop as a Windows console does (`LispStdin>>isInteractive`).
  Output needed nothing: `LispTextOutput` already wrote UTF-8 off Windows.
- **Scripts.** `scripts/pharo-vm.sh` finds the VM for the bash scripts;
  `bootstrap-pharo.sh` picks the VM zip by platform; new `tests/run-all.sh`,
  `tests/phase-5-runner.sh` and `bench/run-benchmarks.sh` match their `.bat`
  files. Programs run without input get `/dev/null` as stdin, so a suite never
  waits on a terminal.
- **The first Linux run passed 2505 of 2508.** One failure was the new runner's
  own bug; the other two were `examples/program/lib/util.lisp`, whose `file-name`
  split paths on `\` only. Now 2509/2509 on Linux both ways (the extra check is
  the REPL at a pseudo-terminal: echo, UTF-8, the break loop, Ctrl+D), and
  2506/2506 on Windows, where that check does not run.
- **One image, both platforms, checked.** A test release built in the container:
  the Linux bundle passes `release/smoke-test.sh` (32/32: every example, piped
  REPL input), and the Windows bundle, holding the image built on Linux, passes
  it on Windows (33/33, including `cog-lisp.bat`).
- **The VS Code extension** runs `cog-lisp.sh`/`build-image.sh` through bash
  off Windows, activates on either launcher, finds an unpacked release as well as
  a checkout, and its problem matcher accepts Linux paths (two new checks).
- **Workflows** (`ci.yml`, `release.yml`, `benchmarks.yml`) pass `actionlint`.
  `release.yml` reuses `ci.yml`, builds once on Linux, tests each bundle on its
  own platform, then publishes with `gh release create` (pre-release for a tag
  with a suffix). The `.vsix` takes the tag's version.
- **Licenses.** The Pharo zips carry no license files, so the bundles have
  `THIRD-PARTY-NOTICES.md` pointing to the Pharo and pharo-vm repositories (MIT)
  and to the libraries the VM folder ships. cog-lisp itself has no LICENSE file
  yet: the owner's decision.
- **On GitHub, three bugs only a runner could show** (each fixed, and the first
  red runs were AC-5's failing jobs):
  - `bootstrap-pharo.bat` checked the image version without `--headless`; on the
    Windows runner the VM opened a window and never returned (the job hung in
    *Bootstrap Pharo* for 20 minutes before it was cancelled).
  - The extension's grammar test counted only the Windows marks of
    `vscode-tmgrammar-test` (`√`, `×`); on Linux they are `✓`, `✖`: 0 files.
  - The runner suite read `ERRORLEVEL` after a `set`. GitHub runs `cmd` steps
    from a `.cmd` file, where `SET` resets `ERRORLEVEL` to 0; by hand (`.bat`
    rules) it does not. The cause was found from the run's uploaded outputs, once
    the upload looked where the suites write (`%TEMP%` is not `runner.temp` there).
- **AC-4: CI is green** on every job: Linux with each compiler (about a minute
  each), Windows, and the extension.
- **The release workflow, by a dry run.** Publishing a real release is the owner's
  step, so `release.yml` also runs by hand (`workflow_dispatch`, a version input):
  everything but `publish`. Its first run passed every job: the four test jobs,
  packaging (both bundles and the `.vsix`), the Linux bundle's smoke test (32/32)
  and the Windows bundle's, with the image built on Linux (33/33). AC-7's
  publishing step runs on the first tag.
- **The Pharo build is pinned** (owner, 2026-11-04). The "stable" Pharo 14
  download had been the latest build: the runners got `e649a7f87c` while this
  machine had `58e29ca31d`. `pharo.pins` now names the exact archive files on
  files.pharo.org with their SHA-256: the image build 788 (`58e29ca31d`, the build
  all of Phase 8 was developed and benchmarked on; byte-identical to the zip used
  here) and the VM v12.0.6-beta at commit `bebdbac` for Linux and Windows. Both
  bootstraps and `release/package.sh` read it and check every download (a cached
  zip that does not match is fetched again); the CI caches are keyed on it.
  Pinning found two latent bootstrap bugs, invisible on fresh CI runners: the
  Windows VM zip marks its files read-only, so re-running the bootstrap could not
  extract over them; and from Git Bash, the batch file's `tar` was GNU tar.
- **License** (owner, 2026-11-04): cog-lisp is under the MIT license (`LICENSE`),
  which every bundle carries; the extension's `package.json` says MIT.
- Still to come: AC-10, the owner's install on a Linux laptop from the first
  release.
