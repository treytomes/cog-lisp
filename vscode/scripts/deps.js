// deps.js -- make node_modules/ match package-lock.json, running `npm ci` only
// when it does not (specs/31-vsix-bundle.md R-8). build-ext.sh and build-ext.bat
// run it before packaging, so a checkout whose lockfile has changed since its
// last install (esbuild added, a package moved to a new version) reinstalls by
// itself, and one that is current does not.
//
// It reads what is installed, not a stamp: each package the lockfile lists must
// be in node_modules/ at the lockfile's version, however it was installed (by
// hand, by CI's own npm ci, or by this). A package marked optional (esbuild's
// builds for other platforms) is checked only if it is there.
//
//   node scripts/deps.js           reinstall if needed
//   node scripts/deps.js --check   only say whether it is needed (exit 1 if so)
'use strict';
const fs = require('fs');
const path = require('path');
const cp = require('child_process');

const root = path.join(__dirname, '..');
const checkOnly = process.argv.includes('--check');

// what is out of step: a list of "name (wanted, found)"
function stale() {
  const lock = JSON.parse(fs.readFileSync(path.join(root, 'package-lock.json'), 'utf8'));
  const out = [];
  for (const [where, entry] of Object.entries(lock.packages || {})) {
    if (where === '' || entry.link) continue;          // the extension itself; a linked folder
    const manifest = path.join(root, where, 'package.json');
    let found = null;
    try { found = JSON.parse(fs.readFileSync(manifest, 'utf8')).version; } catch (e) { found = null; }
    if (found === null && entry.optional) continue;    // another platform's build
    if (found !== entry.version) out.push(where.replace(/^.*node_modules\//, '') + ' (wanted ' + entry.version + ', found ' + (found || 'none') + ')');
  }
  return out;
}

const problems = stale();
if (problems.length === 0) process.exit(0);
console.log('The extension\'s npm packages do not match package-lock.json: ' +
  problems.slice(0, 3).join(', ') + (problems.length > 3 ? ' and ' + (problems.length - 3) + ' more' : ''));
if (checkOnly) process.exit(1);
console.log('Installing them (npm ci)...');
const r = cp.spawnSync('npm', ['ci'], { cwd: root, stdio: 'inherit', shell: true });
if (r.status !== 0) { console.error('npm ci failed'); process.exit(r.status || 1); }
const left = stale();
if (left.length) { console.error('still out of step after npm ci: ' + left.slice(0, 3).join(', ')); process.exit(1); }
