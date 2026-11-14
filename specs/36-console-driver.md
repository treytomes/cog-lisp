# Agents' tools: a console driver, to test a program at a real console

| | |
|---|---|
| **Status** | Implemented (2026-11-13; §5); its Later items done 2026-11-14 |
| **Asked for by** | The owner (2026-11-13), in `~/projects/lisp-expert`, whose weather REPL had one test left that only a person could do: "What would it take to give you the ability to test the weather REPL yourself?" The driver was built there; then: "If this works well, it may be worth adding that script to the `cog-lisp` skill." And: "make the cog-lisp change, and test the driver in AlmaLinux." |
| **Relates to** | `specs/29-console.md` (the prompts, `with-raw-mode`, the interactive console the driver gives a program), `specs/35-mcp-server.md` (the skill's `mcp.md`, which `console.md` follows), `specs/16-phase-10-documentation-and-editor.md` step 10.7 (the agent skill) |

## 1. The problem

A program that talks to a person (a REPL, `ask`, `confirm`, `choose`) reads
keys from a console. An agent's shell gives a program a pipe, or nothing: the
console library sees no console and takes its non-interactive paths (a line
for a choice, no raw mode), so an agent can test the commands but never the
prompts as a person meets them. The VS Code terminal and Windows Terminal give
the program a ConPTY console; a Linux terminal, a pty.

## 2. The approach

`tools/console_driver.py`, a Python program (and module): it starts a program in
a real console (pywinpty's ConPTY on Windows, ptyprocess's pty elsewhere),
renders its output with pyte, and runs a step script: type, press keys, wait
for text, check, end. Python because both console libraries and a terminal
emulator exist for it, prebuilt, installable without administrator rights; a
cog-lisp program cannot open a pseudo-console itself.

## 3. Requirements

- **R-1** The driver runs any program in a real console of a given size
  (`--cols`, `--rows`; 100 by 40), in `--cwd` or the current folder.
- **R-2** Steps: `send` (text and Enter), `type`, `key NAME [N]` (`enter`, `tab`,
  `esc`, `backspace`, arrows, `home`, `end`, `ctrl-<letter>`, and `eof`, the
  end of input: Ctrl+Z, Enter on Windows, Ctrl+D elsewhere, because Ctrl+Z
  suspends a program on Linux), `expect` and `expect-re` (in what was printed
  since the last input, escapes stripped), `expect-screen` and
  `expect-screen-re` (the rendered screen; the regex's `^` and `$` at each
  line), `refute`, `wait`, `settle`, `print`, `screen`, `exit [CODE]`; `#`
  comments.
- **R-3** Each wait has a timeout (`--timeout`, 20 s; `--start-timeout`, 90 s,
  for the first `expect`, while the image starts). A failure prints the step,
  what was printed since the last input and the screen, and exits 1; success
  prints `passed` and exits 0. `--transcript FILE` keeps all the output.
- **R-4** `tests/console/repl.txt` drives cog-lisp's own REPL: an answer, a
  definition kept for the next form, an error and its debug level, the end of
  input.
- **R-5** The skill teaches it in its own page, `console.md`, generated from
  `docs/skill/console.md` like `mcp.md`, under 3 KB; SKILL.md points to it in
  one line (its budget had 72 bytes left).
- **R-6** The release bundles carry `tools/console_driver.py` and the skill's
  `console.md`.
- **R-7** (2026-11-14, L-36.1) `tests/console/run.sh` and `run.bat` run every
  `NAME.txt` in `tests/console/` against `NAME.lisp` when there is one, else
  the REPL, and fail if any fails; CI runs them on Linux and on Windows after
  the suites, with the Python packages pinned. `confirm-enter.txt` is L-36.2's
  test: `y` and Enter at once, then the next lines read.

## 4. Acceptance criteria

- **AC-1** `tests/console/repl.txt` passes on Windows
  (`python tools/console_driver.py tests/console/repl.txt -- cmd.exe /c .\cog-lisp.bat`)
  and on Linux (`python3 ... -- ./cog-lisp.sh`).
- **AC-2** A failing step exits 1 and prints the step and the screen.
- **AC-3** In lisp-expert, the weather REPL's scenarios pass on both systems:
  `weather/test/console-repl.txt` (no network) and `console-live.txt` (the
  arrow-key chooser, `confirm`, `why`).
- **AC-4** The 10.7 suite: `console.md` stays under 3 KB, SKILL.md points to it,
  the driver it names exists, and every step and key it names is in the
  driver's own list (so the two cannot drift apart); SKILL.md stays under its
  budget.
- **AC-5** `release/smoke-test.sh` finds the driver and `console.md` in a bundle.
- **AC-6** (L-36.1) `tests/console/run.sh` and `run.bat` pass on both systems,
  and exit 1 when a scenario fails; CI's Linux and Windows jobs run them.
- **AC-7** (L-36.2) `tests/console/confirm-enter.txt` passes on both: after
  `y` and Enter at once, `confirm` answers yes, its next line starts at the
  left, the next `read-line` is empty, and the one after it `hello`.

## 5. As built (2026-11-13)

- AC-1: passed on Windows 11 (Python 3.12, pywinpty 3, pyte) and AlmaLinux 8
  under WSL 2 (Python 3.12, ptyprocess, pyte; cog-lisp bootstrapped and built
  there from a clone). AC-2: seen while writing the scenarios. AC-3: passed on
  both, with lisp-expert's 18 suites. AC-4: the 10.7 suite, 481 checks. AC-5: in
  the script; it runs with the next release.
- Found on the way:
  - Claude Code's shell on Windows sets `NoDefaultCurrentDirectoryInExePath`,
    so `cmd.exe /c cog-lisp.bat` is not found in the current folder: write
    `.\cog-lisp.bat`.
  - Git Bash turns `/c` into a path: write `cmd.exe //c` there.
  - `python -I` hides the user site-packages, where `pip install --user` puts
    the console libraries.
  - On Windows, Ctrl+Z, Enter reaches the REPL as a blank line before the end of
    input, so it prompts once more before it ends. Harmless.
  - A `confirm` in a console answers on its key; an Enter typed after it is
    left in the input. On Windows the next read takes it as a blank line; on
    Linux, after raw mode, it is a carriage return at the start of the next
    line, and the weather REPL read `kb` as an unknown command (L-36.2).
  - lisp-expert's `tools/test/test-tools.lisp` read C's `system()` result as an
    exit code; on Linux it is the wait status, the code times 256 (fixed there).
- 2026-11-14, L-36.1 and L-36.2 done (R-7, AC-6, AC-7):
  - L-36.2's cause: `cfmakeraw` turns `ICRNL` off, so an Enter typed while the
    terminal is raw is queued as a 13; when raw mode ends, Linux hands what is
    queued to the next read as a line without its newline, and Pharo's line
    reader joins it to the next line typed. `rawOn` now keeps `ICRNL` on, so it
    is queued as a 10: an empty line, as on Windows. The same test showed a
    second difference: `cfmakeraw` turns `OPOST` off too, so a newline the
    console wrote in raw mode (after `confirm`'s answer) went down a line
    without going back to the left; the weather REPL's `ask` drew its result's
    heading half across the screen. `rawOn` keeps `OPOST` on (Windows' raw mode
    leaves output alone). `specs/29-console.md` R-21 says so.
  - `confirm-enter.txt` failed on Linux before the change (the read waited for
    a newline that never came, and the answer's next line started at column
    14) and passes after it, on Linux and on Windows; `run.sh`, with a failing
    scenario added, exited 1.
  - CI's runs are new: the first push shows whether the hosted runners' consoles
    behave as these machines' do.

## 6. Later

Both items were done on 2026-11-14, in this spec (R-7; §5).

- **L-36.1 The console scenario in CI.** Done (R-7). Run `tests/console/repl.txt` on both
  runners (pywinpty on Windows, ptyprocess on Linux, pyte; `pip install`). It
  adds two Python packages to CI and a minute a runner. Consider it when the
  console library or the REPL's reading of input next changes, or when a
  console bug reaches a release.
- **L-36.2 An Enter after a key answer.** Done (`rawOn` keeps `ICRNL`; §5). After a prompt that answers on a key
  (`confirm`), an Enter typed by habit stays in the input: on Linux it becomes a
  carriage return glued to the start of the next line read. `with-raw-mode`
  could drain what is typed before it leaves raw mode, or `read-line` could drop
  a leading carriage return. Consider it with L-36.1, or when a person reports a
  command lost after a yes/no question.
