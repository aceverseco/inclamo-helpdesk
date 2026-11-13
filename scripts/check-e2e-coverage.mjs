// Every scenario of the specs has an end-to-end test named after it. This
// check reads the scenarios from the spec files and the test titles from
// e2e/tests, and fails when a scenario has no test or a test names a scenario
// that does not exist.
//
// Contracts ship with this source revision and do not require internal plans.
//
//   node scripts/check-e2e-coverage.mjs [directory with <capability>/spec.md]
//   E2E_COVERAGE_ROOT=<dir> overrides the repository root (used to try the check itself)
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = process.env.E2E_COVERAGE_ROOT || join(dirname(fileURLToPath(import.meta.url)), '..');
const specsDirs = [process.argv[2] || join(root, 'docs', 'behavior')];
for (const directory of specsDirs) {
  if (!existsSync(directory)) throw new Error(`Behavior contracts are missing: ${directory}`);
}

// Which test file carries which capability; a file may be flat (tests named
// after scenarios) or grouped by requirement (describe blocks).
const FILES = {
  'workspace-widgets': ['workspace-widgets.spec.mjs'],
  'in-product-support': ['in-product-support.spec.mjs'],
  'inclamo-product-design': ['inclamo-product-design.spec.mjs'],
  'helpdesk-visual-theme': ['dashboard-theme.spec.mjs'],
  'website-widget-experience': ['website-widget-experience.spec.mjs'],
  'website-widget-settings': ['website-widget-settings.spec.mjs'],
  'workspace-brand-logo': ['workspace-brand-logo.spec.mjs'],
  'shopify-connection': ['shopify-connection.spec.mjs'],
  'conversation-order-panel': ['order-panel-reading.spec.mjs', 'order-panel-actions.spec.mjs'],
  'reply-order-variables': ['reply-order-variables.spec.mjs'],
  'store-data-rules': ['store-data-rules.spec.mjs'],
  'order-tags-and-notes': ['order-tags-and-notes.spec.mjs'],
  'order-creation': ['order-creation.spec.mjs'],
  'macro-order-actions': ['macro-order-actions.spec.mjs'],
  'order-item-editing': ['order-item-editing.spec.mjs'],
  'reply-inserts': ['reply-inserts.spec.mjs'],
  'sla-timers': ['sla-timers.spec.mjs'],
  'sla-badge': ['sla-badge.spec.mjs'],
  'sla-urgency-widget': ['sla-urgency-widget.spec.mjs'],
  'ai-agent-connection': ['ai-agent-connection.spec.mjs'],
  'call-conversations': ['call-conversations.spec.mjs'],
  'ai-order-authority': ['ai-order-authority.spec.mjs'],
  'ai-reply-ownership': ['ai-reply-ownership.spec.mjs'],
  'staff-action-permissions': ['staff-action-permissions.spec.mjs'],
  'helpdesk-onboarding': ['helpdesk-onboarding.spec.mjs'],
  'acceptance-ux-corrections': ['acceptance-ux-corrections.spec.mjs'],
  'team-queues': ['team-queues.spec.mjs'],
  'ready-replies': ['ready-replies.spec.mjs'],
};

