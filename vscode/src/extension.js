// cog-lisp for VS Code (specs/phase-7.5-review-and-tooling.md section 5).
// Deliberately thin: highlighting and brackets are declarative (package.json,
// the grammar, language-configuration.json); this file only adds commands that
// call the repo's own scripts, so the editor runs exactly what the terminal runs.
// The language intelligence is planned for a language server served by the
// image itself (section 5.4).
'use strict';

const vscode = require('vscode');
const fs = require('fs');
const path = require('path');
const { topLevelFormAt } = require('./forms');

const REPL_NAME = 'cog-lisp REPL';
let replTerminal = null;
let lastStaleWarning = 0;

// The scripts the extension runs: the .bat files on Windows, the .sh files on
// Linux (Phase 8.9). macOS is not supported yet.
const WINDOWS = process.platform === 'win32';
const SUPPORTED = WINDOWS || process.platform === 'linux';
function script(name) { return name + (WINDOWS ? '.bat' : '.sh'); }

/** The folder holding the cog-lisp script (a checkout or an unpacked release):
 *  the cogLisp.root setting, else the workspace folder that has it. */
function cogLispRoot() {
  const launcher = script('cog-lisp');
  const configured = vscode.workspace.getConfiguration('cogLisp').get('root');
  if (configured && fs.existsSync(path.join(configured, launcher))) return configured;
  for (const folder of vscode.workspace.workspaceFolders || []) {
    if (fs.existsSync(path.join(folder.uri.fsPath, launcher))) return folder.uri.fsPath;
  }
  return null;
}

function requireRoot() {
  if (!SUPPORTED) {
    vscode.window.showErrorMessage('cog-lisp: running programs needs Windows or Linux.');
    return null;
  }
  const root = cogLispRoot();
  if (!root) {
    vscode.window.showErrorMessage('cog-lisp: no ' + script('cog-lisp') + ' found. Open the cog-lisp folder, or set cogLisp.root.');
    return null;
  }
  return root;
}

/** cmd.exe arguments that run one of the repo's batch files from the repo root.
 *  The script is named as .\x.bat: cmd may not search the current directory for a
 *  bare name (NoDefaultCurrentDirectoryInExePath), and a relative path keeps the
 *  command line free of the quotes cmd /c mangles when the root has spaces. */
function scriptArgs(name, args) {
  return ['/d', '/c', '.\\' + name, ...args];
}

/** A process that runs one of the scripts from the root: through cmd.exe on
 *  Windows, through bash elsewhere. */
function scriptExecution(root, name, args) {
  if (WINDOWS) return new vscode.ProcessExecution('cmd.exe', scriptArgs(name, args), { cwd: root });
  return new vscode.ProcessExecution('/bin/bash', [path.join(root, name), ...args], { cwd: root });
}

/** Run the active file with the cog-lisp script as a task, so errors become problems. */
async function runFile() {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;
  const root = requireRoot();
  if (!root) return;
  const doc = editor.document;
  if (doc.isUntitled) {
    vscode.window.showErrorMessage('cog-lisp: save the file before running it.');
    return;
  }
  if (doc.isDirty) await doc.save();
  const file = doc.uri.fsPath;
  const task = new vscode.Task(
    { type: 'cog-lisp', task: 'run', file },
    vscode.TaskScope.Workspace,
    'run ' + path.basename(file),
    'cog-lisp',
    scriptExecution(root, script('cog-lisp'), [file]),
    ['$cog-lisp']);
  task.presentationOptions = { reveal: vscode.TaskRevealKind.Always, clear: true, focus: false };
  await vscode.tasks.executeTask(task);
}

/** Rebuild pharo/cog-lisp.image with the build-image script (review T-3). */
async function rebuildImage() {
  const root = requireRoot();
  if (!root) return;
  const task = new vscode.Task(
    { type: 'cog-lisp', task: 'build' },
    vscode.TaskScope.Workspace,
    'build image',
    'cog-lisp',
    scriptExecution(root, script('build-image'), []),
    []);
  task.presentationOptions = { reveal: vscode.TaskRevealKind.Always, clear: true };
  await vscode.tasks.executeTask(task);
}

function replOptions(root) {
  if (WINDOWS) return { name: REPL_NAME, shellPath: 'cmd.exe', shellArgs: scriptArgs('cog-lisp.bat', []), cwd: root };
  return { name: REPL_NAME, shellPath: '/bin/bash', shellArgs: [path.join(root, 'cog-lisp.sh')], cwd: root };
}

