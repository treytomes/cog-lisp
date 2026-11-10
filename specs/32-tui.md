# Full-screen terminal programs: a Terminal.Gui for cog-lisp

| | |
|---|---|
| **Status** | Accepted (owner, 2026-11-10) with the leanings of §11; not yet built. A spike first (§3). Its amendment to `specs/29-console.md` (§5) is recorded there (§14) |
| **Asked for by** | The owner (2026-11-10): "One of the follow-up goals is to build a kind of TUI library that makes use of and extends the console library. Much like how console mirrors the C# Spectre.Console library, tui should mirror the Terminal.Gui v2 library." Foreseen in `specs/29-console.md` §9, whose decision 10 leaned to a second library, `(require 'tui)`, on the console's core |
| **Relates to** | `specs/29-console.md`: its core (§4.8, R-16 to R-23), which this library is built on and never reaches past; its renderables (R-7, R-17), which a view can hold. `specs/27-namespaces.md`, for the short names. Phase 11.1 (`specs/33-phase-11-pure-image.md`), whose `define-class` the views may move onto (decision 2) |

## 1. What Terminal.Gui v2 gives a C# program

[Terminal.Gui](https://github.com/gui-cs/Terminal.Gui) (MIT) is a .NET library for
full-screen programs in a terminal. Version 2 rebuilt most of version 1. What a
program gets from it, roughly in order of use:

- **An application and its loop:** `Application.Init`, `Run` and `Shutdown`; a
  loop that reads input, lays out and draws, and runs timers
  (`AddTimeout`) and work handed to it from other threads (`Invoke`). `Run`
  nests: a dialog run from a handler is modal, and `RequestStop` ends it.
- **Views in a tree:** every element is a `View` with subviews. A view has a
  `Frame` (where it is in its superview) and a `Viewport` (the part of its
  content it shows). In v2 every view can scroll: its content may be larger than
  its viewport.
- **Adornments:** each view has a `Margin`, a `Border` (a line style and a
  title) and a `Padding`, outside in. Borders that meet are joined by a
  `LineCanvas` (`┬`, `┼`, `┤`).
- **Computed layout:** a view's position is a `Pos` (absolute, a percentage,
  centered, anchored to the end, or relative to another view: `Pos.Right(v)`),
  and its size a `Dim` (absolute, a percentage, `Fill`, `Auto` from its text or
  subviews, or another view's). They add and subtract. v2 dropped v1's absolute
  layout mode: an integer is just `Pos.Absolute`.
- **Keyboard:** focus, moved by Tab and Shift+Tab among tab stops and by F6
  between tab groups; hot keys marked with `_` in a view's title (`_OK`);
  commands (`Accept`, `Activate`, `HotKey`, movement) bound to keys at the
  application, the view kind and the view; a configurable quit key (Escape).
- **Mouse:** clicks, double clicks, the wheel, dragging, and a grab that keeps
  the mouse on one view while a button is held. In v2 a view can also be moved
  and resized by the user (`Arrangement`).
- **Color:** schemes, each a style for every visual role a view draws in
  (normal, focus, hot, disabled and more), inherited down the tree, with 16
  colors or true color; themes from configuration.
- **Views:** labels, buttons, check boxes, option selectors, text fields and
  text views, list views and combo boxes, table views and tree views, menus
  (a menu bar and pop-over menus), status bars of shortcuts, tab views, progress
  bars and spinners, windows, dialogs and message boxes, a wizard, file
  dialogs, and more specialized ones (date fields, a color picker, a hex view, a
  graph view).
- **Testing:** a fake driver, a screen of fixed size in memory that a test
  feeds keys and mouse events and reads back cell by cell.

## 2. What cog-lisp has, and what it lacks

- **The console's core has most of the foundation**, built for this
  (`specs/29-console.md` §4.8 and §10):
  - **styles** and colors brought down to what the terminal shows (R-3, R-5),
    and **text measured in cells** (R-6);
  - **renderables** that render to lines at a width (R-17), and **regions** that
    clip lines at a place on the screen (R-18);
  - **input as events** with modifiers and pastes, read with a timeout and
    without stopping the VM (R-19, R-20);
  - **terminal modes** that nest and are restored at exit and on an error: raw
    mode, the alternate screen, a hidden cursor (R-21);
  - **one writer** (R-22), and a **test console that is a screen** (R-23).
  So a terminal driver, Terminal.Gui's lowest layer, is already the console's.
- **It lacks** what the console left to this spec (§9 of 29), and a little more:
  1. **the mouse:** a Windows console's mouse records are passed over
     (`LispTerminal`), and no mouse reports are decoded;
  2. **resizes that carry the new size:** a resize event exists, but the
     capabilities keep the size first detected, and on Linux nothing notices
     a resize;
  3. **the cursor put where text is typed**, and its shape;
  4. **a positioned write of a run of cells**, without `draw-region`'s padding
     to a whole row;
  5. **a test console for a running program:** a clock a test moves forward,
     its screen read in the middle of a run, and resizes and mouse events in its
     shorthand.
  §5 asks the console for each.
- **It lacks a way to describe objects with behavior.** cog-lisp has no record
  types or classes until Phase 11.1; the console's records are tagged vectors.
  Views need state that changes and behavior that a kind of view shares and a
  program extends (§4.3, decision 2).

## 3. The spike, before the design is fixed

Each question is answered by an experiment and recorded here, as
`specs/29-console.md` §3.1 records its own:

1. **The mouse on Windows:** with `ENABLE_MOUSE_INPUT` set, and quick-edit mode
   off (`ENABLE_EXTENDED_FLAGS` without `ENABLE_QUICK_EDIT_MODE`, or the console
   keeps the mouse for selecting text), do injected `MOUSE_EVENT` records arrive
   with their buttons, position, wheel and double-click flags? Can
   `LispTerminal` turn them into the SGR reports a Unix terminal sends
   (`ESC [ < b ; x ; y M`), as `sequenceForKey:state:` turns keys into xterm's
   sequences, so one decoder serves both? Is quick-edit mode back as it was
   afterwards?
2. **The mouse on Linux:** `ESC [ ? 1000 h` (buttons), `1002` (drags), `1003`
   (all motion) and `1006` (SGR encoding) under `script`, and turned off again.
3. **Resizes on Linux:** `SIGWINCH` cannot reach a LISP program through uFFI
   without a handler in C. What does polling `ioctl(TIOCGWINSZ)` while
   `read-event` waits cost, and at what interval is a resize noticed soon
   enough (leaning: every 250 ms)?
4. **Speed:** in cog-lisp, a frame of 120 by 40 cells built in a cell buffer,
   compared with the last frame, and the changed runs written:
   - a whole screen changed;
   - one cell changed (a key typed into a field);
   - a list of 1,000 items scrolled by a page.
   Timed on the test console and on conhost. This sets R-18's budget.
5. **The cursor:** placed with `ESC [ row ; col H` after drawing and shown,
   and shaped with `ESC [ n SP q` (block, underline, bar), in conhost and on
   Linux; and restored at exit.
6. **Interrupting a handler** (decision 6): while the event loop runs a
   handler, nothing reads input, so Ctrl+C is a byte nobody sees. Can a process
   at a higher priority peek at the input (`PeekConsoleInputW`; `poll`) every
   100 ms while a handler runs, and interrupt it, as the memory watchdog
   interrupts a computation (`LispShellCommand>>withMemoryLimit:do:`), without
   taking keys the loop will read later?
7. **Lines and wide characters in conhost:** a box with joined borders (`┬`,
   `┼`, `╪`) and a row holding wide East Asian characters, read back with
   `ReadConsoleOutputCharacterW`: do the cells line up?

## 4. The design (subject to the spike)

### 4.1 Layers

- **R-1. `tui` is a library on the console's core:** `lib/tui.lisp`,
  `(require 'tui)`, in plain cog-lisp. It draws only through the console's
  one writer, reads only through `read-event`, and enters terminal modes only
  through the console's `with-` forms (29's R-16, R-21, R-22). It holds no
  operating-system call and reaches no `%terminal-` primitive. What it needs
  from the operating system the console gives it first (§5).
