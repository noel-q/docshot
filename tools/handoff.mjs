#!/usr/bin/env node
// Deterministic handoff generator. No model, no dependencies. Run from the repo root.
// Usage: node tools/handoff.mjs [--from claude-code] [--to codex] [--run-checks] [--stdout]
//   --stdout      print HANDOFF.md content only, write nothing (safe dry run)
//   --run-checks  run the commands listed in handoff.config.json "checks" and record results
// State file: STATUS.md in Noel's project-system format (Definition of done, Next action, Blocker,
// Human-only tail). Legacy key lines (OBJECTIVE:, GATE:, NEXT:, DO NOT:, BLOCKED:) are also read.
// Optional handoff.config.json: { "state": "STATUS.md", "readFirst": [...],
//   "checks": [{ "name": "tests", "cmd": "node --test" }], "ignore": ["dir"], "recentMinutes": 60 }
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const args = process.argv.slice(2);
const val = (n, d) => { const i = args.indexOf(`--${n}`); return i >= 0 && args[i + 1] && !args[i + 1].startsWith('--') ? args[i + 1] : d; };
const has = (n) => args.includes(`--${n}`);

const root = process.cwd();
const cfgPath = join(root, 'handoff.config.json');
const cfg = existsSync(cfgPath) ? JSON.parse(readFileSync(cfgPath, 'utf8')) : {};
const statePath = cfg.state ?? cfg.current ?? ['STATUS.md', 'docs/CURRENT.md'].find((f) => existsSync(join(root, f))) ?? 'STATUS.md';
const readFirst = cfg.readFirst ?? ['AGENTS.md', statePath, 'HANDOFF.md'];
const recentMin = cfg.recentMinutes ?? 60;
const skip = new Set(['.git', 'node_modules', '.work', 'dist', 'build', '.next', '__pycache__', ...(cfg.ignore ?? [])]);
const from = val('from', 'unknown');
const to = val('to', 'next agent');

