// skill-eval.js -- measure the agent skill (specs/phase-10-documentation-and-
// editor.md step 10.7): the same small tasks, asked of a model with and without
// .agents/skills/cog-lisp/SKILL.md, each answer run by cog-lisp and its output
// compared. Node, no dependencies; talks to an OpenAI-compatible server, such as
// LM Studio's (which also serves models reached through Bionic's private link).
//
//   node tools/skill-eval.js --model <id> [--url http://localhost:1234/v1]
//        [--attempts 2] [--repeat 1] [--max-tokens 8192] [--out results.json]
//   node tools/skill-eval.js --list      the models the server offers
//   node tools/skill-eval.js --dry-run   each task's own solution as the answer:
//                                        checks the tasks and the runner, no model
//
// Each task gets up to --attempts answers: after a wrong one the model is shown
// what happened (the output, or the error line) and asked again, as the skill's
// loop tells an agent to work. A model's reasoning (<think>...</think>) is
// dropped; the program is the last ```scheme (or ```lisp) block of the answer.
// Programs run on a copy of the image, beside anything else using it.
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const cp = require('child_process');

const root = path.join(__dirname, '..');
const windows = process.platform === 'win32';

function option(name, fallback) {
  const i = process.argv.indexOf('--' + name);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : fallback;
}
const flag = (name) => process.argv.includes('--' + name);

const url = option('url', 'http://localhost:1234/v1').replace(/\/$/, '');
const attempts = Number(option('attempts', '2'));
const repeat = Number(option('repeat', '1'));
// a cap on each answer, reasoning included, so a runaway answer cannot fill the context
const maxTokens = Number(option('max-tokens', '8192'));
const tasks = JSON.parse(fs.readFileSync(path.join(__dirname, 'skill-eval-tasks.json'), 'utf8'));
const skill = fs.readFileSync(path.join(root, '.agents', 'skills', 'cog-lisp', 'SKILL.md'), 'utf8');

const BASE_PROMPT =
  'You write programs in cog-lisp. Answer with the complete program in one ```scheme code block. ' +
  'The program is run with the cog-lisp launcher and its printed output is checked.';
const WITH_SKILL = BASE_PROMPT + '\n\nThe cog-lisp skill:\n\n' + skill;

// --- running a program ------------------------------------------------------
const work = fs.mkdtempSync(path.join(os.tmpdir(), 'cog-lisp-skill-eval-'));
const image = path.join(work, 'cog-lisp.image');
for (const f of ['cog-lisp.image', 'cog-lisp.changes']) fs.copyFileSync(path.join(root, 'pharo', f), path.join(work, f));

let counter = 0;
function runProgram(source) {
  const file = path.join(work, 'answer-' + (++counter) + '.lisp');
  fs.writeFileSync(file, source);
  const env = Object.assign({}, process.env, { COGLISP_IMAGE: image });
  const r = windows
    ? cp.spawnSync('cmd.exe', ['/d', '/c', '.\\cog-lisp.bat', file], { cwd: root, env, encoding: 'utf8', input: '', timeout: 60000 })
    : cp.spawnSync('./cog-lisp.sh', [file], { cwd: root, env, encoding: 'utf8', input: '', timeout: 60000 });
  return { status: r.status, stdout: (r.stdout || '').replace(/\r\n/g, '\n'), stderr: (r.stderr || '').replace(/\r\n/g, '\n') };
}
const same = (out, expected) => out.trim() === expected.trim();

// --- asking the model ---------------------------------------------------------
async function models() {
  const r = await fetch(url + '/models');
  if (!r.ok) throw new Error('GET ' + url + '/models: ' + r.status);
  return (await r.json()).data.map((m) => m.id);
}

async function ask(model, messages) {
  const r = await fetch(url + '/chat/completions', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model, messages, temperature: 0.2, max_tokens: maxTokens }),
    signal: AbortSignal.timeout(10 * 60 * 1000),
  });
  if (!r.ok) throw new Error('POST ' + url + '/chat/completions: ' + r.status + ' ' + (await r.text()).slice(0, 300));
  const body = await r.json();
  return body.choices[0].message.content || '';
}

function programIn(answer) {
  const text = answer.replace(/<think>[\s\S]*?<\/think>/g, '');
  const blocks = [...text.matchAll(/```(?:scheme|lisp|racket)?[^\n]*\n([\s\S]*?)```/g)].map((m) => m[1]);
  return blocks.length ? blocks[blocks.length - 1] : text.trim();
}

