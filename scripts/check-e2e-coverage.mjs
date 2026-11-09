// Every scenario of the specs has an end-to-end test named after it. This
// check reads the scenarios from the spec files and the test titles from
// e2e/tests, and fails when a scenario has no test or a test names a scenario
// that does not exist.
//
// A change counts from its first ticked task: one that is only proposed has
// no code to test yet. The changes left out are printed.
//
//   node scripts/check-e2e-coverage.mjs [directory with specs/<capability>/spec.md]
//   E2E_COVERAGE_ROOT=<dir> overrides the repository root (used to try the check itself)
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = process.env.E2E_COVERAGE_ROOT || join(dirname(fileURLToPath(import.meta.url)), '..');
const changes = join(root, 'openspec', 'changes');
const started = name => {
  const tasks = join(changes, name, 'tasks.md');
  return existsSync(tasks) && /^\s*- \[x\] /im.test(readFileSync(tasks, 'utf8'));
};
const proposed = existsSync(changes) ? readdirSync(changes).filter(name => name !== 'archive' && existsSync(join(changes, name, 'specs'))) : [];
const skipped = process.argv[2] ? [] : proposed.filter(name => !started(name));
const specsDirs = process.argv[2]
  ? [process.argv[2]]
  : [join(root, 'openspec', 'specs'), ...proposed.filter(started).map(name => join(changes, name, 'specs'))].filter(existsSync);

// Which test file carries which capability; a file may be flat (tests named
// after scenarios) or grouped by requirement (describe blocks).
const FILES = {
  'shopify-connection': ['shopify-connection.spec.mjs'],
  'conversation-order-panel': ['order-panel-reading.spec.mjs', 'order-panel-actions.spec.mjs'],
  'reply-order-variables': ['reply-order-variables.spec.mjs'],
  'store-data-rules': ['store-data-rules.spec.mjs'],
  'order-tags-and-notes': ['order-tags-and-notes.spec.mjs'],
  'order-creation': ['order-creation.spec.mjs'],
  'macro-order-actions': ['macro-order-actions.spec.mjs'],
  'order-item-editing': ['order-item-editing.spec.mjs'],
  'reply-inserts': ['reply-inserts.spec.mjs'],
};

// Scenarios that cannot run against the installation the tests drive, each
// with where it is covered instead.
const ELSEWHERE = {
  'shopify-connection › The credentials are a secret › Installation without encryption keys':
    'needs an installation without encryption keys; covered by the request spec and the component test',
};

const scenarios = [];
for (const dir of specsDirs) {
  for (const capability of readdirSync(dir)) {
    const file = join(dir, capability, 'spec.md');
    if (!existsSync(file)) continue;
    let requirement = null;
    for (const line of readFileSync(file, 'utf8').split('\n')) {
      const req = line.match(/^### Requirement: (.+)$/);
      const scenario = line.match(/^#### Scenario: (.+)$/);
      if (req) requirement = req[1].trim();
      if (scenario) scenarios.push({ capability, requirement, scenario: scenario[1].trim() });
    }
  }
}

const tests = {};
for (const [capability, files] of Object.entries(FILES)) {
  tests[capability] = [];
  for (const name of files) {
    let requirement = null;
    for (const line of readFileSync(join(root, 'e2e', 'tests', name), 'utf8').split('\n')) {
      const describe = line.match(/^test\.describe\((['"`])(.+)\1,/);
      const test = line.match(/^\s*test\((['"`])(.+?)\1,/);
      if (describe) requirement = describe[2];
      else if (/^\}\);/.test(line)) requirement = null;
      if (test) tests[capability].push({ requirement, scenario: test[2], file: name });
    }
  }
}

const problems = [];
const key = entry => `${entry.capability} › ${entry.requirement} › ${entry.scenario}`;
for (const entry of scenarios) {
  if (ELSEWHERE[key(entry)]) continue;
  const found = (tests[entry.capability] || []).filter(test => test.scenario === entry.scenario && (test.requirement === null || test.requirement === entry.requirement));
  if (found.length === 0) problems.push(`no end-to-end test for: ${key(entry)}`);
  if (found.length > 1) problems.push(`more than one end-to-end test for: ${key(entry)}`);
}
for (const [capability, list] of Object.entries(tests)) {
  for (const test of list) {
    const known = scenarios.some(entry => entry.capability === capability && entry.scenario === test.scenario && (test.requirement === null || test.requirement === entry.requirement));
    if (!known) problems.push(`${test.file}: test "${test.requirement ? `${test.requirement} › ` : ''}${test.scenario}" names no scenario of ${capability}`);
  }
}
for (const name of Object.keys(ELSEWHERE)) {
  if (!scenarios.some(entry => key(entry) === name)) problems.push(`the exception "${name}" names no scenario`);
}

if (skipped.length > 0) console.log(`not started, left out: ${skipped.join(', ')}`);
if (problems.length > 0) {
  console.error(problems.join('\n'));
  process.exit(1);
}
const covered = scenarios.length - Object.keys(ELSEWHERE).length;
console.log(`${covered} of ${scenarios.length} scenarios have an end-to-end test; ${Object.keys(ELSEWHERE).length} covered elsewhere, with the reason on record`);
