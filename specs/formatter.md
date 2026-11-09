# A source formatter for cog-lisp, in VS Code (issue #8)

| | |
|---|---|
| **Status** | Done (2026-11-09); accepted with the leanings of §4. R-2's one-line rule refined from lisp-expert's code (§5); AC-3's differences are the owner's to accept |
| **Issue** | [#8](https://github.com/treytomes/cog-lisp/issues/8) "Implement a VS.Code-compatible auto-formatter. Simple expressions can be retained in a single line. Complex expressions with sub-expressions should place each parameter on its own line, with closing parenthesis on their own line. Favor tabs over spaces." |
| **Relates to** | The language server, `lib/lsp.lisp` (Phase 10 step 10.5) |

## 1. What is there

- **No formatter.** The language server offers hover, completion and
  definitions (`lib/lsp.lisp`, its `capabilities`); the extension's own
  JavaScript knows only enough of the reader's lexical rules to find top-level
  forms (`vscode/src/forms.js`).
- **The reader cannot be the formatter's input:** it drops comments, and
  formatting must keep every comment, string and character literal exactly.
  The formatter works on the source's tokens.
- **The style the issue asks for is the one `~/projects/lisp-expert` is
  written in** (`expert/knowledge-base.lisp`'s `get-oav`, simplified):

  ```lisp
  (define (get-oav object attribute)
  	"Safely looks up an attribute for an object, returning '() if not found."
  	(let ((obj-entry (assoc object *oav-kb*)))
  		(if obj-entry
  			(let ((attr-entry (assoc attribute (cdr obj-entry))))
  				(if attr-entry
  					(cdr attr-entry)
  					'()
  				)
  			)
  			'()
  		)
  	)
  )
  ```

  - a form whose arguments hold no list stays on one line: `(cdr attr-entry)`;
  - otherwise the head stays on the first line with the arguments that
    belong there (`if`'s test, `let`'s bindings, `define`'s name), each other
    argument goes on its own line, one tab deeper, and the closing parenthesis
    goes on its own line, level with the form's start.

  cog-lisp's own sources use the traditional style (closing parentheses
  stacked, spaces), so the formatter runs only when asked.

## 2. Requirements

- **R-1. `(format-source text [options])`**, in LISP (`lib/format-source.lisp`,
  to `require`), answers the text formatted (decision 1):
  - it changes only whitespace between tokens: every token, comment and string
    comes out exactly as it went in, in order. A check of that is part of every
    run, and formatting that would break it answers an error instead;
  - formatting is idempotent: formatting its own output changes nothing;
  - text that does not read (an unclosed list, say) is an error naming the
    line, and nothing is changed.
- **R-2. The layout**, from the issue:
  - **one line** for any form that is not, and holds nothing that is, a form
    with a body: `let` and its kin, `cond`, `case`, `do`, `begin`, `guard`,
    `parameterize`, `syntax-rules`, `define-test`, the `cl` forms with bodies,
    and a `define` of a procedure. So `(+ a b)`, `(f (g x) (h y))`,
    `(if (null? x) 0 (car x))` and `(map (lambda (x) (* x x)) xs)` stay whole.
    (As first written, "no element is itself a list"; that put `(loop (+ i 1))`
    on three lines, which is not how lisp-expert is written. §5.)
  - **complex:** the head, then the form's *header* arguments on the first
    line, each remaining argument on its own line one level deeper, and `)` on
    its own line at the form's own level;
  - **header arguments** by form (decision 2): `define`, `define-macro`,
    `define-syntax`, `set!`, `lambda`, `let` and the other `let` forms, `do`,
    `when`, `unless`, `if`, `case`, `guard` and `parameterize`: 1; a named `let`: 2; `cond`, `begin`, `and`, `or`: 0; a call: 0
    (decision 3);
  - a `cond` or `case` clause is formatted as a form whose header is its test;
  - `let`'s binding list keeps each binding on one line when it is simple, and
    otherwise puts each binding on its own line;
  - a documentation string stays on its own line, as an argument does;
  - **comments:** a comment on a line of its own keeps its line, indented to
    the level of what follows it; a comment at the end of a line stays at the
    end of that token's line; blank lines between top-level forms are kept (at
    most two in a row); blank lines inside a form are kept as one.
  - a quoted datum (`'(a b c)`, `` `(...) ``) is laid out by the same rules,
    with no header arguments.
- **R-3. Indentation is tabs by default** ("Favor tabs over spaces"); the
  options choose spaces and their number. A deeper level is one tab.
- **R-4. The language server formats a document:** it announces
  `documentFormattingProvider`, and answers `textDocument/formatting` with one
  edit replacing the whole document, using the request's `tabSize` and
  `insertSpaces`. An error is answered as an LSP error and the document is not
  touched.
- **R-5. The extension:**
  - **Format Document** (Shift+Alt+F) works on `cog-lisp` files through the
    server;
  - it sets `[cog-lisp]` defaults of `editor.insertSpaces: false` and
    `editor.detectIndentation: false` (decision 4), so a new file indents with
    tabs; a user's own settings win;
  - it does not turn on format-on-save.
- **R-6. From the command line**, `tools/format.lisp FILE [--spaces N]` writes
  the formatted text to stdout (or `--write`, in place), so a file can be
  formatted without an editor, and a CI could check a style.

## 3. Acceptance criteria

- **AC-1:** `tests/lisp/format-source.lisp` checks each rule of R-2 and R-3
  on small inputs, with the expected text written out.
- **AC-2:** every `.lisp` file in this repository and in `lisp-expert`, put
  through `format-source`, keeps its tokens (R-1), is idempotent, and still
  compiles to the same forms; every `examples/` program prints the same output
  after formatting.
- **AC-3:** `lisp-expert`'s `expert/knowledge-base.lisp`, written in this
  style by hand, comes out unchanged or with differences listed here and
  accepted (the rules are measured against real code).
- **AC-4:** the language server answers `textDocument/formatting`
  (`vscode/test/lsp.test.js`); a VS Code test formats a document.
- **AC-5:** `tools/format.lisp` formats a file to stdout and with `--write`.

## 4. Decisions for the owner

1. **In LISP, in the language server** (R-1, R-4), or in the extension's
   JavaScript. In LISP it is one implementation for the editor, the command
   line and any other client, written in cog-lisp and tested in it; it needs a
   built image, as hover-by-server does. In JavaScript it would work without
   the image, but only in VS Code. Leaning: LISP.
2. **The header-argument table** (R-2): the one above, from `lisp-expert`'s
   code. A form not in it is laid out as a call. The table could later be
   extended by a program (as `define-special-form` extends the compiler).
3. **Calls keep no arguments on their first line** when complex, so `(foo
   (bar x) y)` becomes three lines. The alternative keeps the first argument
   on the head's line. Leaning: none, as the issue says "each parameter on its
   own line".
4. **Tabs as the default for `cog-lisp` files** in VS Code (R-5). Leaning:
   yes, as the issue says; a user's own settings override it.
5. **No line-length rule:** a simple form stays on one line however long it
   is. Leaning: none at first; a width can come later.

## 5. As built (2026-11-09)

- **`lib/format-source.lisp`** (`(require 'format-source)`): a tokenizer with
  the reader's lexical rules, a tree of the tokens (comments kept as nodes), and
  the layout. Every run tokenizes its own output and compares the tokens with
  the input's, answering an error rather than different code.
- **R-2's one-line rule was refined** before the code was kept: the literal
  rule ("no element is a list") broke every call that had a call inside it
  (`(loop (+ i 1))` on three lines), unlike the code it was taken from. The
  rule now: a form with a body always breaks; any other form breaks only when
  it holds one, or a comment. A binding list stays on one line when every
  binding does.
- **A Smalltalk send in `[brackets]` is copied exactly as written**, inside
  and all: its layout is Smalltalk's, not LISP's.
- **The language server** announces `documentFormattingProvider` and answers
  `textDocument/formatting` (`lsp-formatting`) with the request's `tabSize` and
  `insertSpaces`; the extension's `[cog-lisp]` defaults are
  `editor.insertSpaces: false` and `editor.detectIndentation: false`.
- **`tools/format.lisp FILE [--write] [--spaces N]`.**
- **Found and fixed: a program could not be given an argument starting with
  `-`.** Pharo's command-line parser (Clap) took `--write` for an option of its
  own and refused it, before cog-lisp ran. The launchers now send each argument
  after the program with a leading `:`, and the shell removes one, so every
  argument arrives as typed (a user's own `:x` too). Checked by both runner
  suites (`tests/runner/args/show.lisp`).
- **Found:** `#\page` is not a character name cog-lisp knows; the form feed is
  `(integer->char 12)`.
- **AC-1, AC-2:** `tests/lisp/format-source.lisp`, 293 checks: each rule, and
  every `.lisp` file of `lib/`, `examples/`, `tests/` and `tools/` keeping its
  tokens, idempotent and reading back the same forms. Run once by hand over
  both repositories too: 172 files, none failing (with the forms compared as
  written text, since `+nan.0` is not `equal?` to itself). Of the 41 examples
  with expected output, 39 print the same formatted; `cl-style` and `closures`
  print their own source text, so their output changes with the layout, as it
  should.
- **AC-3, for the owner** (`lisp-expert`'s `expert/knowledge-base.lisp`, 396
  lines, 364 after): the differences are of three kinds.
  1. Its newer parts stack their closing parentheses in the traditional
     style; the formatter puts each on its own line, as its hand-written parts
     do.
  2. A `cond` clause or an `if` whose parts all stay whole goes on one line,
     where the hand-written code sometimes broke it:
     `((null? current) (set-oav subject attribute value))`.
  3. A `'()` indented with spaces among tabs is indented with tabs.
- **AC-4:** `vscode/test/lsp.test.js` (formatting with tabs, with spaces, no
  edit when there is nothing to change, an error for text that does not read),
  and the VS Code test formats a document through the server.
- **AC-5:** `tools/format.lisp` to stdout, `--spaces 2`, `--write` in place,
  an unreadable file (exit 1, the line named) and a bad flag (exit 2).
