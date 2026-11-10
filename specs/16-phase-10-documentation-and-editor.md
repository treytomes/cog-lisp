# Phase 10 — Knowing the language: documentation, the manual, the editor

| | |
|---|---|
| **Status** | 10.1–10.7 done (2026-11-06). Accepted 2026-11-05, with the owner's decisions (§7); decision 4 accepted with 10.5's detailed spec. 10.6 and 10.7 appended and accepted by the owner (2026-11-06) |
| **Depends on** | Phase 9 (the language it documents) |
| **Feeds** | Phase 11 (the pure image; its LISP-visible tools join the reference) |
| **Review items** | C-18 (compile errors carry no position); R-17 considered and left with the REPL (§7) |

## 1. Goal

Make cog-lisp knowable, by a person reading and by the editor, from one source
of truth kept in the image:

- every built-in documented where it is defined;
- a reference of the built-ins, generated from that documentation;
- hover help in VS Code;
- a user manual built from the examples, whose code and output the suites
  already check;
- a language server served by the image itself, if the spike says it can be;
- the manual and the reference published on the web (10.6, appended
  2026-11-06).

These were the README's "Later" sections (owner ideas, 2026-11-04). The owner
moved them ahead of the pure image (now Phase 11) on 2026-11-05.

## 2. Where we start (measured 2026-11-05)

- **The image has 643 bound globals:**

  | Kind | All | Public |
  |---|---:|---:|
  | primitives | 253 | 249 |
  | LISP procedures | 321 | about 21 |
  | `syntax-rules` forms | 14 | 14 |
  | `define-macro` macros | 29 | 0 |
  | other values | 26 | 3 |

  - The non-public LISP procedures are the compiler's internals (`lc-`, `rd-`,
    `cg-`, `sr-`, ...).
  - The `define-macro` macros are the code generator's accessors.
  - There are 16 special forms besides.
  - So the public surface is about 300 names. None has documentation: there is
    nowhere to keep it.
- **Procedures keep their source** (`procedure-source`). Primitives have none.
  A primitive knows its arity, but not its parameter names.
- **Examples:** 36, every one with an `.expected` file the runner suite checks,
  and every one opening with a comment that explains it.
- **JSON:** Pharo has `STONJSON` (`toString:`, `fromString:`). NeoJSON is not
  in the image.
- **stdin is read a line at a time** (`LispStdin`). An LSP message is
  `Content-Length: n`, a blank line, then n bytes of JSON with **no newline
  after it**, so a line reader would wait for the next message before it saw
  this one. A server needs to read exact byte counts: on a Windows pipe and a
  Linux pipe alike.
- **The VS Code extension** is plain JavaScript (`vscode/src/`, 302 lines) with
  no runtime dependencies. It has a grammar, run and REPL commands, and a
  problem matcher for `path:line:col: error:`.
- **Compile errors carry no position** (review C-18). A runtime error raised
  while a file loads is located at its top-level form (`LispLocatedError`).

## 3. Principles

- **One source of truth.** Documentation lives with each definition, in the
  image. Everything else is generated from it, with a check that the generated
  copy matches:
  - the reference;
  - the editor's offline data;
  - the manual's code and output.

  A built-in without documentation fails a test.
- **The examples stay the manual's backbone.** A chapter's code is an example,
  and its output is the example's `.expected`, already verified.
- **The editor asks the image** where it can (the language server), and reads
  generated data where it cannot (offline hover). Nothing about the language is
  re-derived in JavaScript.
- **The self-hosting rule holds.** The seed compiles `lib/core.lisp` and
  `lib/compiler/`, so documentation forms there may use only what the pinned
  seed understands (9.1).
- **Every step lands green**, with tests and an example, one commit per step, and
  a status line below.

## 4. Steps

### 10.1 Documentation in the image
Two parts, around a release: the self-hosting rule (9.1) means `lib/core.lisp`
can use a new `define-syntax` argument only once a seed has it. The owner chose
the cleaner form and the release it needs over a stopgap call (2026-11-05).

**10.1a: the machinery, and everything the seed's compiler does not compile.**
- **Where documentation is kept.** A procedure, a macro and a special form each
  carry a documentation string. `(documentation 'name)` answers the
  documentation of what `name` is bound to: a global or a special form.
  `(procedure-documentation f)` answers a procedure's.
- **How it is written:**
  - *A primitive* gets its documentation where it is installed, beside its block
    (`src/coglisp-runtime.st`).
  - *A `define`* (and a `define-macro`) whose body is a string followed by at
    least one more form keeps that string as its documentation, as Common Lisp
    does. The string is still evaluated, so the R7RS meaning is unchanged.
  - *A `define-syntax`* takes an optional string before its transformer:
    `(define-syntax when "(when test body ...)\n..." (syntax-rules ...))`, at
    top level and in a body. `let-syntax` bindings take none.
  - *A special form* is documented where the compiler defines it:
    `(define-special-form 'if "(if test then [else])\n..." translator)`. This is
    a procedure call, which the seed compiles, so `lib/compiler/` can use it at
    once.
- **Its shape.** The first line is the call form, with parameter names:
  `(string-ref string k)`. The rest says what it does, in a sentence or two. A
  primitive's parameter names come from this first line; a LISP procedure's from
  its source.
