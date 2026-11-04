// Finding top-level forms in cog-lisp source, for "send form to REPL".
// The only LISP knowledge in the extension besides the grammar: enough of the
// reader's lexical rules (src/coglisp-reader.st) to match parentheses, skipping
// strings, comments, block comments and character literals.
'use strict';

const DELIMITERS = new Set([' ', '\t', '\r', '\n', '\f', '(', ')', '[', ']', '"', ';', "'", '`', ',']);

/**
 * The top-level datums of text, as [start, end) offsets. A quote prefix
 * (' ` , ,@) belongs to the datum after it. An unterminated last datum runs to
 * the end of the text.
 */
function topLevelForms(text) {
  const forms = [];
  let i = 0;
  let depth = 0;
  let start = -1;
  const n = text.length;
  const close = (end) => {
    if (depth === 0 && start >= 0) {
      forms.push([start, end]);
      start = -1;
    }
  };
  while (i < n) {
    const c = text[i];
    if (c === ';') {
      while (i < n && text[i] !== '\n') i++;
      continue;
    }
    if (c === '#' && text[i + 1] === '|') {
      let nest = 1;
      i += 2;
      while (i < n && nest > 0) {
        if (text[i] === '#' && text[i + 1] === '|') { nest++; i += 2; }
        else if (text[i] === '|' && text[i + 1] === '#') { nest--; i += 2; }
        else i++;
      }
      continue;
    }
    if (/\s/.test(c)) { i++; continue; }
    if (depth === 0 && start < 0) start = i;
    if (c === "'" || c === '`') { i++; continue; }
    if (c === ',') { i += text[i + 1] === '@' ? 2 : 1; continue; }
    // #( starts a vector (Phase 7.8)
    if (c === '#' && text[i + 1] === '(') { depth++; i += 2; continue; }
    // [ ] (Smalltalk sends, Phase 7.6) nest like ( )
    if (c === '(' || c === '[') { depth++; i++; continue; }
    if (c === ')' || c === ']') {
      i++;
      if (depth > 0) depth--;
      close(i);
      continue;
    }
    if (c === '"') {
      i++;
      while (i < n && text[i] !== '"') i += text[i] === '\\' ? 2 : 1;
      i = Math.min(i + 1, n);
      close(i);
      continue;
    }
    if (c === '#' && text[i + 1] === '\\') {
      i += 3; // #\ and the character itself, which may be a delimiter: #\(
      while (i < n && !DELIMITERS.has(text[i])) i++;
      close(i);
      continue;
    }
    while (i < n && !DELIMITERS.has(text[i]) && !(text[i] === '#' && text[i + 1] === '|')) i++;
    close(i);
  }
  if (start >= 0) forms.push([start, n]);
  return forms;
}

/**
 * The top-level form to send for a cursor at offset: the one containing it;
 * else the last one ending before it on the cursor's line or earlier (the cursor
 * just after a form); else the first one after it. null if the text has none.
 */
function topLevelFormAt(text, offset) {
  const forms = topLevelForms(text);
  if (forms.length === 0) return null;
  const inside = forms.find(([s, e]) => s <= offset && offset < e);
  if (inside) return inside;
  const before = forms.filter(([, e]) => e <= offset);
  if (before.length > 0) return before[before.length - 1];
  return forms[0];
}

module.exports = { topLevelForms, topLevelFormAt };
