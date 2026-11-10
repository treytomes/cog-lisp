# Rich console output and input: a Spectre.Console for cog-lisp

| | |
|---|---|
| **Status** | Steps 1 to 3 done (2026-11-10; §10 to §12); step 4 (live displays) to come. Accepted (owner, 2026-11-09) with the leanings of §8, and its amendment (§4.8, §9) with the leanings of §9 (owner, 2026-11-10). Decision 5 (names) is settled by `specs/27-namespaces.md`: the library keeps its short names, and a program that wants them apart writes `(require 'console 'prefix 'con:)`. A spike first (§3). Amendment proposed 2026-11-10, for a later full-screen library: §4.8, spike items 6 and 7, AC-8, §9. A second amendment, from lisp-expert's use of the renderables (R-24, §13), accepted with its leanings and built (owner, 2026-11-10). A third amendment, for the full-screen library (`specs/32-tui.md` §5, C-1 to C-7; §14 here), accepted with that spec (owner, 2026-11-10), not yet built |
| **Asked for by** | The owner (2026-11-09): "I'm used to writing C# console programs with the help of Spectre.Console. How do we provide cog-lisp with similar console I/O capabilities? I think this one needs a specification document." |
| **Relates to** | `LispTextOutput` and `LispStdin` (Phase 5; `src/coglisp-runtime.st`, `src/coglisp-shell.st`); the HTTP design (`specs/21-https-and-json.md`), whose rule it follows: the operating system's details stay inside cog-lisp |

## 1. What Spectre.Console gives a C# program

