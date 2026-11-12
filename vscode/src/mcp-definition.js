// How the extension starts cog-lisp's MCP server (specs/35-mcp-server.md R-17):
// the checkout's launcher, which runs lib/mcp.lisp on a private copy of the image
// (R-19), with the workspace folder as its argument (R-6). On Windows a batch
// file runs through cmd.exe: Node spawns no .bat without a shell. Kept apart from
// extension.js, which needs VS Code, so plain Node tests it.
'use strict';
const path = require('path');
const fs = require('fs');

/** The command, arguments and working directory that run the server from root. */
function mcpServerCommand(root, folder, windows) {
  const extra = folder ? [folder] : [];
  return windows
    ? { command: 'cmd.exe', args: ['/d', '/c', '.\\mcp-server.bat', ...extra], cwd: root }
    : { command: path.join(root, 'mcp-server.sh'), args: extra, cwd: root };
}

/** Why root cannot serve, or null when it can: a launcher, the server and a built image. */
function mcpServerProblem(root, windows) {
  if (!root) return 'no cog-lisp folder found: open the cog-lisp folder, or set cogLisp.root';
  const launcher = path.join(root, windows ? 'mcp-server.bat' : 'mcp-server.sh');
  if (!fs.existsSync(launcher)) return launcher + ' is missing: update the cog-lisp checkout';
  if (!fs.existsSync(path.join(root, 'lib', 'mcp.lisp'))) return path.join(root, 'lib', 'mcp.lisp') + ' is missing';
  if (!fs.existsSync(path.join(root, 'pharo', 'cog-lisp.image'))) return 'no built image in ' + path.join(root, 'pharo') + ': run build-image';
  return null;
}

module.exports = { mcpServerCommand, mcpServerProblem };