- **The category** is the section of the reference an entry appears in:
  - for a primitive, the installer that defines it (`installStringsInto:` gives
    Strings);
  - for a special form, Special forms;
  - for a definition in LISP, the file it was loaded from (`lib/core.lisp` gives
    Derived forms, `lib/compiler/` gives The compiler and reader), which the
    compiler records as it does the source text.
- **Public, by rule.** The public names are:
  - the primitives;
  - the special forms;
  - the forms of `lib/core.lisp`;
  - any LISP procedure that has documentation (the compiler's entry points, such
    as `compile-form` and `define-special-form`, get some).

  A test fails if a primitive or a special form has none.
- **Example** `examples/documentation.lisp`: documenting a procedure and a macro,
  and reading a built-in's documentation back.

As built:
- A primitive's documentation is a table at the end of the installer that
  defines it: `self document: anEnv category: 'Strings' with: #(name call
  description ...)`. A name in a table that is not bound is an error, so a table
  cannot drift from what it documents.
- `display`, `write` and `newline` are documented by the ports installer, which
  gives them their final, port-taking definitions.
- An old name (`hash-table-exists?`, `hash-table-size`) is a copy of the
  procedure, so it has documentation of its own.
- Names that start with `%` (`%guard` and the other machinery behind `guard`
  and `restart-case`) are not public.
- The compiler records a definition's category from the file being loaded; the
  bootstrap's stages compile each source file as if loading it, so the
  compiler's own procedures get theirs.
- `(special-form-names)` lists the special forms.

**Then the owner tags a minor release, v0.2.0, and the seed moves to it**, as it
moved to v0.1.3.

**10.1b: the derived forms.**
- `lib/core.lisp`'s forms are documented with `define-syntax`'s string.
- The completeness test covers them too.

### 10.2 The reference of the built-ins
- **`docs/builtins.md`, generated** by a cog-lisp program (`tools/builtins.lisp`)
  from the image's documentation:
  - grouped by category;
  - each entry its call form, its description, and whether it is a procedure, a
    macro or a special form.
- **Checked**: a suite regenerates it and compares the result with the
  committed file, as the bytecode corpus is checked. `COGLISP_REGENERATE=1`
  writes the new one.
- **Linked** from the README, and shipped in the release bundles under `docs/`.

### 10.3 Hover help, offline
- **`vscode/builtins.json`, generated** from the image beside the reference: each
  public name with its call form, description and kind. It is checked against
  the image like the reference.
- **The extension shows it on hover**, and offers the names for completion,
  with no image running. It reads the JSON packaged in the `.vsix`.
- **The editor's tests**: hover over a built-in in a fixture file shows its call
  form.

### 10.4 The user manual
- **`docs/manual/`, generated** by `tools/manual.lisp` from:
  - an ordered list of chapters (`docs/manual/chapters.lisp`): a title, the
    examples it is made of, and an optional prose file;
  - each example: its opening comment becomes prose, its code a listing, and its
    `.expected` the output shown.
- **Checked**: the generated manual matches the committed one. Every example
  belongs to a chapter, or is listed as left out, with a reason.
- **One book**: an index page links the chapters and the reference. Shipped in
  the bundles under `docs/`.
- **What is written by hand** is only what joins the chapters: an introduction,
  installing and running, and a short prose file where a chapter needs one.

As built (10.2 to 10.4):
- `tools/docs.lisp` builds each generated file as a string, and
  `tools/generate-docs.lisp` writes them. The suites load `tools/docs.lisp` and
  compare its strings with the committed files.
- The reference holds only the built-in categories, so neither the tool's nor a
  program's documented definitions get into it.
- The JSON is written by hand, sorted and one entry per line, so it diffs well.
  `STONJSON` writes a dictionary in hash order.
- The extension activates when a cog-lisp file opens, not only in a folder with
  the launcher, so help works in any workspace.
- **Found by the owner, 2026-11-06: no hover after installing.** There were two
  causes:
  - The `.vsix` in `vscode/` was a Nov 4 build. It is git-ignored, and nothing
    had rebuilt it since hover help landed.
  - The extension's language claimed no file extension, so `.lisp` files became
    `cog-lisp` only through this repository's `.vscode/settings.json`. Anywhere
    else (an unpacked release, say) they opened as plain text, with no help.

  Fixes:
  - The language claims `.lisp`.
  - `test/package.test.js` checks the package holds `builtins.json` and makes
    that claim.
  - `test/integration/` runs the extension in a real VS Code
    (`@vscode/test-electron`, VS Code 1.90). It hovers over `define` and
    `display` in a folder with no cog-lisp settings, in CI under `xvfb`. It
    passes 5/5; without the `.lisp` claim it fails 4 of 5.
- A manual section's title is the example's first comment line, after `--` and
  without its spec reference. A folder example shows each of its files, an
  `.args` or `.input` file is shown with it, and an example without
  `.expected` (`dual.lisp`) is shown as a library.

### 10.5 The language server (spike first)
- **The spike, before the step's detailed spec:**
  - a `lisp lsp` command reads LSP messages from stdin and answers on stdout,
    with exact byte counts, on Windows and Linux;
  - VS Code's language client (`vscode-languageclient`, MIT) talks to it;
  - hover on a built-in shows its documentation.

  If exact reads from a pipe cannot be done reliably, the fallback is a local
  socket. The decision is recorded either way.
