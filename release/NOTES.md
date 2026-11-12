## Installing

Download the bundle for your platform, unpack it, and run the launcher in the
unpacked folder. Each bundle has the Pharo VM, the cog-lisp image, the LISP
library and the examples; nothing else needs installing.

| Platform | Bundle | Then |
|---|---|---|
| Linux x86-64 | `cog-lisp-VERSION-linux-x86_64.tar.gz` | `./cog-lisp.sh` (the REPL) or `./cog-lisp.sh examples/hello.lisp` |
| Windows x86-64 | `cog-lisp-VERSION-windows-x86_64.zip` | `cog-lisp.bat` or `cog-lisp.bat examples\hello.lisp` |

The VS Code extension is `cog-lisp-VERSION.vsix` (*Install from VSIX...*); open
the unpacked folder to run files and the REPL from the editor. `INSTALL.md` in
each bundle has the details.

`cog-lisp-skill-VERSION.zip` is a skill for AI agents, such as Bionic's (LM
Studio): how to write, run and fix cog-lisp programs, with checked examples. The
bundles carry it too, in `.agents/skills/cog-lisp/`, so it is active when the
unpacked folder is opened as a Bionic project.

`mcp-server.sh` (`mcp-server.bat` on Windows) in each bundle serves tools for
coding agents over the Model Context Protocol: check a file, explain a name,
find a definition, complete a name, expand a macro call, format source. The VS
Code extension offers it to VS Code's agent; for Claude Code, Bionic and others,
`INSTALL.md` and `docs/mcp.md` show the configuration.

cog-lisp is under the MIT license. Each bundle includes the Pharo image and VM
and the libraries the VM needs, with their licenses in `licenses/` and a summary
in `THIRD-PARTY-NOTICES.md`.