function feedback(run, expected) {
  if (run.status !== 0) {
    const line = run.stderr.split('\n').find((l) => l.includes('error:')) || run.stderr.trim().split('\n')[0] || 'exit code ' + run.status;
    return 'The program failed:\n' + line.replace(/^.*?(\d+:\d+: error:)/, 'program.lisp:$1') + '\nIt printed:\n' + run.stdout +
      '\nFix it. Answer with the complete program in one ```scheme code block.';
  }
  return 'The program printed:\n' + run.stdout + '\nIt should print:\n' + expected +
    '\nFix it. Answer with the complete program in one ```scheme code block.';
}

// one task under one condition: the attempt that passed (1, 2, ...), or 0
async function attemptTask(model, task, system) {
  const messages = [{ role: 'system', content: system }, { role: 'user', content: task.prompt }];
  for (let a = 1; a <= attempts; a++) {
    let answer;
    try {
      answer = model ? await ask(model, messages) : task.solution;
    } catch (e) {
      // the server refused (the context filled, say): this attempt failed, the run goes on
      return { passed: 0, program: '', run: { status: -1, stdout: '', stderr: 'error: the server: ' + e.message.slice(0, 200) } };
    }
    const program = model ? programIn(answer) : answer;
    const run = runProgram(program);
    if (run.status === 0 && same(run.stdout, task.expected)) return { passed: a, program };
    if (!model) return { passed: 0, program, run };
    messages.push({ role: 'assistant', content: answer }, { role: 'user', content: feedback(run, task.expected) });
    if (a === attempts) return { passed: 0, program, run };
  }
  return { passed: 0 };
}

async function main() {
  try {
    if (flag('list')) { (await models()).forEach((m) => console.log(m)); return 0; }
    const dry = flag('dry-run');
    const model = dry ? null : option('model', null);
    if (!dry && !model) {
      console.log('usage: node tools/skill-eval.js --model <id> [--url ' + url + ']   (--list shows the ids)');
      return 2;
    }
    console.log('== cog-lisp skill evaluation: ' + (dry ? 'dry run (the tasks\' own solutions)' : model + ' at ' + url) +
      ', ' + tasks.length + ' tasks, up to ' + attempts + ' attempts, ' + repeat + ' run(s) each ==');
    const conditions = dry ? [['solutions', BASE_PROMPT]] : [['without the skill', BASE_PROMPT], ['with the skill', WITH_SKILL]];
    const results = { model, url, attempts, repeat, date: new Date().toISOString(), conditions: {} };
    for (const [label, system] of conditions) {
      const rows = [];
      for (const task of tasks) {
        for (let r = 0; r < repeat; r++) {
          const t0 = Date.now();
          const outcome = await attemptTask(model, task, system);
          rows.push({ task: task.name, passed: outcome.passed, seconds: Math.round((Date.now() - t0) / 1000), program: outcome.program,
                      error: outcome.run && outcome.run.status !== 0 ? (outcome.run.stderr.split('\n').find((l) => l.includes('error:')) || '') : undefined });
          console.log('  ' + (outcome.passed ? 'PASS' : 'FAIL') + '  [' + label + '] ' + task.name +
            (outcome.passed > 1 ? ' (attempt ' + outcome.passed + ')' : '') +
            (!outcome.passed && outcome.run ? ': ' + (outcome.run.status !== 0 ? (outcome.run.stderr.split('\n').find((l) => l.includes('error:')) || 'exit ' + outcome.run.status).replace(/^.*?error:/, 'error:') : 'printed ' + JSON.stringify(outcome.run.stdout.trim().slice(0, 60))) : ''));
        }
      }
      const first = rows.filter((x) => x.passed === 1).length;
      const any = rows.filter((x) => x.passed > 0).length;
      results.conditions[label] = { first, any, total: rows.length, rows };
      if (option('out', null)) fs.writeFileSync(option('out', null), JSON.stringify(results, null, 2));
    }
    console.log('');
    for (const [label, c] of Object.entries(results.conditions)) {
      console.log('  ' + label + ': ' + c.first + '/' + c.total + ' on the first attempt, ' + c.any + '/' + c.total + ' within ' + attempts);
    }
    const out = option('out', null);
    if (out) { fs.writeFileSync(out, JSON.stringify(results, null, 2)); console.log('  results written to ' + out); }
    if (dry) {
      const c = results.conditions.solutions;
      console.log('== RESULT: ' + c.any + '/' + c.total + ' task solutions pass ==');
      return c.any === c.total ? 0 : 1;
    }
    return 0;
  } finally {
    try { fs.rmSync(work, { recursive: true, force: true }); } catch (e) { /* the VM may still hold it */ }
  }
}

main().then((code) => process.exit(code), (e) => { console.log('error: ' + e.message); process.exit(1); });
