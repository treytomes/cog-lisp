// Hover help and completion for cog-lisp's built-ins, offline
// (specs/phase-10-documentation-and-editor.md step 10.3). The data is
// builtins.json, generated from the documentation kept in the image
// (tools/generate-docs.lisp) and checked against it by the suites, so nothing
// about the language is written here by hand.
'use strict';

const fs = require('fs');

// what ends a symbol, as the reader sees it (language-configuration.json's wordPattern)
const DELIMITERS = new Set([' ', '\t', '\r', '\n', '\f', '(', ')', '[', ']', '"', ';', "'", '`', ',']);

/** The built-ins, name -> { call, kind, category, description }, from a builtins.json. */
function loadBuiltins(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

/** The symbol of lineText around index character, or null. */
function symbolAt(lineText, character) {
  let start = character;
  let end = character;
  while (start > 0 && !DELIMITERS.has(lineText[start - 1])) start--;
  while (end < lineText.length && !DELIMITERS.has(lineText[end])) end++;
  if (start === end) return null;
  return { name: lineText.slice(start, end), start, end };
}

/** Markdown for hovering over a built-in: its call form, what it does, its kind. */
function hoverMarkdown(name, entry) {
  return '```cog-lisp\n' + entry.call + '\n```\n\n' + entry.description +
    '\n\n*' + entry.kind + ' · ' + entry.category + '*';
}

/** The names that start with prefix, sorted. */
function completions(builtins, prefix) {
  return Object.keys(builtins).filter((n) => n.startsWith(prefix)).sort();
}

module.exports = { loadBuiltins, symbolAt, hoverMarkdown, completions };
