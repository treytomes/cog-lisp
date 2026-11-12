// How the extension starts the MCP server (specs/35-mcp-server.md R-17, AC-13):
// the launcher, through cmd.exe on Windows, with the workspace folder; and no
// server where it cannot start. PASS/FAIL + RESULT convention.
'use strict';
const path = require('path');
const fs = require('fs');
const os = require('os');
const { mcpServerCommand, mcpServerProblem } = require('../src/mcp-definition');

let pass = 0;
let total = 0;
function check(label, ok) {
  total++;
  if (ok) pass++;
  console.log((ok ? '  PASS  ' : '  FAIL  ') + label);
}

console.log('== the extension\'s MCP server definition ==');
const win = mcpServerCommand('C:\\cog-lisp', 'C:\\work\\project', true);
check('Windows: cmd.exe /d /c runs the launcher, never the .bat itself',
  win.command === 'cmd.exe' && JSON.stringify(win.args) === JSON.stringify(['/d', '/c', '.\\mcp-server.bat', 'C:\\work\\project']));
check('Windows: from the cog-lisp folder', win.cwd === 'C:\\cog-lisp');
const linux = mcpServerCommand('/opt/cog-lisp', '/home/me/project', false);
check('Linux: the launcher script, with the folder',
  linux.command === path.join('/opt/cog-lisp', 'mcp-server.sh') && JSON.stringify(linux.args) === '["/home/me/project"]');
check('no workspace folder: no argument', mcpServerCommand('C:\\cog-lisp', null, true).args.length === 3);
// never the checkout's image itself: the launcher makes the copy (R-19)
check('the definition runs mcp-server, which copies the image, and names no image',
  !win.args.some((a) => /cog-lisp\.(bat|image)$/.test(a)));

check('no root: no server, and why', /cogLisp\.root/.test(mcpServerProblem(null, true)));
const empty = fs.mkdtempSync(path.join(os.tmpdir(), 'cog-lisp-mcp-def-'));
check('a folder without the launcher: no server', /mcp-server\.bat is missing/.test(mcpServerProblem(empty, true)));
fs.writeFileSync(path.join(empty, 'mcp-server.bat'), '');
fs.mkdirSync(path.join(empty, 'lib'));
fs.writeFileSync(path.join(empty, 'lib', 'mcp.lisp'), '');
check('a folder without a built image: no server', /no built image/.test(mcpServerProblem(empty, true)));
fs.mkdirSync(path.join(empty, 'pharo'));
fs.writeFileSync(path.join(empty, 'pharo', 'cog-lisp.image'), '');
check('a folder with all three serves', mcpServerProblem(empty, true) === null);
fs.rmSync(empty, { recursive: true, force: true });

console.log('');
console.log('== RESULT: ' + pass + '/' + total + ' checks passed ==');
process.exit(pass === total ? 0 : 1);
