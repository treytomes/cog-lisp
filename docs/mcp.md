# Tools for coding agents (MCP)

cog-lisp's image serves the [Model Context Protocol](https://modelcontextprotocol.io),
so a coding agent can ask cog-lisp itself about cog-lisp source: what is wrong
with a file, what a name means and where it is defined, which names complete a
prefix, what a macro call expands to, and how the file is laid out. The answers
are the language server's, from the same code. `lib/lsp.lisp` (for editors),
`lib/mcp.lisp` (for agents) and the image's own Morphic IDE are three adapters
over one service layer, `lib/editor-services.lisp`. No tool runs code.

## The tools

| Tool | Answers | Mirrors in the language server |
|---|---|---|
| `lisp_check` | the problems compiling a file would meet: read errors, compile errors, warnings | diagnostics |
| `lisp_hover` | what the name at a place means: a built-in's documentation, or a project definition and its source | hover |
| `lisp_definition` | where a name is defined, given a place or a `name` | go to definition |
| `lisp_completion` | the names starting with a `prefix` (or the word at a place), at most `limit` | completion |
| `lisp_expand_macro` | the macro call at a place and its full expansion | Expand Macro |
| `lisp_format` | the source, laid out as cog-lisp lays it out | Format Document |

Every tool takes the source as `path` (a file), `text`, or both: `path` with
`text` is the unsaved contents of that file. A place is `line` and `column`,
both from 1, or `offset`, characters from 0; results give both. A relative
`path` is taken from the workspace folder.

The agent skill (`.agents/skills/cog-lisp/mcp.md`) tells an agent when to use
each tool.

## Running it

```text
mcp-server.bat [folder]       (Windows)
./mcp-server.sh [folder]      (Linux)
```

The launcher is in the cog-lisp checkout and in each release bundle. `folder`
is the workspace: the folder whose `.lisp` files the tools search for
definitions and names. Without it there is no workspace, and the tools answer
from the given source alone (and say so). The index of the workspace is built
at the first answer that needs it and follows the files as they change on disk.

The launcher copies the image to a folder of its own in the temporary folder,
runs the server on the copy, and removes it when the server ends. So a server
an agent keeps running never holds `pharo/cog-lisp.image`, and `build-image`
works while it runs; and a rebuilt image is served from the next start. Set
`COGLISP_IMAGE` to serve another image.

Standard output carries the protocol and nothing else; the server writes its
own messages to standard error, where each host keeps a log (below).

### Both revisions of the protocol

The server speaks the protocol revision `2025-11-25` to a client that opens
with `initialize` (the handshake, for the session) and `2026-07-28` to a request
that carries the revision in its `_meta` (no handshake: each request stands
alone), in one process. Hosts of today open with `initialize`.

## Setting up a host

On Windows, every host runs the launcher through `cmd.exe /d /c`: hosts start
programs without a shell, and a batch file needs one.

### VS Code

Nothing to do: the cog-lisp extension offers the server to VS Code's agent once
it finds the cog-lisp folder (the open folder, or the `cogLisp.root` setting)
with a built image. It starts the server on the first workspace folder when the
agent first needs it. If it offers none, the "cog-lisp" output channel says why.
To configure it by hand instead, `.vscode/mcp.json`:

```json
{
  "servers": {
    "cog-lisp": {
      "type": "stdio",
      "command": "cmd.exe",
      "args": ["/d", "/c", "C:\\path\\to\\cog-lisp\\mcp-server.bat", "${workspaceFolder}"]
    }
  }
}
```

### Claude Code

The cog-lisp repository commits a `.mcp.json` that starts the server on the
project's folder; Claude Code asks once to approve it. Another project of
yours adds its own `.mcp.json` (or `claude mcp add`):

```json
{
  "mcpServers": {
    "cog-lisp": {
      "type": "stdio",
      "command": "cmd.exe",
      "args": ["/d", "/c", "C:\\path\\to\\cog-lisp\\mcp-server.bat", "${CLAUDE_PROJECT_DIR:-.}"]
    }
  }
}
```

The committed `.mcp.json` is the Windows form. On Linux, add the server under
the same name at local scope, which takes the place of the project's:

```text
claude mcp add --scope local cog-lisp -- /path/to/cog-lisp/mcp-server.sh .
```

`claude mcp list` checks that it starts.

### Bionic (LM Studio)

In `%USERPROFILE%\.lmstudio\mcp.json`:

```json
{
  "mcpServers": {
    "cog-lisp": {
      "command": "cmd.exe",
      "args": ["/d", "/c", "C:\\path\\to\\cog-lisp\\mcp-server.bat", "C:\\path\\to\\your\\project"]
    }
  }
}
```

On Linux, `"command": "/path/to/cog-lisp/mcp-server.sh"` with the project folder
as the only argument.

### When it does not start

Run the launcher by hand with one request on its input; it answers one line:

```text
echo {"jsonrpc":"2.0","id":1,"method":"ping"} | mcp-server.bat
```

A server that fails writes why to standard error: VS Code shows it in the MCP
server's output (the MCP: List Servers command, then Show Output), Claude Code
in `claude mcp list` and its debug log (`claude --debug`), Bionic in its
developer logs. The usual causes are no built image (`build-image`) and, on
Windows, a host given the `.bat` without `cmd.exe /d /c`.