- **Then, served by the image** (each measured and specified after the spike):
  - **hover**: documentation, the parameter list, and `procedure-source` for a
    definition in the workspace;
  - **completion**: globals, special forms and macros;
  - **go to definition**: top-level definitions in workspace files, from the
    reader's source ranges;
  - **diagnostics**: read errors and compile errors with positions (closes C-18:
    a compile error carries its form, and the reader's source map gives its
    place);
  - **expand the form at the cursor**.
- **How the server compiles without running the program:** it reads and
  compiles each top-level form. It evaluates only the forms that define syntax
  (`define-syntax`, `define-macro`), so later forms expand as they will when the
  file runs. This is a decision for the owner (§7).
- **If the spike fails**, the step ends with the spike's record, and offline
  hover (10.3) is the editor's help until a later phase.

#### The spike's record (2026-11-05): it works, on both platforms

- **The worry was unfounded.** `LispStdin` already buffers raw bytes. Its
  `nextLine` takes them only up to a line feed, and `atEnd` blocks until bytes
  arrive or input ends. So a header line reads with `nextLine`, and only the
  body needed something new: `nextBytes: n`, which waits for exactly n bytes.
  No socket was needed.
- **The server is LISP**: `lib/lsp.lisp`, run by the ordinary launcher
  (`./cog-lisp.sh lib/lsp.lisp`), so no new shell command is needed.
  - Two documented primitives frame the messages: `(read-framed-message)` and
    `(write-framed-message text)`.
  - JSON is Pharo's `STONJSON`, a message a Smalltalk `Dictionary`, reached
    through interop.
  - It answers `initialize`, keeps the open documents (full sync), answers
    `hover` from `(documentation name)`, answers an unknown request with an
    error, and ends on `shutdown` and `exit`.
- **Checked from two clients.** Messages were written 7 bytes at a time, so a
  body has no line break after it and the next message comes later:
  - a Python probe, 8/8 on Windows (through `cog-lisp.bat`) and on Linux;
  - VS Code's own message layer (`vscode-jsonrpc` 8.2.0, which
    `vscode-languageclient` is built on; `vscode/test/lsp.test.js`), 6/6 on
    both.

  | | Windows | Linux (Docker) |
  |---|---:|---:|
  | start-up, to the `initialize` answer | 673 ms | 450 ms |
  | a hover, median of 20 | 33 ms | 1 ms |

- **Found on the way**: a Windows client must start the batch file as
  `.\cog-lisp.bat` (as the extension's tasks do), and must stop the VM itself
  if it stops the server: killing `cmd` leaves the VM running.

#### 10.5 in detail (accepted 2026-11-06, with decision 4 as proposed)

**The extension starts the server and falls back.** It uses
`vscode-languageclient` 9.0.1 (MIT; its license added to the extension's
notices), packaged in the `.vsix`.
- It starts `lib/lsp.lisp` with the workspace's launcher (`cogLisp.root`, as Run
  File finds it).
- With no launcher, or with `cogLisp.languageServer` set to `false`, the
  offline hover and completion of 10.3 stay in use.
- If the server stops, the extension says so once and falls back to the offline
  help.

**What the server serves**, each with checks in `vscode/test/lsp.test.js`:
- **Hover**: a built-in's documentation, as in the spike. For a top-level
  definition in an open document or a workspace file, hover also shows its
  documentation string (if any) and its source.
- **Completion**: the global environment's documented names and the special
  forms, as 10.3 does, plus the names that workspace files define.
- **Go to definition**: for a name a workspace file defines at top level.
  - The server reads (never runs) each `.lisp` file of the workspace when
    started, and each document as it changes.
  - The reader's source ranges give each definition's place.
- **Diagnostics**, as a document opens and changes:
  - read errors, at the reader's position;
  - compile errors, at the top-level form that failed. A compile error now
    carries its form and the reader's range of it, which closes C-18; the
    innermost form's place when the reader recorded it.
  - Unbound names are not reported, since a program may define them at run time.
- **Expand the form at the cursor**: a command, *cog-lisp: Expand Macro*, served
  by a cog-lisp request (`cog-lisp/expand`). It shows `macroexpand`'s answer in a
  new editor.
- **Positions**: the protocol counts UTF-16 units, and cog-lisp strings count
  characters. The server converts both ways, so a line with characters outside
  the Basic Multilingual Plane is placed correctly; a check covers it.