- **R-2. A program that writes a renderable into a view uses the console's
  renderables as they are** (29's R-17): a table, a panel or a tree in a window
  is the console's table, panel or tree, rendered to lines at the view's width.

### 4.2 The application

- **R-3. `(tui-run view)` runs a program:** it makes `view` the top of the
  screen, runs the event loop until `(request-stop)` is called, and answers the
  value given to `request-stop` (`#f` when none).
  - **The outermost `tui-run` sets the terminal up and puts it back:** raw mode,
    the alternate screen, the cursor hidden but where a field puts it, and
    mouse reporting, each by the console's `with-` form, so they are restored
    however the run is left, and at exit. There is no separate `init` and
    `shutdown` to forget (decision 4).
  - **Without a terminal** (piped output or input) it is an error, `tui-run:
    needs a terminal`, except on a test console (R-31).
- **R-4. The loop, one turn at a time:** run what `tui-invoke` queued; lay out
  what needs it (R-13); draw what needs it, and write the frame (R-18); wait for
  an event no longer than until the next timer is due; dispatch the event
  (R-20 to R-25); run the timers that are due. Several events already waiting
  are dispatched before one draw, so typing ahead does not redraw per key.
- **R-5. Timers:** `(add-timeout ms proc)` runs `proc` on the loop after `ms`,
  and again every `ms` while it answers true (as Terminal.Gui's `Func<bool>`).
  It answers a token for `(remove-timeout token)`. Time is the console's clock
  (§5, C-5), so a test moves it forward.
- **R-6. Work from another process:** `(tui-invoke thunk)` runs `thunk` on the
  loop at its next turn, and is safe to call from any Smalltalk process (the
  console's lock, C-6). A computation in a background process reports its
  progress this way.
- **R-7. Runs nest, and the inner one is modal:** `tui-run` called from a
  handler runs a loop over its own top view, drawn over the screen as it is;
  input goes only to it until it stops, and the outer screen is drawn again as
  it was. `(request-stop value)` stops the innermost run. A dialog is this
  (R-28).
- **R-8. Errors and the quit key:**
  - **An error in a handler** ends every run, the terminal is put back, and the
    error is raised from the outermost `tui-run`, so a program's `guard` sees it
    on the main screen. With `tui-run`'s `on-error` option, a procedure receives
    the condition instead and the program keeps running (to show it in an
    `error-box`, say) (decision 7).
  - **The quit key** stops the innermost run, as `(request-stop)`. It is Escape,
    as Terminal.Gui v2's; `(quit-key)` is a parameter holding it (decision 5).

### 4.3 Views

- **R-9. A view is a value made by a kind of view and changed in place:**
  `(button "_OK" 'x 10 'y 2)`. Its state is properties: every option it is
  made with is one, read with `(view-ref v 'name)` and changed with
  `(view-set! v 'name value)`. A property knows what a change to it needs: a
  new `text` lays the view out again; a new `checked` only draws it again
  (`set-needs-layout!` and `set-needs-draw!` are there for a program's own).
  An unknown option or property is an error where it is named, as the
  console's options are (29's R-8).
  - **The common properties**, for every view: `x`, `y`, `width`, `height`
    (§4.4), `text`, `title`, `visible`, `enabled`, `can-focus`, `tab-stop`,
    `scheme`, `margin`, `border`, `padding`, `content-size`, `scroll-bars`,
    `subviews` and `data` (a program's own value).
  - **A few accessors** for what is read most: `view-text`, `view-value`,
    `view-superview`, `view-subviews`, `view-frame` and `view-viewport`
    (decision 3).
- **R-10. Views form a tree:** `(add-subview! parent child)`,
  `(remove-subview! parent child)`, and the `subviews` option. A view has one
  superview. Subviews are drawn in order, the later over the earlier.
- **R-11. A kind of view is a value too:** `(define-view-kind name parent
  option ...)` gives a program its own views, as a C# program subclasses `View`:
  its properties and their defaults, and procedures for drawing (R-19),
  measuring (for `dim-auto`), commands and key bindings (R-21). What it does not
  give it takes from `parent`. Every view in §4.9 is defined this way, on the
  kind `view`, so a program's kinds have nothing the library's lack.
- **R-12. A view shows its content through its viewport.** Its frame is where
  it is in its superview, its adornments included; its viewport is the part of
  its content inside them, and the viewport's position is how far the content
  is scrolled. The content is as large as the viewport unless `content-size`
  says otherwise; then the view scrolls (`scroll-to!`, the wheel, and the keys
  of a view that moves a selection), and `scroll-bars` shows where it is.

### 4.4 Layout

- **R-13. A position is a `pos`, a size a `dim`,** computed again whenever the
  screen or a view they depend on changes:

  | `pos` | is | Terminal.Gui |
  |---|---|---|
  | an integer `n` | `n` cells from the superview's viewport's start | `Pos.Absolute` |
  | `(pos-percent n)` | `n`% of the superview's viewport | `Pos.Percent` |
  | `(pos-center)` | centered | `Pos.Center` |
  | `(pos-anchor-end [n])` | `n` cells from the end, or at the end by its own size | `Pos.AnchorEnd` |
  | `(pos-left-of v)`, `(pos-right-of v)`, `(pos-top-of v)`, `(pos-bottom-of v)` | at another view's edge | `Pos.Left` and the rest |
  | `(pos-align alignment group)` | placed with the others of a group, as a dialog's buttons are | `Pos.Align` |
  | `(pos-computed proc)` | what `proc` answers | `Pos.Func` |

  | `dim` | is | Terminal.Gui |
  |---|---|---|
  | an integer `n` | `n` cells | `Dim.Absolute` |
  | `(dim-percent n)` | `n`% of the superview's viewport | `Dim.Percent` |
  | `(dim-fill [margin])` | to the end, less `margin` | `Dim.Fill` |
  | `(dim-auto ['text] ['content] ['min n] ['max n])` | as large as the view's text, its subviews, or both (the default) need | `Dim.Auto` |
  | `(dim-width-of v)`, `(dim-height-of v)` | another view's | `Dim.Width`, `Dim.Height` |
  | `(dim-computed proc)` | what `proc` answers | `Dim.Func` |

  `(pos+ p n)`, `(pos- p n)`, `(dim+ d n)` and `(dim- d n)` add and subtract,
  and each `-of` form takes an offset: `(pos-right-of label 1)`. Alignment is
  `start`, `center`, `end` or `fill`, as Terminal.Gui's.
- **R-14. Layout errors are found and named:** a `pos` or `dim` that depends
  on itself, through any chain of views, is an error naming the views; so is a
  reference to a view in another tree. A view that does not fit is clipped, not
  an error.
- **R-15. `dim-auto` asks a view its size** by its kind's measure: text by
  the console's measure (its widest line, in cells), a renderable by the
  console's `make-renderable` measure, a container by its subviews' layout.

### 4.5 Adornments and joined lines

- **R-16. Margin, border and padding**, outside in. Each is a thickness: an
  integer for every side, or `(left top right bottom)`, Terminal.Gui's order.
  - **A border** is one of the console's border sets (29's R-9: `square`,
    `rounded`, `heavy`, `double`, `ascii`, `none`), and `ascii` without
    Unicode. Its title is drawn in its top line, with its hot key (R-22),
    shortened with `…` (29's R-24) when there is no room.
  - **A margin** is transparent: the superview shows through it.
- **R-17. Lines that meet are joined:** a view with `join-lines` set draws
  its subviews' borders and its `line` views on one canvas, and where they
  meet it draws the junction (`├`, `┬`, `┼`, `╪`), as Terminal.Gui's
  `LineCanvas`. Lines of different sets meet with the junction Unicode has for
  the pair, where it has one, and with the outer view's set where it has none.

### 4.6 Drawing

- **R-18. The screen is a buffer of cells,** each a character and a style, as
  the test console's screen is (29's R-23). A turn of the loop draws the views
  that need it into the buffer, each clipped to its viewport and to every
  superview's, then compares the buffer with the last frame and writes only the
  runs of cells that changed (C-4), in one flush. A key typed into a field
  writes the cells it changed and moves the cursor, no more. The spike (§3
  item 4) sets the budget a turn must keep; `bench/` records it.
- **R-19. A kind draws with a canvas,** in its viewport's coordinates:
  `(canvas-text! c column row text style)`, `(canvas-lines! c column row
  lines)` (the console's lines, from `render-lines`), `(canvas-fill! c column
  row width height character style)` and `(canvas-line! c column row length
  direction border)` (onto the joined lines of R-17). A wide character cut by
  the clip edge is drawn as a space, never as half a character.
  - **The cursor:** the focused view's kind says where the cursor goes, in its
    viewport, and its shape, or that there is none; after a frame it is put
    there (C-3), or hidden.

### 4.7 Input

- **R-20. Keys go to the focused view first:** an event goes to the deepest
  focused view, then to each superview in turn, until one handles it; then to
  the hot keys of the top view's tree (R-22); then to the application's
  bindings, the quit key among them.
- **R-21. Keys run commands.** A kind declares the commands it has (`accept`,
  `activate`, `hot-key`, `up`, `down`, `page-down`, `select-all`, `copy` and so
  on: Terminal.Gui's `Command`s), and binds keys to them; a program binds more,
  to a view, `(bind-key! v '(ctrl #\s) 'save)`, a kind, or the application,
  `(bind-key! 'application 'f1 'help)`. A key is written in the console's event
  shorthand (29's R-15: `enter`, `#\a`, `(ctrl #\s)`). `(add-command! v 'save
  proc)` gives a view a command of its own.
- **R-22. Hot keys:** `_` before a character in a view's title or text marks
  it (`"_Save"`), drawn in the scheme's `hot` role. The character alone, or with
  Alt where the focused view takes characters, runs the view's `hot-key`
  command: a button is pressed, a label moves focus to the view after it. `__`
  is a plain `_`.
- **R-23. Handlers hear what views do:** `(on v 'accept proc)` runs `proc`
  with an event record when the view is accepted (Enter, a click on a button, a
  double click on a list item). The other events are `activate` (Space, a
  click: a check box toggled, an item chosen), `text-changed`,
  `value-changed`, `focus-changed`, `key` (every key, before the bindings) and
  `mouse`. A handler answering `#t` has handled it, and it goes no further.
  - **Accept rises:** an `accept` no handler takes goes to the superview, and
    in a dialog to its default button (`'default #t`), so Enter in a field
    presses OK, as in Terminal.Gui v2.
- **R-24. Focus:** a view with `can-focus` and `enabled` set can hold it. Tab
  and Shift+Tab move it among the tab stops of the current tab group, in tree
  order; F6 and Shift+F6 move between tab groups (a window, a frame view)
  (`tab-stop`: `stop`, `group` or `none`, Terminal.Gui's `TabBehavior`).
  `(set-focus! v)` moves it. The focused view, and each of its superviews, are
  drawn in the `focus` role.
- **R-25. The mouse** (C-1): a press, release, click, double click, drag, wheel
  and motion go to the deepest visible view under the pointer, its position
  given in that view's viewport. A click focuses a view that can hold focus
  and runs its `activate` command; the wheel scrolls the nearest view that
  scrolls. While a button is held, the view that took the press keeps the
  mouse until the release (Terminal.Gui's grab).

### 4.8 Schemes

- **R-26. A scheme is a style for each role a view draws in:** `normal`,
  `focus`, `hot-normal`, `hot-focus`, `disabled`, `active`, `highlight`,
  `editable` and `read-only` (Terminal.Gui's visual roles), each one of the
  console's styles (29's R-5). `(define-scheme name 'normal style ...)` makes
  one; a role not given comes from `base`. The library has `base`, `toplevel`,
  `dialog`, `menu` and `error`. A view's scheme is its own `scheme`, else its
  superview's.
- **R-27. Without color, every role stays visible.** On a console with
  `colors` `none` (a `NO_COLOR` terminal, 29's R-2), `focus` is drawn inverted,
  `disabled` dim, the `hot` roles underlined and `highlight` bold, so the focus
  and the hot keys show in black and white. On 16 or 256 colors, styles come
  down as the console brings them down (29's R-3).

### 4.9 The views

Each is a kind (R-11), with its own options as properties. Where Terminal.Gui
v2 renamed a view or is moving to a new one, the newer name is taken
(decision 1). The step is §6's.

| Terminal.Gui | tui | What it is | Step |
|---|---|---|---|
| `View` | `view` | the kind every view is made from; with a `draw` option, a program's own drawing | 2 |
| `Toplevel`, `Window` | `toplevel`, `window` | a top view; a window is one with a border, a title and a tab group | 2 |
| `FrameView` | `frame-view` | a bordered, titled container in a window, its own tab group | 2 |
| `Label` | `label` | text, wrapped or not, aligned; its hot key focuses the next view | 2 |
| `Button` | `button` | `accept` when pressed; `default` for a dialog's Enter | 2 |
| `CheckBox` | `check-box` | `checked`, `unchecked`, and `none` when `three-state` | 2 |
| `Line` | `line` | a horizontal or vertical line, joined (R-17) | 2 |
| (cog-lisp's own) | `renderable-view` | any of the console's renderables, or a procedure answering one, rendered at its width and scrolled when taller | 2 |
| `Dialog` | `dialog` | a modal window with buttons aligned along its bottom | 3 |
| `MessageBox` | `message-box`, `error-box` | a dialog with a message and buttons, answering the button chosen (R-28) | 3 |
| `TextField` | `text-field` | one line of text: the cursor, selection, words (Ctrl+Left and Right), undo and redo, cut, copy and paste (R-29), `secret`, and `validate` (Terminal.Gui's `TextValidateField`) | 3 |
| `TextView` | `text-view` | lines of text, wrapped or scrolled, `read-only` | 3 |
| `ListView` | `list-view` | items from a list or a source (R-30), one or several chosen | 4 |
| `ComboBox` | `combo-box` | a text field with a list below it | 4 |
| `OptionSelector` (`RadioGroup` before it) | `option-selector` | one of several options, its hot keys from their text | 4 |
| `TableView` | `table-view` | rows and columns from a source, a cell or row chosen, columns sized and scrolled | 4 |
| `TreeView` | `tree-view` | nodes from roots and a children procedure, opened and closed | 4 |
| `ProgressBar` | `progress-bar` | a fraction done, or a pulse when it is not known | 4 |
| `SpinnerView` | `spinner-view` | a spinner turned by a timer | 4 |
| `MenuBar`, `PopoverMenu` | `menu-bar`, `menu`, `menu-item`, `context-menu` | menus along the top and where the mouse is, with hot keys and shortcuts | 5 |
| `StatusBar`, `Shortcut` | `status-bar`, `shortcut` | keys and what they do, along the bottom | 5 |
| `TabView` | `tab-view` | pages behind tabs | 5 |
| `Wizard` | `wizard` | a dialog of steps, Back and Next | 6 |
| `OpenDialog`, `SaveDialog` | `open-dialog`, `save-dialog` | a file chosen, through cog-lisp's file procedures | 6 |
| `Arrangement` | `arrangement` (a property) | windows the user moves and resizes, with the mouse or Ctrl+F5 and the arrows | 6 |

Later, each on request: date and time fields, a date picker, a numeric field, a
slider, a color picker, a hex view, a graph view, a character map, and themes
read from a file.

### 4.10 Dialogs, data and the clipboard

- **R-28. `(message-box title message buttons)`** runs a dialog (R-7) and
  answers the index of the button chosen, or `#f` when it is left by the quit
  key, as Terminal.Gui's `MessageBox.Query` answers `-1`. `error-box` is the
  same in the `error` scheme. `(tui-run (dialog ...))` answers what its buttons'
  handlers give `request-stop`.
- **R-29. The clipboard** is the image's own, shared by every text view, with
  the console's pastes (29's R-19) pasted as typed text. The system's
  clipboard is later (decision 8).
- **R-30. Long lists are not copied.** A list view, a combo box and a table
  view take either a list (or vector) or a source: procedures answering how
  many items there are and the one at an index, and optionally how to render
  one. Only the rows shown are rendered, so a source of a million rows scrolls
  as fast as one of ten. A tree view takes its roots and a procedure answering a
  node's children, asked only when the node is opened.

### 4.11 Testing

- **R-31. A program runs on the test console unchanged** (29's R-23,
  amended by C-5): `(with-test-console '(width 60 height 20 events (...))
  (lambda () (tui-run win)))` answers the screen as the program left it. When
  the events run out, the run stops as if the quit key were pressed, so a test
  never waits.
  - **Time is the test's:** `(wait 500)` in the events moves the test console's
    clock 500 ms on, firing the timers due.
  - **A screen in the middle:** `(call thunk)` in the events runs `thunk` when
    it is reached, and `(test-console-screen)` answers the screen so far, so a
    test takes screens at the moments it chooses.
  - **The mouse and resizes:** `(click 10 3)`, `(double-click 10 3)`, `(press
    10 3)`, `(release 10 3)`, `(drag 12 3)`, `(wheel-down 10 3)` and `(resize 80
    24)`.
  - **Cells and styles:** `screen-cell` shows which view has the focus and
    which role each cell is drawn in.
- **R-32. Examples print screens.** An example runs its program on a test
  console with its events and prints the screen with `screen-text`, so its
  `.expected` file is plain text (29's R-3) and the manual shows what the
  program looks like.

## 5. What it needs from the console library (an amendment to 29)

Each of these is a change to `lib/console.lisp` and `LispTerminal`, written
into `specs/29-console.md` as a third amendment once this spec is accepted, and
built in step 1 (§6) with tests in `tests/lisp/console-core.lisp`. None of them
is a full-screen feature: a prompt or a live display may use any of them.

- **C-1. Mouse events:** `(with-mouse thunk)`, a scoped mode as the others are
  (29's R-21), turns mouse reports on (SGR encoding, buttons and drags; motion
  with `'motion #t`) and off, and at exit. `read-event` answers events of kind
  `mouse`, with `event-action` (`press`, `release`, `drag`, `move`, `wheel-up`,
  `wheel-down`), `event-button` (`left`, `middle`, `right`), `event-column`,
  `event-row` (from 1) and `event-modifiers`. On Windows `LispTerminal` turns
  mouse records into the same reports, and turns quick-edit mode off while the
  mode is on (§3 items 1 and 2). A double click is the tui's to tell, by time.
- **C-2. A resize carries its size:** a resize event has `event-columns` and
  `event-rows`, and `console-capabilities` answers them from then on. On Linux
  `read-event` polls the size while it waits (§3 item 3) and answers a resize
  when it changed.
- **C-3. The cursor:** `(move-cursor column row)` puts it, and `(cursor-shape
  shape)` shapes it (`block`, `underline`, `bar` or `default`), restored at
  exit. The test console's `screen-cursor` follows both.
- **C-4. A positioned run:** `(draw-segments column row segments)` writes
  segments at a place, clipped to the screen, without padding; and
  `(console-flush)` sends what was written.
- **C-5. The test console for a running program:** a clock, `(console-now)`
  (milliseconds; the test console's moves only by `(wait ms)`, and a
  `read-event` with a timeout on it answers `#f` and moves the clock by the
  timeout when a `wait` comes next); `(test-console-screen)`, the screen so far;
  and the shorthand of R-31 (`call`, `resize`, the mouse).
- **C-6. The lock:** `(with-console-lock thunk)`, the lock of 29's R-14,
  exported, so `tui-invoke` queues safely from another process. It is built
  with 29's step 4 or here, whichever comes first.
- **C-7. An interrupt key** (decision 6): `(with-interrupt-key key thunk)`
  watches for `key` while `thunk` runs and nothing reads input, and raises an
  `interrupted` condition in `thunk`'s process when it comes (§3 item 6).

## 6. Steps

1. **The spike and the console's amendment:** §3, then C-1 to C-7.
2. **The core:** views, kinds and properties (R-9 to R-12), layout (R-13 to
   R-15), adornments and joined lines (R-16, R-17), drawing (R-18, R-19), the
   loop, timers and `tui-invoke` (R-3 to R-8), keys, commands, hot keys, focus
   and the mouse (R-20 to R-25), schemes (R-26, R-27), testing (R-31, R-32); and
   the views of step 2 in §4.9.
3. **Text and dialogs:** text fields and text views, the clipboard, dialogs and
   message boxes (R-28, R-29).
4. **Lists and data:** list views, combo boxes, option selectors, table and
   tree views, sources (R-30), scroll bars, progress bars and spinners.
5. **Menus, status bars and tabs.**
6. **Wizards, file dialogs, and windows the user moves.**
7. **Later, each on request:** the views of §4.9's last paragraph.

Each step comes with LISP tests (R-31), an example in `examples/` (R-32), a
manual chapter ("Full-screen programs"), documentation in the image for every
export (the 10.1 suite), and the library listed under Libraries in
`docs/builtins.md`.

## 7. Examples

In the manual's teaching order, each building on the last, each printing the
screens it shows (R-32):

- `tui-hello.lisp`: a window with a label and a button that quits; `tui-run`
  and `request-stop`.
- `tui-layout.lisp`: the same views placed by `pos` and `dim`, at two screen
  sizes, and a resize between them.
- `tui-focus.lisp`: Tab, hot keys, a default button, and a key bound to a
  command.
- `tui-form.lisp` (step 3): a form of text fields with validation, ending in a
  message box.
- `tui-data.lisp` (step 4): a list view over a source and a table view, with a
  console `table` in a `renderable-view` beside them.
- `tui-timers.lisp`: a clock drawn by a timer, and a spinner while a
  background process computes and reports through `tui-invoke`.

A program reads like this:

```lisp
(require 'console)
(require 'tui)

(define prompt (label "_Name:" 'x 1 'y 1))
(define name (text-field "" 'x (pos-right-of prompt 1) 'y 1 'width 20))
(define ok (button "_OK" 'default #t 'x (pos-center) 'y (pos-bottom-of name 1)))
(on ok 'accept
    (lambda (e)
      (message-box "Hello" (string-append "Hello, " (view-text name) "!") '("_Close"))
      (request-stop (view-text name))))
(tui-run (window "Greeter" 'width (dim-fill) 'height (dim-fill)
                 'subviews (list prompt name ok)))
```

## 8. Acceptance criteria

- **AC-1:** the spike's answers are recorded in §3, and the design is fixed
  from them.
- **AC-2:** the console's amendment (C-1 to C-7) is in `specs/29-console.md`,
  with its checks in `tests/lisp/console-core.lisp`: mouse reports and Windows'
  translated records decoded, a resize's size, the cursor on the test console,
  the clock and a screen taken mid-run.
- **AC-3:** `tests/lisp/tui-layout.lisp` checks every `pos` and `dim` of
  R-13, their arithmetic and `dim-auto`, at three screen sizes, and the errors
  of R-14, by golden screens and by each view's frame.
- **AC-4:** `tests/lisp/tui-drawing.lisp` checks adornments, joined lines in
  each border set and between sets, clipping (a wide character at the edge), a
  hosted renderable, and that a frame after one change writes only the cells
  that changed (counted in `screen-output`).
- **AC-5:** `tests/lisp/tui-input.lisp` checks the order of R-20, commands and
  bindings at each level, hot keys, Tab and F6 order, a default button, the
  quit key, handlers that handle and those that do not, and the mouse of R-25:
  a click on a button, the wheel on a scrolled view, a drag kept by its view.
- **AC-6:** `tests/lisp/tui-loop.lisp` checks timers on the test clock (a
  500 ms timer fires 4 times in `(wait 2000)`, and stops when it answers false),
  `tui-invoke` from another Smalltalk process, nested runs and their answers,
  and an error in a handler: raised from `tui-run`, or given to `on-error`.
- **AC-7:** every view of each step has golden screens at two sizes, with
  `colors` `none` (the focus and the hot keys visible, R-27) and `truecolor`
  (each role's style in its cells), and with and without Unicode.
- **AC-8:** on real terminals, a program is driven by keys and the mouse, and
  the terminal is as it was afterwards (the main screen back, the cursor shown,
  the mouse off, quick-edit back on Windows, a typed line echoed), after the
  quit key and after an error:
  - on Windows, by `tests/tui/windows-check.bat` (a fresh conhost, key and mouse
    records injected with `WriteConsoleInputW`, the screen read back);
  - on Linux, by `tests/tui/linux-check.sh` (`script`);
  - in Windows Terminal and VS Code's terminal, by the owner.
- **AC-9:** `bench/` measures the turns of §3 item 4 and records them in
  `bench/results.md`, within the budget the spike set.
- **AC-10:** every example prints plain text to a pipe and is checked as
  examples are; the manual's chapter holds them.
- **AC-11:** every suite passes on Windows and Linux.

## 9. What it is not

- **Not a copy of Terminal.Gui's API.** Its concepts and names are kept, so a
  C# programmer finds them; the shapes are cog-lisp's: options as names and
  values, handlers as procedures, a run that answers a value, one scoped form
  for init and shutdown.
- **No graphics, no sound.** Only what a terminal shows.
- **No drivers of its own.** The console is the only driver (R-1); there is no
  curses, no .NET console, no second Windows path.

## 10. Licenses

Terminal.Gui is MIT. This is cog-lisp's own design and code, in cog-lisp. The
names programmers know (views, `Pos` and `Dim`, commands, roles) are reused,
and no code is copied. Nothing new is shipped: the terminal calls are the
operating system's, behind the console.

## 11. Decisions for the owner

Accepted with every leaning (owner, 2026-11-10).


1. **Which Terminal.Gui:** version 2, as asked; where v2 has renamed something
   or is still moving (`RadioGroup` to `OptionSelector`, color schemes to
   schemes of visual roles, the new menus), the newer form. Leaning: yes.
   **Owner (2026-11-10):** the concepts matter more than the names.
2. **What a view is made of:** cog-lisp has no classes before Phase 11.1.
   - **Records in LISP now** (tagged vectors, as the console's are), with kinds
     as tables of procedures and a parent (R-11), moved onto `define-class` when
     11.1 lands, with the same API.
   - **Wait for 11.1**, and build on `define-class` from the start.
   - **Smalltalk classes**, reached through interop: fastest, but against the
     pure image (Phase 11) and the console's rule of plain cog-lisp.
   Leaning: records now.
3. **Properties:** generic `view-ref` and `view-set!`, with accessors for the
   few read most (R-9); or a procedure per property per kind
   (`button-text`, `set-button-text!`). Leaning: generic, since every option is
   a property and a program's kinds add their own.
4. **One scoped `tui-run`**, with no separate init and shutdown (R-3). Leaning:
   yes; nothing to forget, and the terminal is always put back.
5. **The quit key:** Escape, as v2; or Ctrl+Q, as v1. Leaning: Escape, held in
   `(quit-key)`.
6. **A handler that never returns:** in raw mode Ctrl+C is a byte, and nothing
   reads it while a handler runs, so a looping handler holds the terminal raw
   until the process is killed (and a killed process restores nothing).
   Terminal.Gui has the same problem. Leaning: an interrupt key (C-7), Ctrl+C
   by default, if the spike (§3 item 6) shows it can be done without taking
   keys from the loop; else none, documented.
7. **An error in a handler:** ends the program and is raised from `tui-run`
   unless `on-error` is given (R-8); or shown in an error box and the program
   kept running. Leaning: raised, since a program that wants the box asks for
   it.
8. **The clipboard:** the image's own first (R-29); the system's
   (`OSC 52`, the Windows clipboard, `xclip`) later, on request. Leaning: yes.
9. **The first slice:** steps 1 and 2, each later step specified in more detail
   as it starts if the steps before change things. Leaning: yes.
10. **The names:** short and unprefixed (`button`, `window`, `label`), with
    `-view` where the console already has the renderable (`table-view` beside
    `table`, `tree-view` beside `tree`), and a program that wants them apart
    writing `(require 'tui 'prefix 'tui:)` (`specs/27-namespaces.md`). Leaning:
    yes.