// Scenarios that cannot run against the installation the tests drive, each
// with where it is covered instead.
const ELSEWHERE = {
  'team-queues › Ready queues exist for every account › A new account has the ready queues':
    'needs a new account; covered by custom/spec/lib/inclamo/presets_spec.rb (an account gets the eight queues when it is created)',
  'team-queues › Ready queues exist for every account › An existing account gets the ready queues on upgrade':
    'needs an upgrade of an installation with accounts; covered by custom/spec/lib/inclamo/presets_spec.rb, which runs the install migration itself on an account without queues',
  "sla-urgency-widget › The widget counts each queue's conversations by SLA urgency › Conversation in two queues":
    'the totals of the test installation move with every other file; covered by custom/spec/requests/api/v1/accounts/inclamo/team_queue_sla_overview_spec.rb ("totals each conversation once") and, for the header showing the totals, by the end-to-end test "Mixed queue"',
  'team-queues › Queues work without the AI subscription › Account without an AI agent':
    'the test installation keeps its AI agent connected for other files; covered by custom/spec/requests/api/v1/accounts/inclamo/team_queues_spec.rb ("an account with no AI agent connected")',
  'team-queues › Installing the ready queues is repeatable › Second installation changes nothing':
    'needs the installer to run again at a chosen moment (it runs again on upgrade and whenever the repair job finds an account incomplete); covered by custom/spec/lib/inclamo/presets_spec.rb',
  'ready-replies › Ready saved replies exist for the support categories › Agent inserts the delivery reply':
    'the browser path of a saved reply with order variables is shown by reply-order-variables; the ready text itself is covered by custom/spec/requests/api/v1/accounts/inclamo/ready_replies_spec.rb on a tied, shipped order',
  'ready-replies › Installing the ready replies is repeatable › Edited reply is kept':
    'needs the installer to run again at a chosen moment (it runs again on upgrade and whenever the repair job finds an account incomplete); covered by custom/spec/lib/inclamo/presets_spec.rb',
  'ready-replies › Installing the ready replies is repeatable › Deleted reply stays deleted':
    'needs the installer to run again at a chosen moment (it runs again on upgrade and whenever the repair job finds an account incomplete); covered by custom/spec/lib/inclamo/presets_spec.rb',
  'ready-replies › Installing the ready replies is repeatable › Short code already taken':
    'needs the installer to run again at a chosen moment (it runs again on upgrade and whenever the repair job finds an account incomplete); covered by custom/spec/lib/inclamo/presets_spec.rb',
  "ai-reply-ownership › The agent's protected reply is posted only while the conversation is the agent's › Take-over and reply at the same moment":
    'needs two database transactions at the same instant; covered by custom/spec/lib/inclamo/ai/protected_reply_ordering_spec.rb on two connections',
  "call-conversations › The call lands on the caller's contact › Two contacts share the number":
    "Chatwoot's API refuses a second contact with a number another holds, so the tests cannot make two; covered by custom/spec/requests/api/v1/accounts/inclamo/ai_calls_spec.rb on rows written past that check",
  'meta-page-connection › Page connection requests Instagram messaging permissions › First-time client connects a Page with a linked Instagram account':
    'the permission set requested is covered by shims/app/javascript/dashboard/inclamo/specs/MetaPageConnectScopes.spec.js; receiving and answering Instagram direct messages needs a real Meta login, which the tests cannot perform; no automated test covers it, and it is checked by hand on a live instance before release',
  'meta-page-connection › Page connection requests Instagram messaging permissions › Connection from the onboarding form':
    'the test installation has no Meta app, so the form cannot start the login; covered by shims/app/javascript/dashboard/inclamo/specs/MetaPageConnectScopes.spec.js (the settings screen and the onboarding form take the login from one flow, and that flow requests the Page and Instagram permissions)',
  'meta-page-connection › Messenger works without Instagram › Administrator declines the Instagram permissions':
    "declining permissions in Meta's dialog and Messenger delivery need a real Meta login, which the tests cannot perform; no automated test covers them, and they are checked by hand on a live instance before release",
  'meta-page-connection › Messenger works without Instagram › Page without Instagram':
    'connecting a real Page and Messenger delivery need a real Meta login, which the tests cannot perform; no automated test covers them, and they are checked by hand on a live instance before release',
  'meta-page-connection › Reauthorization requests the same permissions as connection › Instagram added after the first connection':
    'the permission set requested is covered by shims/app/javascript/dashboard/inclamo/specs/MetaPageConnectScopes.spec.js (reauthorizing requests the same set as connecting, with or without a stored Instagram account); Instagram messages arriving afterwards need a real Meta login, which the tests cannot perform; no automated test covers them, and they are checked by hand on a live instance before release',
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

if (scenarios.length === 0) throw new Error('No behavior scenarios found');

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

if (problems.length > 0) {
  console.error(problems.join('\n'));
  process.exit(1);
}
const covered = scenarios.length - Object.keys(ELSEWHERE).length;
console.log(`${covered} of ${scenarios.length} scenarios have an end-to-end test; ${Object.keys(ELSEWHERE).length} covered elsewhere, with the reason on record`);
