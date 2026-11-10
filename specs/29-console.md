# Rich console output and input: a Spectre.Console for cog-lisp

| | |
|---|---|
| **Status** | Accepted (owner, 2026-11-09) with the leanings of §8. Decision 5 (names) is settled by `specs/27-namespaces.md`: the library keeps its short names, and a program that wants them apart writes `(require 'console 'prefix 'con:)`. A spike first (§3) |
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