/** The REPL terminal, started if there is none (one per window). */
function ensureRepl(show) {
  const root = requireRoot();
  if (!root) return null;
  if (!replTerminal || replTerminal.exitStatus !== undefined) {
    replTerminal = vscode.window.createTerminal(replOptions(root));
  }
  if (show) replTerminal.show(true);
  return replTerminal;
}

/** Send the selection, or else the top-level form at the cursor, to the REPL. */
function sendToRepl() {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;
  const doc = editor.document;
  let text;
  if (!editor.selection.isEmpty) {
    text = doc.getText(editor.selection);
  } else {
    const range = topLevelFormAt(doc.getText(), doc.offsetAt(editor.selection.active));
    if (!range) return;
    text = doc.getText().slice(range[0], range[1]);
  }
  const terminal = ensureRepl(true);
  if (!terminal) return;
  // The REPL reads lines; each line of the form is typed as one.
  terminal.sendText(text.replace(/\r\n/g, '\n').trimEnd(), true);
}

/** The newest of src\*.st, lib\core.lisp and lib\compiler\*.lisp (all built
 * into the image), if newer than the built image. */
function staleSource(root) {
  const image = path.join(root, 'pharo', 'cog-lisp.image');
  if (!fs.existsSync(image)) return { file: null, missing: true };
  const built = fs.statSync(image).mtimeMs;
  const sources = [];
  const src = path.join(root, 'src');
  if (fs.existsSync(src)) {
    for (const name of fs.readdirSync(src)) if (name.endsWith('.st')) sources.push(path.join(src, name));
  }
  sources.push(path.join(root, 'lib', 'core.lisp'));
  const compiler = path.join(root, 'lib', 'compiler');
  if (fs.existsSync(compiler)) {
    for (const name of fs.readdirSync(compiler)) if (name.endsWith('.lisp')) sources.push(path.join(compiler, name));
  }
  let newest = null;
  for (const file of sources) {
    if (!fs.existsSync(file)) continue;
    const t = fs.statSync(file).mtimeMs;
    if (t > built && (!newest || t > newest.t)) newest = { file, t };
  }
  return newest ? { file: newest.file, t: newest.t, missing: false } : { file: null, missing: false };
}

/** Offer to rebuild when the image is missing or older than its sources (review T-3). */
async function checkStale() {
  if (!vscode.workspace.getConfiguration('cogLisp').get('warnStaleImage')) return;
  const root = cogLispRoot();
  if (!root) return;
  const stale = staleSource(root);
  let message;
  if (stale.missing) {
    message = 'cog-lisp: there is no pharo\\cog-lisp.image yet.';
  } else if (stale.file && stale.t > lastStaleWarning) {
    lastStaleWarning = stale.t;
    message = 'cog-lisp: ' + path.relative(root, stale.file) + ' is newer than pharo\\cog-lisp.image, so programs run the old code.';
  } else {
    return;
  }
  const choice = await vscode.window.showWarningMessage(message, 'Rebuild Image');
  if (choice === 'Rebuild Image') rebuildImage();
}

function activate(context) {
  context.subscriptions.push(
    vscode.commands.registerCommand('cog-lisp.runFile', runFile),
    vscode.commands.registerCommand('cog-lisp.startRepl', () => ensureRepl(true)),
    vscode.commands.registerCommand('cog-lisp.sendToRepl', sendToRepl),
    vscode.commands.registerCommand('cog-lisp.rebuildImage', rebuildImage),
    vscode.window.registerTerminalProfileProvider('cog-lisp.repl', {
      provideTerminalProfile() {
        const root = cogLispRoot();
        return root ? new vscode.TerminalProfile(replOptions(root)) : undefined;
      }
    }),
    vscode.window.onDidCloseTerminal((t) => { if (t === replTerminal) replTerminal = null; }),
    vscode.workspace.onDidSaveTextDocument((doc) => {
      const root = cogLispRoot();
      if (!root) return;
      const rel = path.relative(root, doc.uri.fsPath).toLowerCase();
      if ((rel.startsWith('src' + path.sep) && rel.endsWith('.st')) || rel === path.join('lib', 'core.lisp')
          || (rel.startsWith(path.join('lib', 'compiler') + path.sep) && rel.endsWith('.lisp'))) checkStale();
    }),
    vscode.tasks.onDidEndTask((e) => {
      if (e.execution.task.definition.type === 'cog-lisp' && e.execution.task.definition.task === 'build') lastStaleWarning = 0;
    })
  );
  checkStale();
}

function deactivate() {}

module.exports = { activate, deactivate, _test: { staleSource, scriptArgs } };
