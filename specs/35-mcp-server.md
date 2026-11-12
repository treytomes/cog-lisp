# Agents' tools: an MCP server, run by the image

| | |
|---|---|
| **Status** | Accepted (2026-11-12), after the owner's answers to §8, a review (§9), and the owner's additions (§9, items 13 to 17) |
| **Asked for by** | The owner (2026-11-12), after configuring the language server for OpenCode and asking whether Bionic (LM Studio's agent) could use it: "An ideal place to host a language server MCP might be the `cog-lisp` image itself. Let's talk through that idea as well." Then: "write a spec document for building the MCP server." And on scope: "Knowing how to build the MCP server in Lisp will be a good step towards some other open tasks. Simply running it without hosting it is fine for this stage." |
| **Relates to** | `specs/16-phase-10-documentation-and-editor.md` steps 10.5 (the language server, `editor-services`, the extension) and 10.7 (the agent skill), `specs/28-versioning.md` (the image's version, which `serverInfo` reports), `specs/21-https-and-json.md` (`json-read`/`json-write`), `specs/34-morphic-ide.md` (`editor-services`, the image's own editor, the development image), `specs/31-vsix-bundle.md` (the extension's bundle), `specs/17-startup-anywhere.md` (two VMs on one image) |

## 1. Where we start (measured 2026-11-12)

- **The image already serves a protocol.** `lib/lsp.lisp` speaks the Language Server
  Protocol on standard input and output, and its header says what it is: "this file
  is the protocol, its JSON, its framing, and its positions". What it knows about
  source comes from `lib/editor-services.lisp`, which the Morphic IDE asks too
  (`specs/34-morphic-ide.md` R-29). There are already two adapters over one service
  layer; an MCP server would be the third.
- **What `editor-services` answers:** `editor-check path text` (problems as
  `#(severity start end message)`), `editor-definitions` and
  `editor-definitions-named`, `editor-definitions-for path name` (a name as the
  file at `path` means it), `editor-completions path` (every name the file at
  `path` can use: no offset, no prefix), `editor-macro-call-at text offset`,
  `editor-symbol-at text offset`, `editor-resolve path name`, the index
  (`editor-index-folder!`, `editor-index-file!`, `editor-index-text! path text`),
  and `editor-tokens`. `lib/format-source.lisp` answers `format-source` (R-4 of
  `specs/26-formatter.md`).
  - Several answers take a **path, not text**: the path names the file's unit, and
    so its imports, and its entry in the index. The language server therefore
    indexes an open document's text under its path (`lsp-index-text!`) before it
    asks. An MCP server must do the same with text an agent sends (R-8).
  - The language server's hover is two answers, not one
    (`lib/lsp.lisp:237-253`): a definition in the workspace when
    `editor-definitions-for` finds one, else the built-in's `documentation`
    through `editor-resolve`.
- **The image has the pieces an MCP server needs:**
  - `(read-line)` reads the next line from stdin without its line break
    (`docs/builtins.md`); `lib/console.lisp:1116` uses it over ports.
  - `json-read` and `json-write` are LISP procedures over hash tables and vectors,
    with `null` as `()` (`specs/21-https-and-json.md`). **`json-write` writes to
    the current output port** (`lib/json.lisp:108`); it does not answer a string.
  - `display`, `write-string`, `write` and `newline` flush after writing
    (`src/coglisp-runtime.st:732-741`), so a reply leaves the image before the
    next line is read. No new built-in is needed;
  - compiler warnings go to stderr, not stdout (`coglisp-compiler.st:664`).
- **The framing built-ins are LSP-shaped, not MCP-shaped.**
  `read-framed-message`/`write-framed-message` use a `Content-Length` header
  (`src/coglisp-runtime.st:1162-1178`). MCP's stdio transport is newline-delimited
  JSON, in both revisions, so `lib/mcp.lisp` reads and writes lines, not frames.
- **The cost of starting an image** (this machine, 2026-11-12, a private copy):
  `initialize` answered in **~1.0 s**; the first request that needs the workspace
  index answered in **~1.5 s**. A host starts one server per session and keeps it,
  so this is paid once.
- **A long-lived VM on the checkout's image blocks the build.** Two VMs may run
  one image (`specs/17-startup-anywhere.md`), but `build-image` cannot swap in a
  new image while another process holds `pharo/cog-lisp.changes` on Windows: it
  exits 1 and replaces nothing, and `tests/run-all` builds first. The extension
  already runs the language server on a private copy of the image for this reason
  (`vscode/src/extension.js:333-337`, `copyServerImage`). An MCP server lives as
  long as its host's window, so it needs the same treatment, for every host
  (R-19).
- **Node will not spawn a batch file without a shell.** The extension starts the
  language server as `cmd.exe /d /c .\cog-lisp.bat …` (`extension.js:397-399`),
  never the `.bat` itself; a host that spawns a `.bat` directly may fail the same
  way. Every Windows configuration in this spec goes through `cmd.exe /d /c`.
- **There are two protocol revisions to speak.** `2025-11-25` is the last of the
  session-based revisions, opened by an `initialize` handshake. `2026-07-28` is
  the current stable one: stateless, with the version, identity and capabilities
  of every request in `_meta`. It names the shape this spec needs: a **dual-era**
  server, one that "MAY serve both eras concurrently on the same endpoint or
  process", choosing "from how the client opens" (its Versioning page, §Backward
  Compatibility). The transport for both is newline-delimited JSON on stdin and
  stdout.
- **Who wants it:**
  - **Bionic 1.1.8+10** is an MCP host: local servers as `command`/`args`/`env`,
    remote as `url`/`headers`, configured in `%USERPROFILE%\.lmstudio\mcp.json` in
    Cursor's notation (`mcpServers`). Its bundle carries the protocol revisions
    `2024-11-05`, `2025-03-26`, `2025-06-18` and `2025-11-25`, and no later one, so
    it opens with `initialize`. It has no language-server client of its own. It is
    also where the agent skill is measured (`tools/skill-eval.js`, a small model
    behind LM Studio's server).
  - **VS Code 1.145.2** is an MCP host as well: `.vscode/mcp.json` (key `servers`)
    for users, and `contributes.mcpServerDefinitionProviders` for extensions
    (R-17). Its MCP client knows `2025-11-25` and later revisions, so it may probe
    with `server/discover` before opening with `initialize` — which is the second
    reason to be dual-era, not the first. The servers an extension provides reach
    VS Code's own agent, not other agents running in the window.
  - **Claude Code**, which the owner works with in this repository and in
    `~/projects/lisp-expert`, reads its project's MCP servers from `.mcp.json` at
    the project's root (key `mcpServers`), not from VS Code's providers. So the
    extension alone gives it nothing (R-21).
- **What we are not doing.** A generic bridge from MCP to LSP (such as
  `mcp-language-server`) would work today without touching this repository, but it
  is a translation layer that must relearn what `lsp.lisp` already knows: that
  diagnostics are pushed only on `didOpen`/`didChange`, that `cog-lisp/expand` is
  not a standard method, and how offsets become UTF-16 positions. The owner
  declined it (2026-11-12).

## 2. The approach

**`lib/mcp.lisp` is a third adapter over `editor-services`**, run by the image as
`cog-lisp.bat lib\mcp.lisp <folder>` (`cog-lisp.sh lib/mcp.lisp <folder>`),
speaking MCP's stdio transport. It holds no knowledge of checks, definitions,
completions, macros or formatting of its own: it asks the same procedures the
language server and the Morphic IDE ask.

```
              editor-services.lisp  (checks, definitions, completions, index)
                 ▲           ▲            ▲
        lsp.lisp │   ide.lisp│            │ mcp.lisp
                 │           │            │
              editors    the image    agents (VS Code, Claude Code, Bionic, …)
```

`lib/lsp.lisp` is untouched. Editors keep push diagnostics and squiggles; agents
get pull tools. Two protocols, one service layer, no bridge anywhere.

**Run, not hosted (owner, 2026-11-12).** Each host starts its own server process
on a throwaway copy of the image, and the process ends with the host's session.
No image keeps a server running for others to connect to; that is later work
(§10, L-35.1), and this step is built so that work reuses it (R-13, R-20).

**One launcher, every host.** `mcp-server.bat` / `mcp-server.sh` (R-19) copies
the image, runs the server on the copy, and removes the copy at exit, so no host
holds the checkout's image. Every host runs it:

| Host | How it gets the server | Configured by |
|---|---|---|
| VS Code (its own agent) | the extension's provider, automatically (R-17) | the extension |
| Claude Code, in `cog-lisp` and in `lisp-expert` | each repository's committed `.mcp.json` (R-21) | the repository |
| Bionic, and any other host | the user's own configuration, as `README.md` and `docs/mcp.md` show (R-16) | the user |

**Both revisions, one process, one tool table.** The server is dual-era, as
`2026-07-28` defines it. It selects from the client's opening message:

| The client opens with | Era | What answers |
|---|---|---|
| `initialize` | legacy, `2025-11-25` | the handshake of R-4; legacy semantics for that process |
| `server/discover` | modern, `2026-07-28` | discovery (R-5); the next requests are stateless |
| any request carrying `_meta.io.modelcontextprotocol/protocolVersion` | modern | answered statelessly (R-5) |
| anything else | legacy | answered leniently, as `lsp-serve` answers a request before `initialize` |

The era changes the envelope, never the tool: the six handlers of R-7 answer both.
The modern envelope adds `resultType`, per-result `_meta` and the cache hints; the
legacy one has none of them (R-10). One process can serve a legacy session and
modern requests at the same time, and the revision requires nothing else of a
dual-era server.

**The protocol is separate from the transport (R-20).** One procedure takes a
message and answers its reply; the stdio loop only reads lines, calls it, and
writes what it answers. A later transport calls the same procedure.

**The workspace is configuration, in both eras.** The folder to index is the
argument after the script (R-6), the same for a legacy session and a modern
request. The server never asks the client for roots, so neither era's rules on
roots (MCP's `roots/list`, and whatever later revisions say of it) affect it.

**The catalog is the language server's, one for one.** The owner asked for the
MCP server to expose everything the LSP provides (decision 1): the same six
answers, from the same service layer. Nothing is added and nothing is left out.

**One release (decision 6), two steps (§5).**

**Not chosen:**
- **An MCP-to-LSP bridge** (the owner's decision, §1).
- **A server hosted by a running image, behind HTTP**, for this step. It needs a
  port, a lifecycle and evaluator tools to be worth having; it is deferred, not
  dropped (§10, L-35.1).
- **A Node MCP server shipped with the extension.** It would be a second runtime
  to install, a second copy of the language's knowledge, and a version that can
  drift from the image.
- **Evaluator tools** (`eval`, `run-file`). They are not part of what the language
  server provides, so they are not part of this catalog (decision 1); L-35.1
  takes them up.
- **Roots from the client** (§9, item 1). MCP's `initialize` carries no folders;
  roots come only from a `roots/list` request the server sends the client, which
  a read-a-line, answer-a-line loop cannot make. The folder argument serves every
  host.
- **A user-scope Claude Code server** (`claude mcp add --scope user`). It would
  start in every project on the machine, cog-lisp or not; a project's
  `.mcp.json` starts it only where it is useful (R-21).

## 3. Requirements

- **R-1. A third adapter, a second protocol.** `lib/mcp.lisp`, which requires
  `editor-services` and `format-source` and asks them everything. It is a plain
  script like `lsp.lisp`: no image rebuild, and `lib/lsp.lisp` does not change.
  It runs until standard input ends.
- **R-2. The transport.** One JSON-RPC 2.0 message per line, UTF-8, no line break
  inside a message. Read with `(read-line)`; write with `(json-write message)`
  then `(newline)` (`json-write` writes to the current output; `newline` flushes).
  A trailing `\r` on a line read from a host that writes CRLF is stripped, and
  nothing else is. **Standard output carries the protocol and nothing else:**
  every warning, error and log line goes to standard error.
- **R-3. Dual-era, selected by the opening message.** The rules of the table in
  §2, in this order:
  1. a message whose `method` is `initialize` selects the legacy era for that
     process (R-4);
  2. one whose `method` is `server/discover`, or any request carrying
     `_meta.io.modelcontextprotocol/protocolVersion`, is answered in the modern
     era (R-5);
  3. any other request before either is answered leniently, in the legacy era.

  The era is selected from how a client opens, not negotiated: an `initialize`
  scopes legacy semantics to the process, while a request carrying modern `_meta`
  is answered statelessly whatever came before it. One process may therefore serve
  both eras, as `2026-07-28` allows.
- **R-4. The legacy handshake.** `initialize` answers:
  - `protocolVersion`: the client's, when it is `2025-11-25`, `2025-06-18`,
    `2025-03-26` or `2024-11-05`; ours (`2025-11-25`) otherwise;
  - `capabilities`: `{"tools": {}}` (no resources, prompts, sampling or logging);
  - `serverInfo`: `{"name": "cog-lisp", "version": <the image's version>}`, as the
    language server reports it (`specs/28-versioning.md` R-11);
  - `instructions`: one sentence naming what the tools answer, so the model knows
    when to reach for them.

  `initialize`'s params are read only for `protocolVersion`; the client's
  capabilities (`roots` among them) change nothing.
  `notifications/initialized` is accepted and ignored; `ping` answers `{}`. Any
  other notification is ignored, as `lsp-serve` ignores one.
- **R-5. The modern era, statelessly.** No handshake. A request is answered from
  its own contents and the server's configuration:
  - `_meta.io.modelcontextprotocol/protocolVersion` is required, and `2026-07-28`
    is the only revision this era answers: a request naming any other revision is
    refused with `-32022`, `data.supported` naming `["2026-07-28", "2025-11-25"]`
    (`2025-11-25` is reachable through `initialize`, R-4) and `data.requested`
    naming the client's.
  - `_meta.io.modelcontextprotocol/clientCapabilities` is required; without it the
    request is `-32602`, as the revision says.
  - `server/discover` answers `supportedVersions: ["2026-07-28"]` — what a modern
    client can go on using — plus `capabilities` (`{"tools": {}}`), the same
    `instructions` sentence, `_meta.io.modelcontextprotocol/serverInfo` and the
    cache hints of R-10.
  - **What "stateless" means here.** No answer depends on which requests came
    before it, in either era. The one thing kept between requests is the
    workspace index, a cache of the folder named in configuration (R-6) and the
    files on disk; R-8 says how a request's own text is used without changing it.
- **R-6. The workspace folder.** The folder to index is the optional argument
  after the script (`cog-lisp lib\mcp.lisp <folder>`), in both eras. Without the
  argument there is **no** workspace: the server does not fall back to its working
  directory, which a host may set anywhere (a home folder, the host's own
  install), and indexing that could take minutes. A folder that does not exist is
  reported on stderr at startup, and the server runs with no workspace.
  - The index is built once, before the first answer that needs it, not at
    startup.
  - With no workspace, single-file tools still work; a tool whose answer depends
    on the workspace (`lisp_definition` by name, workspace names in
    `lisp_completion`) says so in its result text rather than answering nothing.
  - A file outside the folder still resolves its own definitions, because R-8
    gives every request's file to `editor-services` with its text.
- **R-7. The tools, the language server's six and no others.** `tools/list`
  returns exactly these, each with `name`, `title`, `description`, `inputSchema`
  (`type: "object"`, `additionalProperties: false`) and `annotations`;
  `lisp_check` also has an `outputSchema` (R-10):

  | Tool | Answers | Asks `editor-services` for | The LSP capability it mirrors |
  |---|---|---|---|
  | `lisp_check` | the problems in a file | `editor-check` | diagnostics (`textDocumentSync`, pushed) |
  | `lisp_hover` | what the name at a place means: its workspace definition, else the built-in's documentation | `editor-symbol-at`, `editor-definitions-for`, then `documentation` of `editor-resolve` (as `lsp-hover` does) | `hoverProvider` |
  | `lisp_definition` | where a name is defined (by place, or by `name`) | `editor-symbol-at`, `editor-definitions-for`, `editor-definitions-named` | `definitionProvider` |
  | `lisp_completion` | the names that complete the word at a place, or a `prefix` | `editor-completions`, filtered here | `completionProvider` |
  | `lisp_expand_macro` | the macro call at a place and its expansion | `editor-macro-call-at` | `cog-lisp/expand` |
  | `lisp_format` | the source, formatted | `format-source` | `documentFormattingProvider` |

  Every tool is `readOnlyHint: true` and `openWorldHint: false`. A capability the
  language server gains is a tool this server gains, and one it loses is a tool
  this server loses: the table is the contract, and the tests compare it with
  `lsp.lisp`'s `initialize` answer and its one nonstandard method (AC-3).
  - **Completion is filtered, because an agent pays for every name.**
    `editor-completions` answers every name the file can use: hundreds of
    built-ins plus the index. The language server sends them all and leaves the
    filtering to the editor; an agent has no editor. `lisp_completion` keeps the
    names that start with the prefix (the given `prefix`, else the part of the
    word at the place before it), sorted, at most `limit` of them (default 50), and
    says how many more there were. A call with neither a place nor a `prefix` is
    `isError`.
  - **Each tool's `description` says when to use it**, in the words the skill
    uses (R-22), for a model that sees the tools without the skill.
- **R-8. Path, text, or both.** A tool that reads source takes `path`, `text`, or
  both:
  - `path` alone: the file is read from disk.
  - `text` alone: the agent's source, with no file behind it; it is answered as a
    file of no library, with no imports.
  - **both**: `path` names the file (its unit, its imports, its place in the
    index) and `text` is its contents. This is how an agent checks an unsaved
    buffer, which a separate process cannot see.
  - neither: `isError`, saying a tool needs `path` or `text`.

  Text a request sends never changes the index: the server answers from the index
  with that one file's entry taken from the request's text, then puts the entry
  back as it was (the file on disk, or nothing), so the next request sees what it
  would have seen anyway (R-5). If `editor-services` cannot answer that way
  without a change of its own, that change is part of this step and keeps the
  language server's behavior as it is.
- **R-9. Places are offsets or lines, and results give both.** A tool that takes a
  place takes either `offset` (characters from 0 into the text) or `line` and
  `column` (both from 1, the column in characters); giving both is `isError`.
  Models count characters badly, so `line`/`column` is the form the tools'
  descriptions show first. Results give the offset **and** `line`/`column`. No
  UTF-16 arithmetic appears in `mcp.lisp`; that stays in `lsp.lisp`, where a
  protocol requires it.
- **R-10. Results, in either envelope.** Every tool answers
  `content: [{"type": "text", "text": …}]`. `lisp_check` also answers
  `structuredContent: {"problems": [...]}`, which hosts on `2025-06-18` and later
  read, and declares its shape as `outputSchema` in `tools/list`; its text is the
  same JSON, for hosts that read only `content`. The text of `lisp_definition`,
  `lisp_completion` and `lisp_expand_macro` is JSON; that of `lisp_hover` is the
  documentation; that of `lisp_format` is the formatted source. In the modern era:
  - a result carries `resultType: "complete"` and
    `_meta.io.modelcontextprotocol/serverInfo` (the image's name and version);
  - `server/discover` and `tools/list` carry the cache hints the revision requires
    on them (its Caching page: servers MUST include them on these results):
    `ttlMs: 0` and `cacheScope: "public"`. A zero TTL says the catalog is always
    re-read; `public` says the six tools are the same for every caller.

  In the legacy era neither `resultType`, the per-result `_meta` nor the cache
  hints are sent: a `2025-11-25` client does not know them, and clients treat an
  absent `resultType` as `"complete"`.
- **R-11. Errors.** In both eras an unknown tool is `-32602` and an unknown method
  is `-32601`. A modern request missing a required `_meta` field, or naming an
  unsupported revision, is refused as R-5 says (`-32602`, `-32022`); no other
  error code is emitted but `-32603` for an internal error. A tool that cannot do
  its work (a missing file, text that does not read, no name at the place, a
  place outside the text) answers `isError: true` with a text line saying why,
  never a protocol error. A line that is not JSON is answered with `-32700` and
  a `null` id. One bad message never ends the loop, as with `lsp-serve`.
- **R-12. Quitting.** End of input ends the server with exit code 0, which both
  revisions name as the graceful shutdown of a stdio server. MCP has no
  `shutdown`/`exit` exchange; a host that sends them anyway gets `-32601` and the
  server keeps serving.
- **R-13. One table for the catalog and the calls.** The tools are one list of
  `(name title description schema handler)` records. `tools/list` and `tools/call`
  read the same list, so a tool cannot be listed and not callable. Adding a tool is
  one row.
- **R-14. Nothing executes source.** No tool in this spec evaluates, loads or runs
  a file (decision 1). The catalog contains no such name. (Expanding a macro and
  checking a file run macro expanders, as the language server's do; they run
  nothing else.)
- **R-15. Tests.**
  - `tests/lisp/mcp.lisp` tests the handlers, the tool table and the dispatch
    procedure of R-20 in the image, without a process, with `lib/test.lisp`
    (`define-test`, `check`), as every LISP suite does; `tests/run-all` runs it
    with no other change. It covers R-8 (all four forms, and that the index is the
    same before and after a request with `text`) and R-9 (both forms of a place).
  - `vscode/test/mcp.test.js` spawns the real server **through the launcher**
    (R-19) and drives both eras: the legacy handshake, a modern `server/discover`
    and a modern `tools/list`/`tools/call`, every tool, the error paths of R-11 in
    both eras, a malformed line, and that every line on stdout parsed as JSON. It
    also runs `lsp.lisp` once to compare the LSP's capabilities with the tool
    table (AC-3). CI runs it beside `lsp.test.js`, on Windows and Linux.
  - `vscode/test/package.test.js` and the extension's unit tests check R-17's
    contribution and the definition it answers.
  - `release/smoke-test.sh` starts the bundle's launcher, sends `initialize`, and
    checks the answer, on each platform.
- **R-16. Docs.**
  - **`README.md` gains a section, "Tools for coding agents (MCP)"**, after
    "Getting started": what the server answers in two sentences, and the setup
    for each host, each a copyable block: VS Code (nothing to do once the
    extension is installed and `cogLisp.root` or the open folder finds the
    launcher), Claude Code (the committed `.mcp.json`; approve it when Claude Code
    asks; how a project of the user's own adds one, as R-21's), and Bionic
    (`%USERPROFILE%\.lmstudio\mcp.json`, with `mcpServers`, through `cmd.exe /d /c`
    on Windows). It links `docs/mcp.md` for the rest. The documentation list gains
    a line too.
  - **`docs/mcp.md`**: what the server is, the launcher and its folder argument
    (R-6, R-19), the tool table, both eras in a paragraph, every host's
    configuration on Windows and Linux, how to see a server's stderr in each host
    when it fails to start, and the sentence that `lsp.lisp`, `mcp.lisp` and the
    Morphic IDE are three adapters over one service layer. The page holds no `{{`
    or `{%` (it goes through Liquid).
  - The release bundle's `INSTALL.md` gains the Bionic and Claude Code
    configurations with the bundle's paths.
- **R-17. The extension offers the server to VS Code.** `vscode/package.json`
  contributes a provider, and the extension registers it during activation:

  ```json
  "contributes": {
    "mcpServerDefinitionProviders": [
      { "id": "cog-lisp.mcp", "label": "cog-lisp" }
    ]
  }
  ```

  The provider answers one `McpStdioServerDefinition` that runs the launcher of
  R-19 from `cogLisp.root`, as the language server is run: on Windows
  `cmd.exe /d /c .\mcp-server.bat <folder>` with the root as its working
  directory, elsewhere `./mcp-server.sh <folder>`; `<folder>` is the first
  workspace folder (R-6). Its `version` is the image's version — which the
  extension already has, because it compares it with its own
  (`specs/28-versioning.md` R-11) — so a rebuilt image makes the host offer a
  refreshed tool list.
  - No activation event is added: VS Code generates
    `onMcpCollection:cog-lisp.mcp` for the contribution and activates the
    extension when the collection is needed.
  - When `cogLisp.root` is empty and no workspace folder holds a launcher, or the
    root has no built image, the extension writes why to its output channel and
    offers no server rather than one that cannot start.
- **R-18. The version is the image's.** `serverInfo.version` in the legacy
  handshake, and `_meta.io.modelcontextprotocol/serverInfo` in modern results, is
  `*env*`'s `version`, as the language server reports it, so a host's log names the
  image that answered.
- **R-19. The launcher, and the checkout's image stays free.** A server a host
  keeps running must never hold `pharo/cog-lisp.image` and its changes file, or
  `build-image` and `tests/run-all` fail for as long as the host is open (§1).
  `mcp-server.bat` and `mcp-server.sh`, at the root of the checkout and of each
  release bundle (a twin pair, kept in step like the others):
  - find the image as `cog-lisp.bat`/`.sh` do (`COGLISP_IMAGE`, else the
    checkout's or the bundle's own), and copy it and its changes file into a new
    folder under the temporary folder (`cog-lisp-mcp-*`);
  - run `cog-lisp lib/mcp.lisp <folder>` on the copy, through `COGLISP_IMAGE`,
    passing standard input, output and error through unchanged, and exit with
    its exit code;
  - remove the copy when the server exits, and at each start remove earlier
    copies no VM still holds (a host that kills its server leaves one behind);
  - **write nothing to standard output themselves**: every message of their own,
    and every command's (`copy` prints "1 file(s) copied."), goes to stderr or
    nowhere, because stdout is the wire (R-2);
  - with no built image, say so on stderr and exit 1.

  Because every host runs the launcher, no configuration needs a copy of its own,
  and no copy goes stale: each start copies the image as it is then.
- **R-20. The protocol is a procedure, the transport a loop.** `lib/mcp.lisp`
  separates them:
  - `(mcp-handle message)` takes one parsed message and answers the reply to
    send (a hash table), or `#f` for a notification. It reads no input, writes no
    output, and knows nothing of lines or processes;
  - `(mcp-serve-stdio)` reads lines, parses them (answering `-32700` itself for a
    line that does not parse), calls `mcp-handle`, and writes what it answers.

  A later transport (L-35.1) calls `mcp-handle` unchanged. The LISP suite tests
  `mcp-handle` directly (R-15).
- **R-21. Claude Code finds the server in each cog-lisp project.** A committed
  `.mcp.json` at the root of this repository and of `~/projects/lisp-expert`
  names one stdio server, `cog-lisp`, that runs the launcher with the project's
  own folder as its argument (R-6).
  - **This repository's** runs its own `mcp-server` launcher.
  - **`lisp-expert`'s** finds cog-lisp as its `run-tests` does: `COGLISP_HOME`
    when it is set, else the sibling checkout `../cog-lisp`, through
    `.mcp.json`'s `${VAR:-default}` expansion. Its `CLAUDE.md` gains a line on the
    tools, and its instructions for copying the skill name the new file of R-22.
  - Windows runs the `.bat` through `cmd.exe /d /c`. One committed file serves
    Windows and Linux if `${VAR:-default}` expansion can choose the launcher's
    command; if it cannot, the committed file is the Windows form and
    `docs/mcp.md` gives the Linux one for a local-scope server. Which of the two
    holds is recorded in §7, from AC-16.
- **R-22. The skill teaches the tools.** The agent skill
  (`.agents/skills/cog-lisp/`, generated from `docs/skill/`) gains a file,
  `mcp.md`, generated from `docs/skill/mcp.md`, and SKILL.md gains a short
  pointer to it in "Work in this loop": when the `cog-lisp` tools are available,
  read `mcp.md`. (SKILL.md is 10,103 bytes of its 10,240-byte budget: the detail
  cannot go there, and the pointer may need words taken from elsewhere in it.)
  `mcp.md` says, for a small model, in the skill's plain style:
  - **The loop with tools**: write the file; `lisp_check` it (`path`) and fix
    every problem; then run it, because no tool runs code and only a run shows
    output. An unsaved edit is checked with `path` and `text` together.
  - **Before using a name**: `lisp_hover` on it, or `lisp_definition` with
    `name` for one defined in the project, instead of guessing; `lisp_completion`
    with a `prefix` to find the right name.
  - **When a macro misbehaves**: `lisp_expand_macro` at its call.
  - **After editing**: `lisp_format` the file and write back what it answers.
  - **Places**: give `line` and `column`, both from 1; read a result's `line`
    and `column` rather than its `offset`.
  - **Without the tools**, the run loop of SKILL.md still works.

  Every tool `mcp.md` names is in R-7's table, and every tool in the table is in
  `mcp.md` (the skill suite checks both), so the skill and the server cannot
  drift. `tools/docs.lisp` generates it, the 10.7 suite checks it is current, and
  the release's skill zip includes it.
- **R-23. Deferred work is never lost.** This spec defers work (§10). So that
  it, and every later spec's deferrals, is picked up:
  - a spec's deferred items live in a section titled **"Later"**, each with an id
    `L-<spec number>.<n>` (`L-35.1`), what it is, and why it waits;
  - `PROJECT-PLAN.md`'s list **"Deferred: to pick up"** names every id, links its
    spec, and says when it should be considered; an item picked up names the spec
    that took it, and an item dropped says why, by the owner's decision;
  - `specs/README.md`'s workflow says so;
  - a suite (`tests/lisp/deferred.lisp`) fails when an id in any spec's "Later"
    section is missing from the plan's list, or an id in the list is in no spec.

## 4. Acceptance criteria

- **AC-1:** `mcp-server.bat` (and `.sh`) starts, answers `initialize` with a
  protocol version, the tools capability and `serverInfo` carrying the image's
  version, then answers `ping`.
- **AC-2:** the modern era works in the same process: `server/discover` with `_meta`
  answers `resultType: "complete"`, `supportedVersions: ["2026-07-28"]`, the tools
  capability, `instructions`, `_meta.io.modelcontextprotocol/serverInfo`, and
  `ttlMs: 0` with `cacheScope: "public"`; a `tools/list` with `_meta` answers the
  same envelope and hints around the six tools; a request without
  `clientCapabilities` is `-32602`; one naming `1900-01-01` is `-32022` with both
  revisions in `data.supported` and the client's in `data.requested`. No legacy
  answer carries `resultType`, `ttlMs` or `cacheScope`.
- **AC-3:** the catalog is the language server's: each of the five capabilities
  `lsp.lisp` advertises in `initialize` (`textDocumentSync`, `hoverProvider`,
  `completionProvider`, `definitionProvider`, `documentFormattingProvider`) and
  its nonstandard `cog-lisp/expand` method maps to one tool of R-7, and no tool
  maps to nothing, checked mechanically in `mcp.test.js`. A new capability in
  `lsp.lisp` fails the test until this spec and the table change.
- **AC-4:** `tools/list` returns the six tools, each with a valid `inputSchema`
  and its annotations, `lisp_check` with an `outputSchema` its
  `structuredContent` matches, and no name from R-14.
- **AC-5:** on a workspace with a library, a program that uses it, and a broken
  file, with the server started on that folder as R-6 describes, every tool
  answers: `lisp_check` finds the unterminated string;
  `lisp_definition` on a call into the library gives its path and line;
  `lisp_hover` gives that procedure's documentation, and a built-in's
  documentation on a built-in; `lisp_completion` completes a prefix with at most
  `limit` names and says how many more there were; `lisp_expand_macro` expands a
  macro call; `lisp_format` reindents a misindented file.
- **AC-6:** the same source given as `path` and as `path` with `text` gives the
  same answer for every tool; an unsaved change given as `text` with its `path`
  is checked as the text says, and a following call with `path` alone sees the
  file on disk again; a tool given neither says so with `isError`.
- **AC-7:** a place given as `line`/`column` and as the same `offset` gives the
  same answer; both at once, or a place outside the text, is `isError`.
- **AC-8:** errors are as R-11 says in both eras: an unknown tool is `-32602`, an
  unknown method is `-32601`, a line that is not JSON is `-32700`, and the next
  message on the same connection still gets its answer.
- **AC-9:** nothing but protocol reaches stdout, the launcher's own work
  included: in `mcp.test.js`, every line written is JSON, including a run over a
  file that draws a compiler warning.
- **AC-10:** the server exits 0 when its input ends, and the launcher with it,
  leaving no copy behind. Started with no folder, it indexes nothing and
  `lisp_definition` by name says there is no workspace.
- **AC-11:** while a server started by the launcher runs, `build-image` succeeds
  (in `mcp.test.js` on Windows: the checkout's `pharo/cog-lisp.changes` is not
  held, which is what the build needs). A copy left by a killed server is
  removed by the next start.
- **AC-12:** `mcp-handle` answers a message with no process around it, and the
  stdio loop is the only code in `lib/mcp.lisp` that reads or writes (R-20).
- **AC-13:** the extension's definition runs the launcher through `cmd.exe /d /c`
  on Windows and with the first workspace folder (the extension's unit tests).
- **AC-14:** the generated skill has `mcp.md`; SKILL.md points to it and stays
  under its budget; every tool `mcp.md` names is in the tool table and every tool
  in the table is in `mcp.md` (the 10.7 suite).
- **AC-15:** the deferred-work suite passes, with `L-35.1` in
  `PROJECT-PLAN.md`'s list; removing it from the list fails the suite.
- **AC-16 (by hand, recorded in §7):** Claude Code, started in this repository
  and in `lisp-expert`, on Windows and on Linux, lists the `cog-lisp` server from
  `.mcp.json` and runs `lisp_check` on a file of that project.
- **AC-17 (by hand, recorded in §7):** a Bionic session with the server in
  `%USERPROFILE%\.lmstudio\mcp.json`, configured as `README.md` says, lists the six
  tools and runs `lisp_check` on a file in this repository.
- **AC-18 (by hand, recorded in §7):** with the extension installed, VS Code's MCP
  servers list shows the extension's `cog-lisp` server, an agent session offers
  `lisp_check`, the server starts on the first message, not when the window
  loads, and `build-image` succeeds while it runs.
- **AC-19 (by hand, recorded in §7):** `tools/skill-eval.js` run twice with the
  evaluation's model through Bionic, once without the server and once with it
  and the skill's `mcp.md`; the scores are recorded. This measures; it does not
  gate the release.
- **AC-20:** every suite passes on Windows and Linux, and the release smoke test
  starts the bundle's launcher on each.

## 5. Steps

Two steps, released together (decision 6):

1. **The server.** `lib/mcp.lisp` (R-1 to R-14, R-18, R-20), the launcher
   (R-19), the suites (R-15), and the deferred-work list and its suite (R-23).
   AC-1 to AC-12, AC-15.
2. **Its hosts.** The extension's provider (R-17), the `.mcp.json` files (R-21),
   the skill (R-22), the docs and the README (R-16), the release bundle. AC-13,
   AC-14, AC-16 to AC-20.

## 6. Risks

- **Standard output is the wire.** Any `display` in code reached by `require`, a
  future compiler message on stdout, a stray print, or a launcher command's own
  output corrupts one line and the host drops the connection. Today compiler
  warnings go to stderr (`coglisp-compiler.st:664`), and AC-9 keeps it that way.
- **Two envelopes, one body.** The tool handlers are era-blind by construction
  (R-13), so only the envelope is at risk: `resultType`, per-result `_meta`, the
  cache hints, and `-32022`. AC-2 and AC-8 keep the modern envelope honest, but no
  host we know opens modern yet — Bionic speaks legacy and VS Code may speak
  either — so the modern path is proven by test before it is proven by use.
- **The modern revision is younger than the legacy one.** `2026-07-28` is the
  current stable revision and changed more than any before it. If a host's modern
  client differs on a detail, the fix is at the envelope, and the tool table and
  handlers stand unchanged.
- **Text that leaves the index as it found it** (R-8) may need a small addition
  to `editor-services`. It is shared with the language server and the IDE, so
  their suites must pass unchanged.
- **The launcher's cleanup is best effort.** A host that kills its server skips
  the removal; the next start sweeps. A machine that never starts another server
  keeps one copy (about the image's size) in its temporary folder.
- **One `.mcp.json` for two platforms** may not be possible (R-21). The fallback
  is a Windows file and documented Linux steps, which is what `lisp-expert`'s
  `opencode.jsonc` already does.
- **The skill's budget.** SKILL.md has 137 bytes left; the pointer of R-22 may
  cost words elsewhere in it. `mcp.md` is a separate file, so it has its own
  budget: keep it under 3 KB, so that reading it is cheap for a small model.
- **A large file is one long line.** `text` carrying a 100 KB file is a 100 KB
  line. Reading it whole costs memory, not correctness.
- **The image is single-threaded.** A `lisp_check` of a large file blocks the next
  request; a host with a timeout may retry. No concurrency is promised, and the
  tools are cheap enough that this should not be felt.
- **The index is the cost of the first answer.** The first tool call that needs
  the workspace pays for `editor-index-folder!`: 1.5 s measured on this repository,
  growing with the tree. Answers that need only their own `path`/`text` do not
  wait for it. The launcher's copy adds the time to copy the image at each start.
- **The recipe needs `cogLisp.root`.** Without it the extension cannot find the
  launcher. R-17 makes it say so rather than register a server that cannot start.
- **Two adapters can drift.** `lsp.lisp` and `mcp.lisp` ask the same services but
  may expose different subsets. AC-3 makes that a test failure rather than a
  discovery, but the two files still need reading together when a capability
  changes.

## 7. As built

Not built yet. A first draft of `lib/mcp.lisp` and of the extension's provider
exists in the working tree (2026-11-12). It predates §9 and must follow it: it
reads `rootUri`/`workspaceFolders` from `initialize`, handles
`notifications/roots/list_changed`, falls back to the working directory, runs the
checkout's image, takes text or path but not both, and its provider names the
`.bat` as the command instead of running it through `cmd.exe /d /c`.

## 8. Decisions (owner, 2026-11-12)

1. **The catalog is the language server's.** Expose everything the LSP provides,
   and nothing else: the six tools of R-7, one for each capability or method it
   answers. Evaluator tools are not in it (the language server has none); L-35.1
   takes them up.
2. **Both revisions.** A dual-era server, as `2026-07-28` defines the term: legacy
   `initialize` for Bionic, modern per-request `_meta` for hosts that open that way.
   The cost is one dispatch and two envelopes (R-3, R-5, R-10), not two servers.
3. **Short tool names.** `lisp_check`, `lisp_hover`, and so on.
4. **Text or path: both** (R-8), so an unsaved buffer can be checked.
5. **Offsets and line/column: both** (R-9).
6. **One release.** The server and its hosts ship together (§5).
7. **Run, not hosted.** For this step each host runs its own server; a server
   hosted by a running image is later work (§10). Building this one teaches how
   to build an MCP server in LISP, which other open work needs.
8. **Per-project Claude Code configuration**, in this repository and in
   `lisp-expert` (R-21).
9. **Setup in the README** (R-16), for every host.
10. **The protocol apart from the transport** (R-20).
11. **Deferred work is tracked where it will be picked up** (R-23), not only in
    its spec.
12. **The skill says exactly how to use the tools** (R-22).

## 9. Changes after review (2026-11-12)

The spec was reviewed against the code and against the published revisions
(`2025-11-25`'s Lifecycle page; `2026-07-28`'s Versioning, Discovery and Caching
pages). What changed, and why:

1. **No roots from the client** (R-6, §2). MCP's `initialize` has no `rootUri` or
   `workspaceFolders` (those are LSP's); its roots come only from a `roots/list`
   request the server would send. The folder is now the command-line argument in
   both eras, so roots' status in any revision does not matter here.
2. **The checkout's image stays free** (R-19, AC-11). A host keeps the server
   running, and a VM holding `pharo/cog-lisp.changes` makes `build-image` fail, so
   the server runs on a private copy, as the language server does.
3. **R-2's write.** `json-write` writes to the port; it does not answer a string.
4. **Path and text together** (R-8, AC-6). The services that need imports take a
   path, so an unsaved buffer is `path` plus `text`; the request's text does not
   stay in the index (R-5's "stateless" made precise).
5. **No working-directory fallback** (R-6, AC-10).
6. **Places as line/column too** (R-9, AC-7), because models count characters
   badly.
7. **Completion is filtered** (R-7, AC-5): a prefix and a limit, since
   `editor-completions` answers every name.
8. **Hover names both its sources** (R-7, AC-5), as `lsp-hover` has them.
9. **`lisp_check` declares an `outputSchema`** (R-7, R-10, AC-4).
10. **Errors:** the claim about codes `2025-11-25` "retired" is gone (R-11 now
    lists every code it emits), and a line that is not JSON is `-32700` (AC-8).
11. **Cache hints** (R-10): confirmed required on `server/discover` and
    `tools/list` by the Caching page.
12. **Tests** (R-15): the LISP suite uses `lib/test.lisp`, not `tests/harness.st`.

Then the owner's additions (decisions 7 to 12):

13. **Claude Code** (R-21, AC-16): the extension's provider reaches VS Code's own
    agent only, so each cog-lisp project commits a `.mcp.json`.
14. **One launcher for every host** (R-19, AC-1, AC-9 to AC-11): it makes the
    private copy that R-19 first left to each host, so the extension, Claude Code
    and Bionic configure one command. It replaces the extension's own copying for
    this server (R-17), and runs through `cmd.exe /d /c` on Windows.
15. **Setup in the README** (R-16).
16. **The protocol apart from the transport** (R-20, AC-12), for L-35.1.
17. **The skill** (R-22, AC-14, AC-19) and **deferred work** (R-23, AC-15, §10).

## 10. Later

- **L-35.1 An MCP server hosted by a running image.** A server inside a
  long-running image (the development image of `specs/34-morphic-ide.md` first),
  which agents connect to over MCP's Streamable HTTP, so they work with the live
  image rather than a throwaway copy, and gain the tools the language server does
  not have: evaluation (`eval`, `run-file`), inspection, the image's sessions and
  record of changes (`lib/ide.lisp`). It needs its own spec: binding to
  localhost only, what an agent may change and how the owner sees and stops it,
  the server's lifecycle inside the image, and both eras over HTTP. It reuses
  this spec's `mcp-handle` (R-20) and tool table (R-13). **Waits for** this
  spec to be built and used; consider it when the agent work of the north star
  (the image as an agent's body) begins, or when an agent first needs to
  evaluate in the image.