[Spectre.Console](https://spectreconsole.net/) (MIT) is a .NET library for console
programs. What a program gets from it, roughly in order of use:

- **Styles and markup:** `[bold red on blue]text[/]`, with colors from 16 up to
  24-bit, decorations (bold, dim, italic, underline, strikethrough, invert) and
  links. Text with no markup is escaped with `[[` and `]]`.
- **Capability detection:** whether output is a terminal, how many colors it
  shows, whether it shows Unicode, how wide it is. Output degrades by itself:
  piped to a file it carries no escape codes.
- **Layout, called renderables:** rules (a titled line across the screen),
  panels (a box around content), tables, trees, grids and columns, padding and
  alignment, bar charts, FIGlet text, and exceptions written readably.
- **Prompts:** text with a default and validation, secret text, confirmation,
  and choosing one or several items from a list with the arrow keys.
- **Live display:** a status line with a spinner while work runs, progress bars
  for several tasks, and a renderable redrawn in place as it changes.
- **Testing:** a test console that records what was written, at a fixed width
  and with fixed capabilities, and plays back key presses.

## 2. What cog-lisp has, and what it lacks

- **It has text output that is right:** `LispTextOutput` writes to a Windows
  console with `WriteConsoleW` (UTF-16, so the code page never matters), and to
  pipes and files as UTF-8. It knows which of the two it is writing to.
- **It knows what its input is:** `LispStdin` tells a Windows console, a file,
  a pipe and a Unix terminal apart, and reads a whole line, with the system
  doing the echo and line editing.
- **It lacks three things a library like this needs**, none of which a LISP
  program can do today without Smalltalk and the operating system's calls:
  1. **escape codes that a Windows console obeys:** a console shows ANSI escape
     sequences as text unless `ENABLE_VIRTUAL_TERMINAL_PROCESSING` is set on it;
  2. **the terminal's size:** `GetConsoleScreenBufferInfo` on Windows,
     `ioctl(TIOCGWINSZ)` on Unix;
  3. **one key at a time, without echo,** for menus driven by the arrow keys:
     a console mode without line input on Windows, `termios` raw mode on Unix,
     always restored afterwards.
- **And one thing the language has, which live displays need:** Pharo's
  processes. A higher-priority Smalltalk process can redraw a spinner while a
  LISP computation runs, as the memory watchdog already interrupts one
  (`LispShellCommand>>withMemoryLimit:do:`).

## 3. The spike, before the design is fixed

Each question is answered by an experiment and recorded here:

1. **Escape codes on Windows:** with `ENABLE_VIRTUAL_TERMINAL_PROCESSING` set
   through uFFI, do colors and cursor movement written with `WriteConsoleW`
   show correctly in each of these?
   - Windows Terminal;
   - the old console host (`conhost`);
   - VS Code's integrated terminal, where the extension's REPL runs (ConPTY).
2. **Keys:** in raw mode, do the arrow keys, Enter, Escape, Backspace and
   Ctrl+C arrive, and can the mode always be restored, after an error too?
   - On Windows: `ReadConsoleInputW`, or `ENABLE_VIRTUAL_TERMINAL_INPUT`, so
     that keys arrive as the same escape sequences Unix sends and one decoder
     serves both.
   - On Linux: `tcgetattr`, `cfmakeraw`, `tcsetattr` and `read(0, ...)`
     through uFFI.
3. **Size:** the terminal's columns and rows on both platforms, and what a
   pipe answers (no size: the width comes from `COLUMNS`, else 80).
4. **Drawing while computing:** a Smalltalk process at a higher priority
   redraws a spinner every 100 ms while a LISP loop runs, and the program's own
   output does not tear it (one lock around writes).
5. **Testing without a person:** the console's cells read back, colors
   included, after writing escape codes
   (`ReadConsoleOutputCharacterW` and `ReadConsoleOutputAttribute` on
   `CONOUT$`; on Linux a pseudo-terminal from `script`).
6. **Waiting for a key without stopping the VM** (§9): a uFFI call blocks every
   Smalltalk process until it returns, as `LispStdin`'s `ReadConsoleW` does
   today. Does a wait with a timeout, polled with a `Delay` as `LispProcess`
   polls a child, keep a spinner process turning while a prompt waits?
   - On Windows: `WaitForSingleObject` on the input handle with a timeout, then
     `ReadConsoleInputW`, or `PeekConsoleInputW`.
   - On Linux: `poll` on descriptor 0 with a timeout, or raw mode with
     `VMIN` 0 and `VTIME` set, then `read`.
7. **The rest of a full-screen terminal** (§9), each tried once: the alternate
   screen (`ESC [ ? 1049 h` and `l`), hiding the cursor, a resize noticed
   (`WINDOW_BUFFER_SIZE_EVENT`; `SIGWINCH`, or the size polled), and mouse
   reports (`ENABLE_MOUSE_INPUT`; `ESC [ ? 1006 h`).

### 3.1 The answers (2026-11-10)

Windows: a script in a fresh classic console (`start /wait conhost.exe
PharoConsole.exe ... st spike-win.st`), which writes, injects keys with
`WriteConsoleInputW` and reads the screen back. Linux: AlmaLinux 8 under WSL,
in a pseudo-terminal from `script`, with keys piped in.

1. **Escape codes on Windows work** once `ENABLE_VIRTUAL_TERMINAL_PROCESSING`
   is set: `ESC[31m` gives the attribute red (4), bold and underline show, and
   `ESC[5;10H` puts the next character at row 5, column 10. 24-bit color is
   accepted and shown as the nearest of the console's 16 (attribute 10 for
   `10;200;30`), so reading the screen back cannot check 24-bit color: R-23's
   test console checks it instead. (Windows Terminal and VS Code's terminal,
   both ConPTY, are left for AC-4 by the owner.) On Linux the terminal obeys
   them; nothing is turned on.
2. **Keys arrive as the same bytes on both.** With raw mode
   (`LINE_INPUT`, `ECHO_INPUT` and `PROCESSED_INPUT` off) and
   `ENABLE_VIRTUAL_TERMINAL_INPUT` on, Windows delivers injected keys as the
   escape sequences a Unix terminal sends: down is `27 91 66`, Enter `13`,
   Escape `27`, Ctrl+C `3`, and Alt+Up `27 91 49 59 51 65` (`ESC[1;3A`).
   Linux, in `cfmakeraw`'s raw mode, gave `27 91 66 97 13 27 3` for the same
   keys. So one decoder serves both. Ctrl+C is a byte, not a signal, in raw
   mode, which R-12 turns into a condition. A lone ESC and the start of a
   sequence are the same byte: the decoder reads ESC with nothing after it,
   within a moment, as the Escape key.
3. **Size:** `GetConsoleScreenBufferInfo`'s window was 120 by 30 (its buffer
   9001 rows); `ioctl(1, TIOCGWINSZ)` answered 100 by 30, as `stty` set it.
4. **Drawing while computing:** answered with item 6; the lock is step 4's.
5. **Testing without a person:** on Windows the screen reads back
   (`ReadConsoleOutputCharacterW`, `ReadConsoleOutputAttribute`) in a console
   the test starts; on Linux, `script` records what was written.
