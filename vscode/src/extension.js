// cog-lisp for VS Code (specs/phase-7.5-review-and-tooling.md section 5).
// Deliberately thin: highlighting and brackets are declarative (package.json,
// the grammar, language-configuration.json); this file only adds commands that
// call the repo's own scripts, so the editor runs exactly what the terminal runs.
// The language intelligence is cog-lisp's own language server, lib/lsp.lisp,
// served by the image (Phase 10 step 10.5): hover, completion, go to definition,
// diagnostics and macro expansion. Without it (no cog-lisp folder, the setting
// off, or the server stopped), hover and completion of the built-ins come from
// builtins.json, generated from the image's documentation (step 10.3;
// src/builtins.js).
'use strict';

const vscode = require('vscode');
const fs = require('fs');
const path = require('path');
const { topLevelFormAt } = require('./forms');
const { loadBuiltins, symbolAt, hoverMarkdown, completions } = require('./builtins');
const cp = require('child_process');
const lc = require('vscode-languageclient/node');

// the language server's client, while it serves; the offline help steps aside then
let client = null;
let serverActive = false;

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

// Hover and completion for the built-ins, from the generated builtins.json
function registerBuiltins(context) {
  let builtins = {};
  try {
    builtins = loadBuiltins(path.join(context.extensionPath, 'builtins.json'));
  } catch (e) {
    return;   // without the data, no help: nothing else depends on it
  }
  context.subscriptions.push(
    vscode.languages.registerHoverProvider('cog-lisp', {
      provideHover(document, position) {
        if (serverActive) return undefined;
        const found = symbolAt(document.lineAt(position.line).text, position.character);
        if (!found || !Object.prototype.hasOwnProperty.call(builtins, found.name)) return undefined;
        const range = new vscode.Range(position.line, found.start, position.line, found.end);
        return new vscode.Hover(new vscode.MarkdownString(hoverMarkdown(found.name, builtins[found.name])), range);
      }
    }),
    vscode.languages.registerCompletionItemProvider('cog-lisp', {
      provideCompletionItems(document, position) {
        if (serverActive) return undefined;
        const found = symbolAt(document.lineAt(position.line).text, position.character);
        const prefix = found ? document.lineAt(position.line).text.slice(found.start, position.character) : '';
        return completions(builtins, prefix).map((name) => {
          const entry = builtins[name];
          const item = new vscode.CompletionItem(name,
            entry.kind === 'procedure' ? vscode.CompletionItemKind.Function : vscode.CompletionItemKind.Keyword);
          item.detail = entry.call;
          item.documentation = new vscode.MarkdownString(entry.description);
          return item;
        });
      }
    })
  );
}

// Start lib/lsp.lisp with the workspace's launcher, as Run File runs programs
async function startLanguageServer(context) {
  if (!vscode.workspace.getConfiguration('cogLisp').get('languageServer', true)) return;
  const root = SUPPORTED ? cogLispRoot() : null;
  if (!root || !fs.existsSync(path.join(root, 'lib', 'lsp.lisp'))) return;
  const serverOptions = () => Promise.resolve(WINDOWS
    ? cp.spawn('cmd.exe', ['/d', '/c', '.\\' + script('cog-lisp'), 'lib\\lsp.lisp'], { cwd: root })
    : cp.spawn('./' + script('cog-lisp'), ['lib/lsp.lisp'], { cwd: root }));
  let told = false;
  const clientOptions = {
    documentSelector: [{ language: 'cog-lisp' }],
    outputChannelName: 'cog-lisp language server',
    errorHandler: {
      error: () => ({ action: lc.ErrorAction.Continue }),
      closed: () => {
        serverActive = false;
        if (!told) {
          told = true;
          vscode.window.showWarningMessage('cog-lisp: the language server stopped; hover and completion of the built-ins go on without it.');
        }
        return { action: lc.CloseAction.DoNotRestart, handled: true };
      }
    }
  };
  client = new lc.LanguageClient('cogLisp', 'cog-lisp language server', serverOptions, clientOptions);
  try {
    await client.start();
    serverActive = true;
  } catch (e) {
    serverActive = false;
    client = null;
  }
}

// cog-lisp: Expand Macro -- the server expands the macro call at the cursor
async function expandMacro() {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;
  if (!client || !serverActive) {
    vscode.window.showInformationMessage('cog-lisp: Expand Macro needs the language server (a cog-lisp folder, and cogLisp.languageServer on).');
    return;
  }
  const answer = await client.sendRequest('cog-lisp/expand', {
    textDocument: { uri: editor.document.uri.toString() },
    position: { line: editor.selection.active.line, character: editor.selection.active.character }
  });
  if (!answer) {
    vscode.window.showInformationMessage('cog-lisp: no macro call at the cursor.');
    return;
  }
  const doc = await vscode.workspace.openTextDocument({
    language: 'cog-lisp',
    content: ';; ' + answer.form.split('\n').join('\n;; ') + '\n;; expands to\n' + answer.expansion + '\n'
  });
  await vscode.window.showTextDocument(doc, { preview: true, viewColumn: vscode.ViewColumn.Beside });
}

function activate(context) {
  registerBuiltins(context);
  context.subscriptions.push(vscode.commands.registerCommand('cog-lisp.expandMacro', expandMacro));
  startLanguageServer(context);
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

function deactivate() { return client ? client.stop() : undefined; }

module.exports = { activate, deactivate, _test: { staleSource, scriptArgs, serverActive: () => serverActive } };
