// cog-lisp's names in Code Spell Checker (specs/25-vscode-spelling.md R-3).
// cSpell has no package.json contribution point for dictionaries: an extension
// activates cSpell and hands its API the path of a cspell-ext.json, as cSpell's
// own dictionary extensions do. cSpell is never required: if it is missing,
// inactive or fails, nothing else changes, and a failure is only logged.
'use strict';

const path = require('path');

const CSPELL_ID = 'streetsidesoftware.code-spell-checker';

/**
 * Registers cspell/cspell-ext.json with cSpell, if it is installed. Answers
 * true when cSpell took it. vscodeApi and log are parameters so a test can
 * stand in for VS Code.
 */
async function registerSpelling(context, vscodeApi, log) {
  const extension = vscodeApi.extensions.getExtension(CSPELL_ID);
  if (!extension) return false;
  try {
    const api = await extension.activate();
    if (!api || typeof api.registerConfig !== 'function') {
      log('cog-lisp: Code Spell Checker has no registerConfig; its dictionary is not registered');
      return false;
    }
    await api.registerConfig(context.asAbsolutePath(path.join('cspell', 'cspell-ext.json')));
    return true;
  } catch (e) {
    log('cog-lisp: registering the dictionary with Code Spell Checker failed: ' + (e && e.message ? e.message : e));
    return false;
  }
}

module.exports = { registerSpelling, CSPELL_ID };