6. **Waiting without stopping the VM works:** polling with a timeout of 0
   (`WaitForSingleObject(input, 0)`; `poll(fd 0, timeout 0)`) and a 20 ms `Delay`
   between polls kept a higher-priority spinner process turning (18 turns in
   400 ms on Windows, 375 in 6 s on Linux, where its own `Delay` is the limit),
   and a key injected after 150 ms was read at 187 ms.
7. **The rest:** the alternate screen works (`ESC[?1049h` shows a blank
   screen, `ESC[?1049l` brings the main one back as it was); hiding the cursor
   writes without error; with `ENABLE_WINDOW_INPUT` a resize record
   (`WINDOW_BUFFER_SIZE_EVENT`, with the new size) is queued at once, ahead of an
   injected mouse record. Mouse reports through VT input (`ESC[?1006h`) are the
   full-screen spec's.
- **Restoring:** both console modes on Windows, and the `termios` record on
  Linux, read back the same as before the spike changed them.

## 4. The design (subject to the spike)

### 4.1 Two layers

- **The runtime** (`LispTerminal`, in `src/coglisp-runtime.st`) holds every
  operating-system call: it turns on escape codes, answers the size, enters and
  leaves raw mode, and reads a key. It is reached through a handful of
  internal primitives. A program never sees a handle, a console mode or a
  `termios` record.
- **The library** (`lib/console.lisp`, `(require 'console)`) is written in
  cog-lisp: styles, markup, measuring text, the renderables, prompts and live
  displays.

### 4.2 The console a program writes to

- **R-1. A console** is the current output port together with what it can do.
  `(console-capabilities)` answers a hash table:
  - `terminal?`: is it a terminal at all (not a pipe or a file);
  - `colors`: `none`, `16`, `256` or `truecolor`;
  - `unicode?`: can it show box-drawing characters;
  - `interactive?`: can it read keys (a terminal on both ends);
  - `width` and `height`.
- **R-2. Detection follows the conventions:** `NO_COLOR` turns color off,
  `FORCE_COLOR` turns it on for a pipe, `TERM=dumb` means none, and `COLORTERM`
  set to `truecolor` or `24bit` means 24-bit. A Windows console with escape
  codes on is `truecolor`. A program can override any capability, for one call
  or for a whole block (`with-console`).
- **R-3. Output degrades by itself:** to a pipe or a file there are no escape
  codes, and a live display writes its final state once. So a program's
  `.expected` output stays plain text, and every example can be checked as
  examples are today.

### 4.3 Styles and markup

- **R-4. Markup, as Spectre's:** `(print-markup "[bold green]done[/] in [blue]3 s[/]")`,
  with `print-markup-line` adding a newline.
  - **Styles:** a color name, `#rrggbb` or `rgb(r,g,b)`; `on` a background; and
    `bold`, `dim`, `italic`, `underline`, `strikethrough`, `invert` and
    `link=URL`.
  - **Tags** nest, and `[/]` closes the innermost one.
  - **Escapes:** `[[` and `]]` are `[` and `]`, and `(markup-escape text)`
    escapes a string that came from elsewhere.
  - **Errors:** a markup error names the position.
- **R-5. Styles are values too:** `(style 'bold 'red '(on blue))` and
  `(styled text style)`, for code that builds output rather than writing
  markup.
- **R-6. Text is measured in cells, not characters:** a wide East Asian
  character takes two cells and a combining mark none, so tables line up
  (`(text-width s)`).

### 4.4 Renderables

- **R-7. A renderable is a value; `(render x)` writes it.** The first set:
  - `rule`: a line across the width, with an optional title;
  - `panel`: content in a box, with a header and padding;
  - `table`: columns with headers, alignment and widths, rows of any
    renderable, borders and an optional title and caption. A table too wide for
    the console shrinks, wrapping its cells;
  - `tree`: nodes and children, with guide lines;
  - `grid` and `columns`: content side by side, without borders;
  - `padded` and `aligned`: wrappers.

  Plain strings and styled text are renderables, and so is any value, written
  as `display` writes it.
- **R-8. Options are symbol and value pairs**, since cog-lisp has no keyword
  arguments: `(panel "hi" 'header "Note" 'border 'rounded 'padding 1)`.