const git = (...a) => {
  try { return execFileSync('git', a, { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim(); }
  catch { return null; }
};

const now = new Date();
const london = now.toLocaleString('en-GB', { timeZone: 'Europe/London', dateStyle: 'full', timeStyle: 'short' });

// Git state
const inRepo = git('rev-parse', '--is-inside-work-tree') === 'true';
const branch = inRepo ? git('branch', '--show-current') : null;
const lastCommit = inRepo ? (git('log', '-1', '--format=%h %s (%cr)') ?? 'no commits yet') : null;
const statusLines = inRepo ? (git('status', '--short') ?? '').split('\n').filter(Boolean) : [];

// Recently modified files (ignored folders skipped)
const recent = [];
const cutoff = now.getTime() - recentMin * 60000;
const walk = (dir, depth) => {
  if (depth > 6) return;
  let entries = [];
  try { entries = readdirSync(dir, { withFileTypes: true }); } catch { return; }
  for (const e of entries) {
    if (skip.has(e.name)) continue;
    const p = join(dir, e.name);
    if (e.isDirectory()) walk(p, depth + 1);
    else if (e.isFile()) {
      try { const m = statSync(p).mtimeMs; if (m >= cutoff && e.name !== 'HANDOFF.md') recent.push({ p: relative(root, p), m }); } catch {}
    }
  }
};
walk(root, 0);
recent.sort((a, b) => b.m - a.m);

// Read the state file
const stateFull = join(root, statePath);
const stateText = existsSync(stateFull) ? readFileSync(stateFull, 'utf8') : '';
const stateMtime = existsSync(stateFull) ? statSync(stateFull).mtimeMs : 0;
const lines = stateText.split('\n');
const sections = {};
let cur = '';
for (const l of lines) {
  const h = l.match(/^##\s+(.+?)\s*$/);
  if (h) { cur = h[1].toLowerCase(); sections[cur] = []; continue; }
  if (cur) sections[cur].push(l);
}
// Tolerant: takes bullets or plain paragraph lines under a heading, bullets stripped.
const sec = (prefix) => {
  const k = Object.keys(sections).find((x) => x.startsWith(prefix));
  return k ? sections[k].map((x) => x.trim()).filter((x) => x && !x.startsWith('```')).map((x) => x.replace(/^-\s*/, '')) : [];
};
const clip = (s, n = 220) => (s.length > n ? s.slice(0, n - 1) + '…' : s);
const meta = (name) => (stateText.match(new RegExp(`^-\\s*${name}:\\s*(.+)$`, 'mi')) ?? [])[1]?.trim();
const legacy = (name) => [...stateText.matchAll(new RegExp(`^${name}:\\s*(.+)$`, 'gmi'))].map((m) => m[1].trim());

const nextBullets = sec('next action');
const due = nextBullets.find((x) => /^due:/i.test(x))?.replace(/^due:\s*/i, '');
const next = [...nextBullets.filter((x) => !/^due:/i.test(x)), ...legacy('NEXT')];
const objective = [meta('Definition of done') ?? sec('definition of done').join(' '), ...legacy('OBJECTIVE')].filter(Boolean);
const gate = legacy('GATE');
const blockerRaw = [...sec('blocker'), ...legacy('BLOCKED')];
const blocker = blockerRaw.filter((x) => !/^none\.?$/i.test(x));
const humanOnly = sec('human-only');
const doNot = legacy('DO NOT');
const projStatus = meta('Status');
const lastUpdated = meta('Last updated');

const warnings = [];
if (!stateText) warnings.push(`${statePath} not found. Create it from the STATUS template (Definition of done, Next action, Blocker, Human-only tail).`);
else {
  if (!next.length) warnings.push(`${statePath} has no next action. A handoff without one next action is not usable.`);
  const newestOther = recent.find((r) => r.p !== statePath);
  if (newestOther && stateMtime < newestOther.m - 10 * 60000) warnings.push(`${statePath} is older than the newest changed file (${newestOther.p}). It may be stale: refresh it before handing over.`);
}

// Optional checks
// Prefer test-runner summary lines (pass/fail counts, failing test names); otherwise the last 3 lines.
const summarise = (s) => {
  const ls = s.trim().split('\n');
  const key = ls.filter((l) => /^# (tests|pass|fail)\b|^\s*not ok\b/.test(l)).map((l) => l.trim().slice(0, 160));
  return (key.length ? key.slice(0, 6) : ls.slice(-3)).join(' | ');
};
const checkResults = [];
for (const c of cfg.checks ?? []) {
  if (!has('run-checks')) { checkResults.push({ name: c.name, cmd: c.cmd, status: 'NOT RUN' }); continue; }
  try {
    const out = execFileSync('sh', ['-c', c.cmd], { cwd: root, encoding: 'utf8', timeout: 120000, stdio: ['ignore', 'pipe', 'pipe'] });
    checkResults.push({ name: c.name, cmd: c.cmd, status: 'PASS', tail: summarise(out) });
  } catch (e) {
    const out = summarise(`${e.stdout ?? ''}${e.stderr ?? ''}`);
    checkResults.push({ name: c.name, cmd: c.cmd, status: 'FAIL', tail: out || String(e.message).slice(0, 200) });
  }
}

const L = [];
L.push('# HANDOFF (generated, do not hand-edit)', '');
L.push(`Generated: ${london} (UK time) | ISO ${now.toISOString()}`);
L.push(`From: ${from} | To: ${to} | Active writer after this handoff: ${to}`);
L.push(`Working directory: ${root}`, '');
L.push('## Read first, in this order', ...readFirst.map((f, i) => `${i + 1}. ${f}`), '');
L.push(`## Where the work stands (from ${statePath})`);
if (projStatus) L.push(`- Status: ${projStatus}${lastUpdated ? ` (last updated ${lastUpdated})` : ''}`);
L.push(`- Definition of done / objective: ${clip(objective.join(' ') || 'UNKNOWN', 400)}`);
if (gate.length) L.push(`- Gate: ${gate.join(' ')}`);
L.push(`- Next single action: ${clip(next.join(' ') || 'MISSING', 500)}${due ? ` (due ${due})` : ''}`);
L.push(`- Blocker: ${blocker.join('; ') || 'None'}`);
for (const h of humanOnly.slice(0, 5)) L.push(`- Human-only: ${clip(h)}`);
if (humanOnly.length > 5) L.push(`- Human-only: ...and ${humanOnly.length - 5} more in ${statePath}`);
for (const d of doNot) L.push(`- Do not: ${d}`);
L.push('');
L.push('## Git (verified by this script just now)');
if (!inRepo) L.push('- Not a git repository.');
else {
  L.push(`- Branch: ${branch || 'detached'} | Last commit: ${lastCommit}`);
  L.push(`- Uncommitted entries: ${statusLines.length}`);
  for (const s of statusLines.slice(0, 20)) L.push(`  - ${s}`);
  if (statusLines.length > 20) L.push(`  - ...and ${statusLines.length - 20} more`);
}
L.push('');
L.push(`## Files changed in the last ${recentMin} minutes (verified)`);
if (!recent.length) L.push('- None.');
for (const r of recent.slice(0, 20)) L.push(`- ${r.p} (${Math.round((now.getTime() - r.m) / 60000)} min ago)`);
if (recent.length > 20) L.push(`- ...and ${recent.length - 20} more`);
L.push('');
L.push('## Checks');
if (!checkResults.length) L.push('- None configured. Add "checks" to handoff.config.json.');
for (const c of checkResults) L.push(`- ${c.name}: ${c.status} (\`${c.cmd}\`)${c.tail ? ` ${c.tail}` : ''}`);
L.push('');
L.push('## Rules for the receiving agent');
L.push('- A handoff moves text and file evidence, not hidden state or permissions. Re-run the checks above before relying on anything here.');
L.push('- Label every claim verified, inherited, assumed, proposed or unknown. Never say a command ran without evidence.');
L.push('- One writer at a time. Do not edit files another agent is changing. Do not commit, push, deploy or spend without explicit authority.');
L.push(`- Finish by updating ${statePath} (and the session log if the project uses one), then run this script again.`);
if (warnings.length) { L.push('', '## Warnings', ...warnings.map((w) => `- ${w}`)); }
const doc = L.join('\n') + '\n';

if (has('stdout')) { process.stdout.write(doc); process.exit(warnings.length ? 2 : 0); }
writeFileSync(join(root, 'HANDOFF.md'), doc);

const prompt = [
  `You are taking over from ${from}. Work in ${root}.`,
  `Read, in order: ${readFirst.join(', ')}.`,
  'Re-run the listed checks before trusting anything in the handoff.',
  `Do this one action only: ${next.join(' ') || '(none recorded, ask Noel)'}`,
  ...doNot.map((d) => `Do not: ${d}`),
  "Follow the rules in AGENTS.md. Do not commit, push, deploy or spend without Noel's explicit approval.",
  `When the unit is done, update ${statePath}, run the handoff script again, then stop.`,
].join('\n');
console.log(`Wrote ${join(root, 'HANDOFF.md')}${warnings.length ? ' with warnings' : ''}\n\n--- paste-ready prompt ---\n${prompt}`);
process.exit(warnings.length ? 2 : 0);