**Decision 4, the owner's: does the server run a document's syntax definitions?**
- *Proposed: yes*, for `define-syntax` and `define-macro` at top level, so that
  diagnostics see the program's own macros. This accepts that a document's
  macro definitions (and, for `define-macro`, its expander's code) run inside
  the server's image.
- *Without it*, a use of the program's own macro compiles as a procedure call.
  That gives no false errors, but misses the errors inside the use.

**Checked in CI**:
- the Linux and Windows jobs, which build the image, also run
  `vscode/test/lsp.test.js`;
- the VS Code job packages the `.vsix` with the client inside it.

**Measured and recorded**: start-up, and the median hover, completion and
diagnostics times on a file the size of `lib/compiler/compiler.lisp`.

#### 10.5 as built (2026-11-06)

- **The server**, `lib/lsp.lisp`, does all of the above.
  - Open documents are fully synced. The workspace index holds the top-level
    `define`, `define-macro` and `define-syntax` forms of every `.lisp` file. It
    skips `pharo`, `node_modules`, `.vscode-test`, `.git` and `dist`.
  - Paths are compared lowercased on Windows.
- **C-18 is closed.** A `LispCompileError` carries the forms being translated,
  outermost to innermost (`forms`). The server underlines the innermost one the
  reader has a range for.
- **The extension** starts the server through `vscode-languageclient` 9.0.1,
  spawning the launcher itself:
  - Windows: `cmd /d /c .\cog-lisp.bat lib\lsp.lisp`;
  - Linux: `./cog-lisp.sh lib/lsp.lisp`.

  While the server runs, the offline hover and completion answer nothing, so
  nothing shows twice. If the server stops, the extension warns once, does not
  restart it, and the offline help answers again.
- **The `.vsix` ships 8 npm packages, all MIT or ISC.** They are listed in
  `vscode/THIRD-PARTY-NOTICES.md`, and the package test fails on an unlisted one.
- **Checks:**
  - `vscode/test/lsp.test.js`: 18/18 on Windows and on Linux (Docker).
  - `npm run test:vscode`, inside VS Code 1.90:
    - offline 5/5;
    - with the server 7/7, covering one hover per name, go to definition,
      diagnostics, completion and Expand Macro.
  - CI runs `lsp.test.js` in its Linux and Windows jobs. Its VS Code job has no
    image, so it runs only the offline pass.

  | | Windows | Linux (Docker) |
  |---|---:|---:|
  | start-up, to the `initialize` answer | 352 ms | 277 ms |
  | diagnostics, a small file | 53 ms | 10 ms |
  | diagnostics, `compiler.lisp` (1295 lines) | 374 ms | 350 ms |
  | hover, median of 15 | 51 ms | 1 ms |
  | completion, median of 15 | 42 ms | 5 ms |

  Windows' extra time per request is probably `LispStdin` polling an empty pipe
  every 20 ms, where Linux blocks in `read`. This is not measured. It is well
  under the 300 ms budget.

### 10.6 The documentation on the web (accepted 2026-11-06)

Appended by the owner on 2026-11-06. `docs/` already holds the manual and the
reference as committed, checked Markdown. This step publishes them on GitHub
Pages, so a reader needs neither a checkout nor a bundle. The owner chose:
- GitHub Pages built by Jekyll;
- a rebuild on every tagged release (decision 6);
- no wiki (decision 7).

**Where we start (checked 2026-11-06):**
- The repository is public.
- GitHub Pages is not enabled: the Pages API answers 404.
- The wiki is turned off.
- `docs/` links only within itself: chapter to chapter, to `README.md`, to
  `../builtins.md`, and to the reference's section anchors.
- The generated pages contain no `{{` or `{%`.

**The site is GitHub's own Jekyll build of `docs/`.** There is no converter of
our own. It is the `github-pages` gem that `actions/jekyll-build-pages` runs:
- `jekyll-relative-links` turns links to `.md` files into links to pages;
- `jekyll-readme-index` makes `manual/README.md` the `/manual/` page;
- the default theme (Primer) looks like GitHub's own Markdown view.

**New files:**
- `docs/index.md`, the home page. `tools/generate-docs.lisp` generates it from
  the introduction's opening paragraph, with links to the manual, the reference,
  the releases and the repository. The 10.4 suite checks it like the manual's
  pages.
- `docs/_config.yml`, written by hand:
  - the title and description;
  - `baseurl: /cog-lisp`, set here so the links do not depend on what the
    Pages API answers at build time;
  - `exclude` for the manual's sources (`chapters.lisp`, `introduction.md`).
- `docs/_layouts/default.html`: the theme's layout, with its *Improve this page*
  footer replaced. That footer links to editing the page on GitHub, but the
  pages are generated, so an edit would be overwritten. The new footer names
  the release the site documents (`cog_lisp_version`) and links to the releases
  and the source.
- `.github/actions/build-site`, an action that CI and the release share. It:
  - adds the version, when given, as `cog_lisp_version` in the build's copy of
    `_config.yml` (never committed), so every page's footer names it;
  - runs `actions/jekyll-build-pages` on `docs/`;
  - runs `tools/check-site.js`.
- `tools/check-site.js` (Node, no dependencies). It checks that:
  - every link between the built pages, and every anchor, resolves;
  - the home page, the manual's contents, each of its chapters and the reference
    are present.
- `.github/workflows/pages.yml`:
  - It builds the site with the shared action, uploads it
    (`actions/upload-pages-artifact`) and deploys it (`actions/deploy-pages`).
  - After deployment it fetches the home page, a chapter and the reference from
    the published URL.
  - Its permissions are only `pages: write` and `id-token: write`.
  - It runs when the release calls it, or by hand with a tag to publish.

**When it publishes (decision 6):** each tagged release.
- `release.yml` calls `pages.yml` after the release itself is published, with
  the tag's version. The site then documents the release people download, and
  says which one it is.
- A pre-release (`v1.2.3-rc1`) does not change the site.
- The dry run publishes nothing.

**CI builds the site on every push, without publishing it** (a `site` job using
the shared action). A change that breaks the site fails CI before a release can
publish it.

**Liquid:** Jekyll runs every page through Liquid, and GitHub's Jekyll (3.x)
cannot turn that off for one page. The 10.4 suite fails if a page in `docs/`
contains `{{` or `{%`. The fix then is for the generator to wrap that page in
`{% raw %}`.

**What the owner does once.** These are repository settings, so the owner
changes them, not a workflow or Claude:
- Settings → Pages → Source: *GitHub Actions*.
- Settings → Environments → `github-pages` → deployment branches and tags: add
  the tag rule `v*`. The environment allows only the default branch at first,
  and the release deploys from its tag.
- The repository's website: `https://treytomes.github.io/cog-lisp/`.

The README and `release/INSTALL.md` link to the site.

**No wiki (decision 7).** A wiki would be a second copy of generated pages that
can be edited in the browser, and the next release would overwrite any edit.

#### 10.6 as built (2026-11-06)

- **The site was built locally** with the action's own image
  (`ghcr.io/actions/jekyll-build-pages:v1.0.13`: Jekyll 3.10, github-pages 232).
  Run without a token, it builds 17 pages in about 3 s.
  - `tools/check-site.js` passes 4/4: 110 links within the site, and 19 section
    anchors in the reference.
  - A broken link, a missing anchor and a missing chapter each made it fail.
  - Built locally, with no token, the build warns that GitHub's metadata is
    missing; CI passes the workflow's token.
- **What Jekyll does with the Markdown as committed:**
  - links to `.md` files become `/cog-lisp/<page>.html`;
  - `manual/README.md` becomes `/manual/`;
  - each page's title comes from its first heading;
  - the reference's section ids match its own links.
  - The Markdown originals are copied beside the pages, which does no harm.
- **The theme's favicon link is commented out** in its layout, so the missing
  icon is not a broken link.

#### A fix to 10.5 found on the way (2026-11-06): the server runs on a copy of the image

- **The bug.** Any two VMs on one image collide: the first holds the
  `.changes` file open for writing, and the second fails at start-up with
  "Cannot open non source file". The extension started the server on
  `pharo/cog-lisp.image`. So while VS Code was open on a checkout, every other
  cog-lisp run there failed: *Run File*, the REPL, the terminal, the docs
  generator, the suites. The owner's own window showed it on the day 10.5
  shipped.
- **The fix.** The extension copies the image and its changes to a fresh
  `cog-lisp-server-*` folder in the system's temporary folder, and starts the
  server there through `COGLISP_IMAGE`.
  - A change to `pharo/cog-lisp.image` (a rebuild) restarts the server on a new
    copy.
  - Old copies are removed: on Windows the VM can hold its files for a moment
    after it exits, so removal is retried. A copy left behind by a window that
    has closed (`owner.pid`) is removed at the next start.
  - `vscode/test/lsp.test.js` runs its server on a copy too.
- **Checked inside VS Code** (the server pass is now 10/10):
  - the server runs on a copy;
  - a program runs from the same checkout while the server runs;
  - touching the image restarts the server on a new copy and removes the old
    one.

  `COGLISP_TEST_ROOT` gives that pass another checkout. Here it ran on a
  throwaway copy of this checkout, because the owner's window, still on the old
  extension, held this one's image.
- **Two VMs still collide** when both run on `pharo/cog-lisp.image`: for
  example, a long-running REPL and *Run File*. That predates Phase 10 and is
  left as it is.

### 10.7 A skill for agents (accepted 2026-11-06)

Appended by the owner on 2026-11-06. The owner is testing how well Ministral 3
3B (a reasoning model) works with cog-lisp, in Bionic (LM Studio's agent app).
A **skill** gives an agent cog-lisp's working knowledge when a task needs it.
It ships with each release.

**What a skill is in Bionic** (from Bionic's own bundled `skill-management`
skill, read 2026-11-06):
- **The files.** A skill is a folder named after the skill, holding `SKILL.md`:
  YAML front matter, then Markdown instructions.
  - `name` (required) is kebab-case, 1 to 63 characters, and must match the
    folder's name.
  - `display-name` is optional.
  - `description` is required.
  - Other fields are ignored.
- **How it is used.** The `description` goes into the system prompt of every
  agent that has the skill. The agent reads `SKILL.md` itself when the
  description matches the task, or the user types `@cog-lisp`. The agent gets
  read access to the whole folder, so supporting files can sit beside
  `SKILL.md`.
- **Where it lives.**
  - A global skill: `~/.lmstudio/skills/<name>/`, installed by Bionic's agent
    (it asks the user to approve).
  - A project skill: `<project>/.agents/skills/<name>/`, always active in that
    project.
- **The same `SKILL.md` format** (front matter with `name` and `description`) is
  the common agent-skill format other agent tools read too. Only Bionic is a
  target here.

**Written for a small model.** A 3B model has little room for context and copies
examples literally. So the skill is short, says exactly what to do, and every
example in it is checked to run as shown.

**The skill: `.agents/skills/cog-lisp/`**, committed. Placed there, it is a
*project* skill wherever the folder is a Bionic project: this checkout, or an
unpacked release.
- **`SKILL.md`**, generated by `tools/generate-docs.lisp` (like the manual), under
  10 KB (about 2,500 tokens). Its sources, in `docs/skill/`:
  - **`skill.md`**, hand-written: the prose, with a marker where each example
    goes.
    - The front matter: `name: cog-lisp`, `display-name: cog-lisp`, and a
      `description` under 150 characters saying when to use it ("writing,
      running or fixing cog-lisp programs (.lisp files run by cog-lisp.sh or
      cog-lisp.bat)").
    - **How to run a program**, per platform, and what comes back: the exit
      code, and errors as `path:line:col: error: message`.
    - **The loop**: write a `.lisp` file, run it, read the error, fix it, run it
      again; ask the image with `(documentation 'name)`.
    - **What cog-lisp is**: Scheme (R7RS), not Common Lisp.
    - **The traps** a model trained on other Lisps falls into, each with the
      right way. These are candidates: each stays only if an example shows it
      true of cog-lisp today.
      - `define`, not `defun`;
      - no `list-ref`;
      - `for-each` takes one list;
      - `display` versus `write`;
      - `#t` and `#f`;
      - string literals cannot be changed;
      - `[receiver message: argument]` for Smalltalk;
      - `load` is relative to the loading file.
    - **Where to look next**: `reference.md` beside it, and in a checkout or a
      bundle `docs/manual/` and `examples/`.
  - **`examples/*.lisp`**, about 10 short programs, each with its `.expected`
    output. They run like the repository's examples (every suite run), and the
    generator puts each one's code and output into `SKILL.md`. So the skill's
    examples are checked programs, not text that has to be kept right by hand.
- **`reference.md`**, generated by `tools/generate-docs.lisp` from the image's
  documentation:
  - every built-in's name and call form, grouped as in `docs/builtins.md`, with
    a one-line description;
  - terse, so a small model can read the part it needs. The full reference is
    38 KB, about 10,000 tokens.
- Both generated files are committed (decision 2), like the rest of the
  documentation.
- `docs/_config.yml` excludes `skill/`, so the website does not publish the
  sources as pages. The source's front matter would otherwise make Jekyll treat
  it as a page of its own.

**Checks** (a new LISP suite, `tests/lisp/phase-10.7-skill.lisp`):
- `SKILL.md` and `reference.md` are what the generator writes;
- the front matter parses, and `name` matches the folder and Bionic's rule;
- the `description` is under 150 characters;
- `SKILL.md` stays under its budget, 10 KB;
- every example in `docs/skill/examples/` runs with its `.expected` output, and
  each is in `SKILL.md`.

**Rebuilt at release time**, like the site:
- The release regenerates the skill from the image it has just built.
- It fails if the result differs from the committed copy, so a release cannot
  ship a skill that does not match its own image.
- It adds the version to its copy's front matter (`version: X.Y.Z`; Bionic
  ignores fields it does not know, and the agent sees it).
- It zips that copy as `cog-lisp-skill-VERSION.zip` and attaches it to the
  release.
- The bundles carry the same stamped copy.

**In the release:**
- The bundles carry `.agents/skills/cog-lisp/`, and `release/smoke-test.sh`
  checks it is there and stamped with the bundle's version.
- `release/INSTALL.md` and the release notes explain the two ways to use it:
  - open the unpacked folder as a Bionic project (the skill is then active);
  - or install `cog-lisp-skill-VERSION.zip` (or the folder) through Bionic's
    agent, for use in every project.

**Measuring it (decision 8).** Whether the skill helps is a measurement, not an
opinion.
- `tools/skill-eval.js` runs a fixed set of about 10 small tasks
  through LM Studio's local server (OpenAI-compatible, `localhost:1234`), with
  and without the skill.
  - The tasks include: reverse a list, count words, a hash-table histogram, fix
    a given error, call a Smalltalk method, write a macro.
  - It runs each answer with cog-lisp, compares the output, and records the
    pass rates, for the model the owner has loaded.
- It needs the owner's LM Studio with the model loaded, so it is run by hand,
  not in CI.
- The first results (Ministral 3 8B, on the owner's `rojo` machine) are recorded here, and the skill is
  revised while they show a trap it misses.

**Where it ships (decision 9):** as above: a project skill in the checkout and
the bundles, plus the zip.

#### 10.7 as built (2026-11-06)

- **The traps were checked on the image first**, and the list changed:
  - **True, and kept:** `defun` and `nil` are unbound; `map` takes one list, as
    `for-each` does; changing a string literal fails ("string is immutable (a
    literal); copy it first").
  - **Found while checking:**
    - `format` is unbound;
    - `'()` counts as true;
    - a quoted selector in `send` fails;
    - `filter`, `remove`, `reduce`, `fold`, `iota`, `sort`, `list-tail`,
      `last`, `call/cc` and `define-record-type` do not exist.

    A model reaches for these first, so the helpers example defines `filter`,
    `fold`, `iota`, `list-ref` and `sort`.
  - **Not traps:** `load` is relative to the loading file (checked from another
    directory), and `display` and `write` behave as in Scheme (shown in the
    first example).
  - **Useful to an agent:** `(documentation 'name)` answers `#f` for a name
    that does not exist, so the skill tells the agent to check names that way.
- **The traps are data**, `docs/skill/traps.lisp`: each one's title, wrong code,
  outcome and right code. The suite runs every wrong piece of code and checks
  its error message (or what it prints), and runs every right one. The skill
  quotes each error in full, as the model will see it.
  - Changing two claims made three checks fail (the two claims, and the
    committed copy).
- **10 examples** in `docs/skill/examples/`, among them one that fails, to show
  an error line (`an-error.lisp:4:1: error: car: not a pair: 5`). It also shows
  that the position is the top-level form that was running, not the `car`
  inside the procedure. The runner suite runs them with their `.expected`,
  `.exitcode` and `.stderr` files, on both platforms.
- **The budget is 10 KB, not 150 lines.** Ten examples in code blocks take about
  360 lines, but only 9.4 KB, about 2,500 tokens: what a model pays for is text,
  not lines.
  - `reference.md` is 26.6 KB, against `docs/builtins.md`'s 38 KB. It gives a
    line per built-in: its call form, then its whole description. Cutting each
    description to its first sentence saved only 4 KB, and lost what mattered
    (`lambda` became "A procedure.").
- **Generated by `tools/generate-docs.lisp`**, which now creates the folders it
  writes into.
- **The release** regenerates every documentation file from the image it has
  just built, and fails if any differs from the committed copy. Then
  `release/package.sh`:
  - copies the skill into each bundle, adding `version:` after `name:` in its
    front matter;
  - zips that copy as `cog-lisp-skill-VERSION.zip`.

  `release/smoke-test.sh` checks the bundle's skill and its version.
- **`tools/skill-eval.js`** and `tools/skill-eval-tasks.json`: 10 tasks. Most
  aim at a trap: the second element of a list, keeping the odd numbers,
  sorting, joining strings, a Smalltalk message, fixing a `defun`.
  - Each task has its own solution, and `--dry-run` runs those: 10/10.
  - It was also run against a stand-in server: the reasoning block was
    dropped, the error line was fed back, and the answer passed on its second
    attempt.
  - Programs run on a copy of the image.
- **The model:** the owner chose Ministral 3 8B (reasoning), served from the
  `rojo` desktop (CUDA) through Bionic's private link, in place of the 3B model
  first tried. The results below come from that model.

#### 10.7: the first results (2026-11-06)

`ministral-3-8b-reasoning-2512` (Q4_K_M, loaded with a 16,384-token context),
through the server at `http://localhost:1235/v1`. It ran 10 tasks, with up to
2 attempts each; after a wrong answer, the model was shown what happened.

| Run | Skill | Without the skill: first attempt / within 2 | With the skill: first attempt / within 2 |
|---|---|---:|---:|
| 1, 1 run per task | as committed | 0/10, 2/10 | 6/10, 6/10 |
| 2, 3 runs per task | + 3 traps, `iota` with a start | 1/30, 7/30 | 14/30, 16/30 |
| 3, 3 runs per task | + the rule first, `first`/`second`/`last` named | 0/30, 4/30 | **17/30, 20/30** |
| 4, 3 runs per task (2026-11-09) | `format` built in: its trap became an example; two sentences shortened | 0/30, 7/30 | 14/30, 15/30 |
| 5, 3 runs per task (2026-11-09) | list built-ins (specs/22-lisp-expert-libraries.md): the helpers example became `list-tools`; the `second` trap names `cadr` and `list-ref` | 1/30, 9/30 | **17/30, 20/30** |

- **Without the skill** the model writes some other Lisp:
  - names that do not exist: `print`, `second`, `split`, `defun`, `format`;
  - Smalltalk syntax it cannot know.
  It almost never passes on the first attempt.
- **What each revision fixed**, from the failures of the run before it:
  - run 2:
    - a value alone prints nothing in a program;
    - a list written as code is a call ("object is not applicable: 1");
    - `cons` in a loop builds the list backwards;
    - `iota` takes an optional start, as most Schemes' does;
  - run 3:
    - the rule that the answer is a program that prints its result, moved to
      the top of the skill with an example;
    - `first`, `second` and `last` named among the missing names.
- **What still fails, with the skill:**
  - **The model writes the result instead of a program** (`(1 4 9 16 25)`,
    `red,green,blue`, `20`) in 5 of the 10 failures of run 3. `second-element`
    never passed.
    - Part of this may come from the harness: it asks for one code block, and
      the task shows the expected output.
    - An agent in Bionic writes a file and runs it, so this is the first thing
      to watch there.
  - Two answers used `iota` without defining it, though the skill says to copy
    the helpers.
  - The remaining failures are the model's own bugs.
- **The context fills up.** One request in a third attempt at run 3 was
  refused: "Context size has been exceeded". The skill costs 3,362 prompt
  tokens of the 16,384 loaded, and a reasoning model's answers are long.
  - `tools/skill-eval.js` now caps each answer (`--max-tokens`, 8192), records
    a refused request as a failed attempt, and saves its results as it goes.
  - For agent work, load the model with a larger context: it supports 262,144.
- **Run 4** came after `format` was built in (specs/19-format.md). It failed the
  same ways as run 3: the result instead of a program, `second`, an undefined
  `iota`, and the model's own bugs. None of its answers used `format`, which no
  task needs, and none of its failures came from the change. Its lower count
  is read as sampling: runs 2 and 3 differed by as much.
- **Run 5** came after R7RS's and SRFI 1's list procedures were built in.
  `second-element`, which no earlier run passed, passed all 3 times. The other
  failures are the old ones: "object is not applicable: 1" (all 3
  `sort-numbers` answers, and one each of `squares` and `keep-odd`) and
  "unbound variable: red" (`join-with-commas`) are the result written instead of
  a program, and `fix-a-program` twice printed nothing. The answers were not
  saved (`--out`), so these readings come from the errors alone.
- Sampling makes these numbers noisy (3 runs per task, temperature 0.2), so a
  difference of two or three tasks is not a finding.

## 5. Acceptance criteria

- AC-1 (10.1) Every primitive, special form and `lib/core.lisp` form has
  documentation, and a test fails when one does not. `(documentation 'name)`
  answers it, and a documented `define`, `define-macro` and `define-syntax` keep
  their strings. `lib/core.lisp` uses `define-syntax`'s string, compiled by the
  v0.2.0 seed. The example runs.
- AC-2 (10.2) `docs/builtins.md` is generated from the image, matches it in a
  suite, and ships in the bundles.
- AC-3 (10.3) The extension shows hover help and completion for every public
  name, from generated data checked against the image, with no image running.
- AC-4 (10.4) `docs/manual/` is generated from the examples and the chapter
  list, matches them in a suite, accounts for every example, and ships in the
  bundles.
- AC-5 (10.5) Either the image serves hover, completion, go to definition,
  diagnostics with positions and macro expansion to VS Code on Windows and
  Linux, with tests on both; or the spike's record says why not and what was
  tried.
- AC-6 (10.6) CI builds the site from `docs/` on every push and checks every
  link, anchor and page in it. A release publishes the site to GitHub Pages, and
  a check after deployment fetches the home page, a manual chapter and the
  reference from the published URL. A page in `docs/` holding Liquid syntax
  fails a suite.
- AC-7 (10.7) `.agents/skills/cog-lisp/` is a valid Bionic skill, generated
  from `docs/skill/` and the image: its front matter passes Bionic's rules, its
  examples run with their outputs, and both files match the generator, all
  checked by a suite. A release regenerates it from its own image, stamps the
  version, puts it in the bundles and attaches it as a zip. The
  evaluation's first results for Ministral 3 8B, with and without the skill,
  are recorded.

## 6. Examples

| Example | Proves |
|---|---|
| `examples/documentation.lisp` | a documented procedure, and a built-in's documentation read back |
| (the manual) | every example, as a chapter's worked and checked code |

## 7. Decisions (owner, 2026-11-05)

1. **Macros are documented by a string in `define-syntax`**, not a separate
   call. A minor release (v0.2.0) gives the seed that compiles it (10.1). Special
   forms use a string in `define-special-form`, which needs no release.
2. **Every generated file is committed** and checked against the image by a
   suite: the reference, the editor's data, the manual.
3. **The manual is Markdown.**
4. **The language server evaluates a document's top-level syntax definitions**
   (`define-syntax`, `define-macro`), so later forms expand as they will when
   the file runs. This accepts that a document's macros run inside the server's
   image. (Proposed with 10.5's detailed spec; accepted 2026-11-06.)
5. **R-17 stays with the REPL**: the server reads whole documents. It is fixed
   when a large form sent to the REPL makes it matter.
6. **The site is GitHub Pages, built by Jekyll, and rebuilt on every tagged
   release** (2026-11-06), so it matches the release people download.
7. **No wiki** (2026-11-06).
8. **The skill is measured** by `tools/skill-eval.js` through LM Studio's local
   server, run by hand, with its results recorded (2026-11-06).
9. **The skill ships as a project skill** in the checkout and the bundles, plus
   a zip attached to each release, rebuilt by each release from its own image
   (2026-11-06).

## 8. Risks

- **About 300 descriptions to write** at once. They are mechanical and each is
  short. The test that fails on a missing one keeps it from drifting, and
  `docs/builtins.md` shows the whole set for review.
- **Exact byte reads from stdin** (10.5): the stdio machinery was built for lines,
  and the Windows pipe and console paths differ. Hence the spike, and the socket
  fallback.
- **A new runtime dependency for the extension** (the language client): packaged
  into the `.vsix`, and its license added to the notices.
- **GitHub's Jekyll is not GitHub's Markdown view** (10.6). The two can make
  different heading ids, and Liquid reads `{{` and `{%`. Building the site in CI
  and checking its links and anchors catches the first; the suite check catches
  the second.
- **The runtime moves to LISP in Phase 11.1**: primitive documentation written in
  Smalltalk now must move with it. Keeping it beside each definition makes that
  a move, not a rewrite.

## 9. Step status

| Step | Status |
|---|---|
| 10.1 Documentation in the image | done: the machinery; 249 primitives, 16 special forms and the compiler's entry points documented (10.1a, 2026-11-05); the 14 derived forms, by define-syntax's string, compiled by the v0.2.0 seed (10.1b, 2026-11-06) |
| 10.2 The reference of the built-ins | done (2026-11-05): docs/builtins.md, 283 entries in 17 sections, checked against the image |
| 10.3 Hover help, offline | done (2026-11-05): hover and completion from vscode/builtins.json, checked against the image |
| 10.4 The user manual | done (2026-11-05): docs/manual/, 14 chapters from all 36 examples |
| 10.5 The language server | done (2026-11-06): hover, completion, go to definition, diagnostics (C-18 closed) and Expand Macro, served by the image to VS Code on Windows and Linux |
| 10.6 The documentation on the web | done (2026-11-06): GitHub Pages from docs/, built and checked by CI, published by each release (first publish awaits the owner's Pages settings and the next release) |
| 10.7 A skill for agents | done (2026-11-06): .agents/skills/cog-lisp/, generated and checked, rebuilt by each release; Ministral 3 8B passes 17/30 tasks on the first attempt with it, 0/30 without |