- **R-9. Borders** come in Spectre's familiar sets: `square`, `rounded`,
  `heavy`, `double`, `ascii` and `none`. A console without Unicode uses
  `ascii`.
- **R-24. A box is as wide as its words** (second amendment, §13). A table is
  at least as wide as its title and its caption, and a panel as its header,
  up to the width it is given; the cells it gains go where `expand` puts them.
  Only a width too narrow for them makes a title or a caption wrap, at its
  spaces, and a header or a rule's title shorten, ending in `…` (`...`
  without Unicode). Nothing is cut without a mark. The measure (`make-renderable`'s) answers the same
  widths, so a table in a grid, a column or another table's cell keeps its
  title on one line when there is room.

### 4.5 Prompts

- **R-10. On an interactive console:**
  - `(ask "Name?")`, with `'default`, `'validate` (a procedure answering `#t` or
    a message) and `'secret #t` (no echo);
  - `(confirm "Continue?")`, which answers `#t` or `#f`;
  - `(choose "Pick one" items)`: arrow keys and Enter;
  - `(choose-many "Pick some" items)`: Space toggles, Enter accepts;
  - each with a page size for long lists.
- **R-11. Without one** (piped input), a prompt reads a line: the answer, or
  the item's number or name. So a program that prompts can still be driven by
  a script, and tested.
- **R-12. Raw mode is always restored:** after Enter, Escape, Ctrl+C or an
  error. Ctrl+C in a prompt is a condition the program can catch, as an error
  is.

### 4.6 Live displays

- **R-13. Live displays:**
  - `(with-status "Working..." thunk)`: a spinner and a message while `thunk`
    runs, cleared when it returns;
  - `(with-progress (lambda (p) ...))`: tasks with bars, percentages, a rate
    and a time remaining, from `(progress-task p "Download" 100)` and
    `(progress-advance! task 10)`;
  - `(with-live renderable (lambda (live) ...))`: redraws the renderable in place
    on `(live-update! live new)`.
- **R-14. One lock** serializes what the spinner's process and the program
  write, and a program's own `display` during a live display goes above it, not
  through it.

### 4.7 Testing

- **R-15. A test console:** `(with-test-console options thunk)` runs thunk
  against a console of fixed width, colors and Unicode. It answers what was
  written, escape codes included, and plays back keys given as a list
  (`'(down down enter)`). So every renderable and prompt is tested in LISP, at
  any width, with no terminal at all.

### 4.8 Room for a full-screen library (§9)

These shape what §4.2 to §4.7 build, so a later Terminal.Gui-style library
builds on them rather than beside them. None of them is a full-screen feature.

- **R-16. Three layers, not two:** the runtime (`LispTerminal`); a console core
  in the library (capabilities, styles, segments, regions, input events); and
  what is built on the core: renderables, prompts and live displays now, the
  full-screen library later, which reuses the core and the renderables and does
  not reach past them to the runtime.
- **R-17. A renderable renders to lines, not to a port.** `(render-lines x
  width)` answers its lines, each a list of segments (text and a style), at most
  `width` cells wide; `(render x)` is that, written to the console. So anything
  that can place lines can host a renderable: a panel's body, a table's cell, a
  live region, and later a window.
- **R-18. Drawing is to a region:** a rectangle of the screen (column, row,
  width, height) that clips what is drawn into it. A live display (R-13) is a
  region at the cursor, redrawn by writing only the cells that changed, and the
  screen a full-screen program draws on is the same thing at the full size.
- **R-19. Input is events, not symbols:** `(read-event [timeout])` answers an
  event record, or `#f` after the timeout: a key (its name or character, and its
  modifiers: ctrl, alt, shift), a paste, and later a mouse event or a resize. A
  prompt reads events too. The key lists of R-15 are shorthand for key events.
- **R-20. Waiting for input never stops the VM** (spike item 6): every
  read waits with a timeout and polls, so a spinner turns while a prompt
  waits, and a full-screen program can run timers while it waits for a key.
- **R-21. Terminal modes are scoped and nest:** raw mode, the alternate
  screen, a hidden cursor and mouse reporting are each entered by a `with-`
  form and restored when it is left, however it is left, and again at exit
  (`runAtExit`), so a program stopped by an error never leaves the terminal
  raw. A prompt's raw mode inside a full-screen program's is not left early.
- **R-22. One writer:** all drawing goes through the console core, under R-14's
  lock, so a program's live displays now and its event loop later draw through
  the same place.
- **R-23. The test console is a screen:** a grid of cells (character and
  style) that interprets the escape codes the library writes, at a fixed size,
  fed a list of events. A test reads it back as plain text, or cell by cell
  with styles; R-15's recorded output is its log.

## 5. Steps

1. **The runtime layer and styles:** the spike, `LispTerminal`, capabilities,
   markup, styles, `text-width`.
2. **Renderables:** rule, panel, table, tree, grid, columns.
3. **Prompts.**
4. **Live displays.**
5. **Later, each on request:** bar charts, FIGlet text, exceptions written
   readably, a calendar, and color in the REPL's own prompt and break loop.

Each step comes with LISP tests (R-15), an example in `examples/` (plain output,
R-3), a manual chapter ("The console"), and documentation in the image.

## 6. Acceptance criteria

- **AC-1:** the spike's answers are recorded in §3, and the design is fixed
  from them.
- **AC-2:** `tests/lisp/console-*.lisp` check each requirement on a test
  console at several widths and with each color setting, golden output written
  out.
- **AC-3:** with output piped, every example prints plain text and is checked
  as examples are today.
- **AC-4:** on a real terminal, colors, a table and a menu driven by keys work:
  - on Windows, checked by injecting keys (`WriteConsoleInputW`) and reading
    the screen back;
  - on Linux, checked through `script`;
  - in VS Code's terminal, by the owner.
- **AC-5:** raw mode is restored after a prompt ends by Enter, Escape, Ctrl+C
  and an error, on both platforms: a line typed afterwards echoes.
- **AC-6:** a spinner keeps turning while a LISP loop computes, and the loop's
  own output is not torn.
- **AC-7:** every suite passes on Windows and Linux.
- **AC-8** (§4.8): a renderable renders to lines at a given width and into a
  region of the test console, clipped (R-17, R-18); a spinner keeps turning
  while a prompt waits for a key (R-20); and the terminal is restored after a
  nested raw mode and after an error (R-21).

## 7. Licenses

Spectre.Console is MIT. This is cog-lisp's own design and code, in cog-lisp. The
names programmers know (markup tags, border sets, renderable names) are reused,
and no code is copied. Nothing new is shipped: the terminal calls are the
operating system's.

## 8. Decisions for the owner

1. **Markup syntax:** Spectre's `[style]text[/]`, so the habit carries over.
   Leaning: yes.
2. **The API's shape:** renderables as values written by `render`, with options
   as symbol and value pairs (R-8); or builder procedures that change a table in
   place (`table-add-row!`), closer to Spectre's fluent style. Leaning: values,
   with `table-add-row!` too, for building a table in a loop.
3. **A library to `require`** (`console`), with a small built-in runtime layer;
   or built in. Leaning: a library, as `format-source` is.
4. **The first slice:** steps 1 and 2 (styles, markup, capabilities, the
   renderables), then prompts, then live displays, each specified in more
   detail as it starts if the spike changes things. Leaning: yes.
5. **The names:** `print-markup`, `render`, `ask`, `confirm`, `choose` and the
   rest, unprefixed; or each prefixed `console-`. Leaning: unprefixed, with
   `console-` only for the console itself (`console-capabilities`), since
   `(require 'console)` already says where they come from.
   **Owner (2026-11-09):** names like `rule` are generic and come up in
   `lisp-expert`; C# answers this with namespaces. So the names wait on
   `specs/27-namespaces.md`, written first: with it, the library keeps its short
   names, and a program that wants them apart writes
   `(require 'console 'prefix 'con:)`.

## 9. Later: a full-screen library (Terminal.Gui)

Asked for by the owner (2026-11-10): "I'm later going to want us to capture
`Terminal.Gui` style functionality. I want to make sure the development of
this spec does not preclude the later expansion." Proposed as an amendment
(§4.8, spike items 6 and 7, AC-8), for the owner to accept.

[Terminal.Gui](https://github.com/gui-cs/Terminal.Gui) (MIT) gives a .NET
program full-screen applications in a terminal: windows and dialogs, views
(labels, buttons, text fields, lists, menus, tabs) laid out relative to each
other, keyboard focus and navigation, the mouse, color schemes, and a main
loop with timers. That is its own spec, later. What it would need from this
one, and would not get from §4.1 to §4.7 as they stood:

- **Input that does not stop the VM.** A uFFI call blocks every Smalltalk
  process until it returns; `LispStdin`'s `ReadConsoleW` does so today. A prompt
  can live with that, but a main loop with timers, a spinner, or a redraw while
  waiting for a key cannot (R-20, spike item 6).
- **Drawing into a rectangle.** `(render x)` written straight to a port cannot
  put a table in a window, clipped, at a position (R-17, R-18).
- **Events with modifiers, and room for the mouse and resizes**, not key
  symbols alone (R-19).
- **Terminal modes held for a whole program**, nested and always restored, not
  raw mode for one prompt (R-21).
- **A test console that is a screen**, to test a layout cell by cell (R-23).

Each is a choice about the shape of what §4 builds, not more to build: the
first slice (§5 steps 1 and 2) builds the core of R-16 to R-19 and R-23 as it
builds styles and renderables; R-20 and R-21 come with prompts (step 3), and
R-22 with live displays (step 4). Mouse events, resizes and the alternate
screen are only tried in the spike, and built by the full-screen spec.

Decisions for the owner:

9. **Accept §4.8** as requirements of this spec. Leaning: yes; each costs
   little now and much later.
10. **The later library's name and home:** a second library, `(require 'tui)`,
    on this one's core (leaning), or more of `console`.

## 10. As built: step 1 (2026-11-10)

The spike (§3.1), then step 1 of §5 with the core §4.8 asks of it.

- **The runtime layer** is `LispTerminal` (`src/coglisp-runtime.st`), behind
  internal primitives (`%terminal-output-kind`, `-input-kind`,
  `-enable-escapes`, `-size`, `-raw-on`, `-raw-off`, `-raw?`, `-read`,
  `-flush`, `-on-restore`, `-restore`).
  - **Raw mode nests** (a depth count; the outermost saves and restores), and
    `LispTerminal restore` runs at exit (`runAtExit`) and when a program stops
    on an error (`failReport`). It also writes what the library left to undo
    (`%terminal-on-restore`: leaving the alternate screen, showing the cursor).
  - **Reading polls** (R-20): `WaitForSingleObject` or `poll` with a timeout of
    0, then a 10 ms `Delay`.
  - **Windows reads key records** (`ReadConsoleInputW`), not `ReadConsoleW`,
    which would block on a record with no character and pass over none. A key
    with no character (an arrow, a function key) is turned into the sequence a
    Unix terminal sends (xterm's, with its modifiers) by `LispTerminal
    sequenceForKey:state:`, so one decoder serves both. (Found by the Windows
    check: injected keys come as raw records even with VT input on.)
  - **NUL is a character device** to `GetFileType`, as a console is: a console
    is also one `GetConsoleMode` answers (found as `</dev/null` read as a
    console).
- **The library** is `lib/console.lisp`, `(require 'console)` (decision 3),
  plain cog-lisp, its records tagged vectors (cog-lisp has no
  `define-record-type`):
  - capabilities and `with-console` (R-1, R-2); styles, markup and its errors
    with their position, colors brought down to what the console has (R-3 to
    R-5); `text-width` (R-6);
  - `render-lines` and `make-renderable` (R-17), `render` (R-7, for text so
    far), regions (R-18), and every write through one procedure, `%write`
    (R-22, for step 4's lock);
  - `read-event` and its decoder, with key names, modifiers and pastes
    (R-19), `with-raw-mode`, `with-alternate-screen`, `with-hidden-cursor`
    (R-21);
  - the test console, an emulated screen (R-15, R-23).
- **Escape alone** is ESC with nothing behind it within 50 ms; ESC with a key at
  once behind it is Alt and that key, as terminals send it.
- **Checks:** `tests/lisp/console-core.lisp` (105 checks, AC-2);
  `examples/console.lisp`, plain text to a pipe (AC-3), in the manual's new
  chapter "The console"; and on real terminals (AC-4, AC-5, as far as step 1
  goes), `tests/console/windows-check.bat` (14/14: a fresh conhost, keys
  injected, the screen read back) and `tests/console/linux-check.sh` (10/10:
  `script`, keys piped in). Those two need a terminal, so they are run by hand,
  not by `run-all`. Windows Terminal and VS Code's terminal are the owner's
  (AC-4).

## 11. As built: step 2, the renderables (2026-11-10)

- **`rule`, `panel`, `table`, `grid`, `columns`, `tree`, `padded` and
  `aligned`** (R-7), each a renderable on step 1's `render-lines`, so each can
  hold any other: a table's cell a panel, a tree's leaf a table.
- **Options are names and values** (R-8); an unknown option, an option with no
  value, or an unknown border is an error where the renderable is made.
- **Borders** (R-9): `square`, `rounded`, `heavy`, `double`, `ascii` and `none`,
  and `ascii` for the others on a console without Unicode.
- **Tables** (decision 2): values, built with `table`'s `columns` and `rows`,
  or a row at a time with `table-add-row!` (and `table-add-column!`).
  Columns are text or `table-column`s, with `align` and a fixed `width`.
- **Measuring** joins the renderable protocol: `make-renderable` takes an
  optional measure, `(narrowest . widest)`, which text answers by its longest
  word and its longest line. One layout, `%fit`, serves tables, grids and
  columns: every column at its widest if they fit; else the widest give cells
  up first, down to their narrowest, then below it, when their words break.
  `expand` spreads what is left.
- **`render` drops a line's trailing plain spaces**, which show as nothing, so
  a program's plain output and its `.expected` file hold none; a styled space
  (a background) is kept.
- **Checks:** `tests/lisp/console-renderables.lisp` (52 checks: golden output
  at several widths, with and without Unicode, styles kept in cells and
  borders); `examples/console-renderables.lisp`, in the chapter "The console".

## 12. As built: step 3, the prompts (2026-11-10)

- **`ask`** (R-10): what is typed, with Backspace; `default` (shown, and
  answered for an empty answer), `validate` (a procedure answering `#t` or a
  message, shown before asking again; `#f` gets a message of its own),
  `secret` (typed as `*`), and `allow-empty`. A key with a modifier types
  nothing, and a paste types its text.
- **`confirm`**: `y` or `n` answers at once, Enter the `default`, which the hint
  shows (`[Y/n]`, `[y/N]`, or `[y/n]` with none).
- **`choose` and `choose-many`**: the arrow keys, Page Up and Down, Home and End;
  Space marks in `choose-many`. The list is drawn in place under the title,
  a page at a time (`page-size`, 10) with where it is (`(3 of 6)`), the
  current item in `highlight` (bold cyan), each shown by `display`. Each redraw
  goes back up over the last one, clearing its lines, so nothing doubles. On
  Enter the list goes and the title and the answer stay. The cursor is hidden
  while the list is shown (R-21), raw mode held for the whole prompt.
- **Without a console** (R-11): `ask` and `confirm` read a line; `choose` lists
  the items numbered and reads a number or a name, `choose-many` several,
  separated by spaces or commas. A wrong answer says why and asks again; the end
  of the input is an error. The line read ends the prompt's line, as an echo
  would, so a program's output stays in lines.
- **Cancelling** (R-12): Ctrl+C or Escape is an error, `prompt: cancelled`,
  which `prompt-cancelled?` tells; raw mode and the cursor are restored on the
  way out, as on every other way out.
- **The test console** takes `input`, a string of lines: then it is not
  interactive, and the prompts read those lines, as from a pipe. Its screen now
  takes a backspace back a cell, as a terminal does.
- **Checks:** `tests/lisp/console-prompts.lisp` (62 checks); on real terminals
  (AC-4, AC-5), `windows-check` 20/20 and `linux-check` 14/14, typing with a
  backspace into `ask`, choosing with the arrows, and cancelling with Ctrl+C,
  the terminal mode as it was after each; `examples/console-prompts.lisp`, in
  the chapter "The console".
- **Learned on the Windows console:** a clear (`ESC[2J`) on a screen with
  content scrolls the window down its buffer instead of erasing in place, so a
  test reading the screen back reads from the window's top
  (`srWindow.Top`), not from row 0.

## 13. Second amendment: a box as wide as its words (accepted and built 2026-11-10)

**Found by** lisp-expert's views (its `specs/01-console-views.md`), which put a
query's goal in a table's title. At 60 cells:

- **A title or a caption wider than its table wraps** into the table's width,
  however much room the console has: `A rather long title for a small table`
  over a two-column table became five lines of two words. lisp-expert moved its
  goals out of the titles, into a `rule` above each table.
- **A panel's header wider than its content is cut, without a mark:**
  `(panel "x" 'header "A rather long header for a panel")` drew `┌─ A ┐`. That
  is a bug: text is lost and nothing shows it.
- **So is a rule's title wider than the width:** at 20 cells, `(rule "A rather
  long title for a rule")` drew `── A rather long ───`.

Spectre.Console and Python's Rich both lay a title out at the table's width, so
the first is their behavior too. R-24 changes it here: a title, a caption or a
header is part of what the box must hold.

**The change** (R-24):

- `%table-measure` answers at least the title's and the caption's widest
  line, plus nothing for borders (a title sits outside them); `%table-lines`
  fits the columns to that width as `expand` does, when the content alone is
  narrower. Given less room than the title, the title wraps as now.
- A panel's measure answers at least the header's width plus its border's
  corners and gaps, and the panel widens its content to it. Given less room,
  the header shortens with `…` (`...` without Unicode).
- A rule already spans the width; a title too long for it shortens with `…`
  (`...` without Unicode), keeping at least one line cell at each side.

**Acceptance criteria** (in `tests/lisp/console-renderables.lisp`):

- **AC-24a.** At 60 cells, a two-column table titled `A rather long title for
  a small table` draws its title on one line, centered over a table as wide
  as it; the same with a long caption.
- **AC-24b.** At 20 cells the same table wraps its title at spaces within 20
  cells, as now.
- **AC-24c.** A panel headed `A rather long header for a panel` around `x` is
  as wide as its header at 60 cells; at 20 cells its header ends in `…`, and
  in `...` without Unicode.
- **AC-24c'.** At 20 cells, `(rule "A rather long title for a rule")` ends its
  title in `…`.
- **AC-24d.** `(columns (list t "next"))` with a titled table `t` keeps the
  title on one line when the columns fit.
- **AC-24e.** A table whose content is wider than its title draws exactly as
  before (the existing golden outputs do not change).

**Decisions for the owner:**

1. **Widen to the title, or wrap as Spectre does?** Leaning: widen. A wrapped
   title over a narrow table reads as broken, and a program that wants it
   narrow can wrap the title itself.
2. **Where the gained cells go.** Leaning: as `expand` spreads them, a cell to
   each column in turn, so a table looks the same whether it was widened by its
   title or by `expand`. The other choice, all of them to the last column,
   keeps narrow columns narrow (a `CF` column of `1.0`).
3. **A panel's header: shorten, or widen the panel as far as the console?**
   Leaning: both, as R-24 says: widen first, shorten only when the width runs
   out.

**As built (2026-11-10).** `%one-line` gives a title one line of at most the
cells it has, ended with `…` when cut, and `%cut-line` takes a line's first
cells; `rule` and `panel` draw their titles with them. A table fits its
columns to its title or caption by `%fit` with `expand`; its measure, and a
panel's, include them. A panel's header has five cells less than the panel
(a corner, a line and a space each side): it had four, so a header as wide as
that drew a top border one cell wider than the box. Checks: AC-24a to AC-24e in
`tests/lisp/console-renderables.lisp` (12 checks); every earlier golden output
is unchanged.

## 14. Third amendment: what the full-screen library needs (accepted 2026-11-10)

Accepted with `specs/32-tui.md` (owner, 2026-11-10), which §9 here foresaw
and whose step 1 builds it, after that spec's spike (its §3). The requirements
are that spec's §5, C-1 to C-7, kept there so they are read beside what uses
them:

- **C-1.** Mouse events, under `with-mouse` (R-21), with Windows' mouse records
  turned into the reports a Unix terminal sends, and quick-edit mode off while
  it is on.
- **C-2.** A resize event that carries the new size, which the capabilities
  answer from then on; on Linux, the size polled while `read-event` waits.
- **C-3.** `move-cursor` and `cursor-shape`, restored at exit.
- **C-4.** `draw-segments`, a positioned write without padding, and
  `console-flush`.
- **C-5.** A clock, `console-now`, which the test console moves only by
  `(wait ms)`; `test-console-screen`, the screen so far; and the shorthand for
  `call`, resizes and the mouse.
- **C-6.** `with-console-lock`, R-14's lock, exported.
- **C-7.** `with-interrupt-key`, if the spike shows it can be done.

None is a full-screen feature: a prompt or a live display may use any of them.
Checks: in `tests/lisp/console-core.lisp` (`specs/32-tui.md` AC-2).
