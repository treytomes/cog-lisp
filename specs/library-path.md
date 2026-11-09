# Loading cog-lisp's own libraries from anywhere: `require` and `*env*`

| | |
|---|---|
| **Status** | Accepted (2026-11-09), with the owner's changes: a global `*env*`, `require` of a symbol, and `load` free to answer more |
| **Found by** | Reviewing `~/projects/lisp-expert` (2026-11-09) |

## 1. The gap

**`load` resolves a relative path against the loading file.** So a program
outside cog-lisp's folder has no way to name the libraries that come with it
(`lib/cl.lisp`, `lib/test.lisp`).

`lisp-expert` therefore carries copies of cog-lisp 0.2.1's `lib/cl.lisp` and
`lib/test.lisp`, with documentation strings added. Those copies already lack
0.2.2's `setf`, `defsetf`, `aref` and `gethash`, and will fall further behind
with each release.

## 2. The shape (owner, 2026-11-09)

- **`load` stays simple:** load and run the file at the given path.
- **`require` is the smarter loader.** It takes a symbol, resolves it to a file
  through the library path, and hands that file to `load`, once.
- **The library path lives in a global environment, `*env*`**, as MiniScript's
  `env` does on the Mini Micro. One visible place holds what the running world
  knows about itself.
- The project is early enough to change what `load` answers, if that helps.

## 3. Requirements

- **R-1. `*env*`**, a global hash table keyed by symbols, created by the image
  at start-up:

  | Key | Value |
  |---|---|
  | `home` | cog-lisp's folder (R-4), as a string |
  | `library-path` | the folders `require` searches, a list of strings, in order |
  | `libraries` | each required library: its name and the full path it was loaded from, an alist |
  | `platform` | `windows` or `linux` |
  | `version` | the release, as a string (`"0.2.3"`); `"dev"` in a checkout |

  - A program reads it with `hash-table-ref` and changes it with generalized
    `set!` (Phase 9 step 9.4):
    `(set! (hash-table-ref *env* 'library-path) (cons "my/libs" (hash-table-ref *env* 'library-path)))`.
  - More keys may come later; a program must not assume these are all.
- **R-2. `(require 'name)`** resolves `name` to `name.lisp` in the first folder
  of the library path that has it, and loads it, once.
  - A name with slashes names a subfolder: `(require 'weather/json)` finds
    `weather/json.lisp`.
  - A second `(require 'name)` does nothing.
  - It answers the full path of the library, whether it loaded it now or before.
  - A name not found signals
    `require: no library named name in <the library path>`.
  - `(require-path 'name)` answers the path `require` would load, or `#f`,
    without loading anything.
- **R-3. The library path, at start-up:**
  1. each folder in the `COGLISP_PATH` environment variable (separated by `;` on
     Windows and `:` on Linux, as `PATH` is);
  2. `lib/` in cog-lisp's folder.
- **R-4. cog-lisp's folder is found from the launcher, not from the image.**
  - The launchers set `COGLISP_HOME` to their own folder.
  - The image's folder will not do: the language server runs on a copy of the
    image in the temporary folder (10.5), and `COGLISP_IMAGE` can point
    anywhere.
  - Without `COGLISP_HOME`, the image falls back to its own folder's parent.
- **R-5. `load` answers the full path of the file it loaded** (it answers
  nothing useful today). That is how `require` records a library's path in
  `*env*`. `load`'s resolution of a relative path, against the loading file, is
  unchanged.
- **R-6. Documentation:**
  - `*env*`, `require` and `require-path` are documented, and the reference is
    regenerated.
  - The manual gains an example; its Common Lisp chapter and the skill use
    `(require 'cl)`.
  - `lib/cl.lisp`'s header says to load it that way.

## 4. Acceptance criteria

- **AC-1:** a program in a temporary folder, outside cog-lisp's, runs
  `(require 'cl)` and `(require 'test)` and uses both, from a checkout and from
  an unpacked bundle, on Windows and Linux.
- **AC-2:** a second `require` of the same name does nothing. A library in a
  `COGLISP_PATH` folder, or in a folder a program puts first in `*env*`'s
  `library-path`, is found before cog-lisp's own. A name with a slash finds its
  subfolder.
- **AC-3:** an unknown name fails with the message of R-2. `require-path` answers
  `#f` for it.
- **AC-4:** `*env*` holds the keys of R-1 with the right values. After the two
  requires of AC-1, `libraries` names both, with their paths.
- **AC-5:** the language server, running on a copy of the image, resolves
  `(require 'cl)` in a document's diagnostics.
- **AC-6:** `(load "x.lisp")` answers the full path of `x.lisp`.
- Checked by a LISP test (`tests/lisp/`), and by the runner suite for running
  from another folder.

## 5. Decisions

1. **`require` of a symbol, `load` of a path** (owner, 2026-11-09). R7RS's
   `define-library` and `import` bring a module system (separate namespaces,
   exports): a Phase 11 question, which `require` does not stand in the way of.
2. **`*env*` is a hash table**, so a program changes it with generalized `set!`
   and needs no setter procedures of its own (proposed with this revision).
3. **What `lisp-expert` does then** (proposed): drop its copies and
   `(require 'cl)`. Its added documentation strings could come upstream into
   `lib/cl.lisp` and `lib/test.lisp`.
