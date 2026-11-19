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
  'instance-installation': ['instance-installation.spec.mjs'],
  'interface-language': ['interface-language.spec.mjs'],
  'app-provisioned-account': ['app-provisioned-account.spec.mjs'],
  'app-storefront-chat': ['app-storefront-chat.spec.mjs'],
  'app-agent-auto-connection': ['app-agent-auto-connection.spec.mjs'],
  'app-store-access': ['app-store-access.spec.mjs'],
  'app-store-erasure': ['app-store-erasure.spec.mjs'],
};

// Scenarios that cannot run against the installation the tests drive, each
// with where it is covered instead.
const ELSEWHERE = {
  "app-provisioned-account › A new administrator can set a password of their own › The link's time has passed":
    "the link lives for hours (Devise's reset_password_within) and the tests cannot move the installation's clock; covered by custom/spec/requests/inclamo/provisioning/account_spec.rb, which travels past that time",
  'app-provisioned-account › Requests are limited › Too many requests':
    'the limits are Rack::Attack rules and the test installation runs with ENABLE_RACK_ATTACK=false, as every other file needs; covered by custom/spec/requests/inclamo/provisioning/limits_spec.rb',
  'app-provisioned-account › Every provisioning attempt is recorded without personal data › A refused request is recorded':
    'the record is a table no address or page shows; covered by custom/spec/requests/inclamo/provisioning/events_spec.rb',
  "app-store-access › The key is a secret › An installation without the app's address":
    "needs an installation with the shared secret and no address of the store app, and the test installation has both for the other scenarios; covered by custom/spec/requests/inclamo/provisioning/store_access_spec.rb (no request for a key without the app's address, or without an HTTPS one)",
  'app-store-access › Requests for a key are recorded without the key › A refusal is recorded':
    'the record is a table no address or page shows; covered by custom/spec/lib/inclamo/shopify/app_key_spec.rb ("records each outcome with the time, the account and the store, without a key or a signature")',
  'app-agent-auto-connection › Every attempt is recorded without secrets › A refused connection is recorded':
    'the record is a table no address or page shows; covered by custom/spec/requests/inclamo/provisioning/agent_events_spec.rb',
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
  'instance-installation › Health is visible from outside and failures reach the operator › Alarm after three failures':
    'the monitor is a service outside the machine and outside this repository; covered by the checklist for each new machine in docs/install.md (the health page is failed on purpose and the alarm is awaited in the operator\'s chat)',
  'instance-installation › The machine is closed except for the web and ssh › Password login refused':
    'needs a machine whose ssh daemon deploy/harden.sh has configured, which the tests may not do to the machine they run on; covered by the checklist for each new machine in docs/install.md',
  'interface-language › A missing wording is shown in English › Single missing text':
    'the string check refuses a build whose Ukrainian dictionary lacks a text, so no installation has one to show; covered by shims/app/javascript/dashboard/inclamo/specs/language.spec.js ("gives the English text where the chosen language has none, never the key")',
  'interface-language › Own screens are complete in Ukrainian › Identifier kept':
    'needs a store whose app lacks an access scope; scope names reach the sentence through a placeholder, and scripts/check-ui-strings.mjs refuses a Ukrainian text that drops or adds a placeholder (scripts/ui-strings-language.test.mjs)',
  'interface-language › Ukrainian counts take the right form › Two-form text of Chatwoot is unchanged':
    "needs a text of Chatwoot with a chosen number of forms on a screen; covered by shims/app/javascript/dashboard/inclamo/specs/language.spec.js against the translation library itself (\"leave a Ukrainian text with two forms reading as before\")",
  'interface-language › Ukrainian counts take the right form › Other languages are untouched':
    'every other end-to-end file runs in English and reads its counts as before; the rule itself is covered by shims/app/javascript/dashboard/inclamo/specs/language.spec.js ("leave English untouched")',
  'interface-language › Dates, times and money follow the interface language › Date in Ukrainian':
    "needs an order of the store placed on a known day; covered by shims/app/javascript/dashboard/inclamo/specs/language.spec.js, where the interface is Ukrainian and the environment's own language is English",
  'interface-language › Dates, times and money follow the interface language › Amount in Ukrainian':
    "needs an order of the store with a known total; covered by shims/app/javascript/dashboard/inclamo/specs/language.spec.js, where the interface is Ukrainian and the environment's own language is English",
  'interface-language › One word for one thing › Conversation has one name':
    'a property of the dictionary, not of a screen; covered by scripts/check-ui-strings.mjs, which refuses the words locale/uk.rules.json rules out',
  'shopify-connection › The credentials are a secret › Installation without encryption keys':
    'needs an installation without encryption keys; covered by the request spec and the component test',
  'app-store-erasure › Erasures hold after a restore from backup › A restore brings an erased store back':
    'needs the database of the installation the tests drive to be restored from a backup; covered by custom/spec/lib/inclamo/erasure/reapply_spec.rb, which brings back the state a backup taken before the erasure holds and runs the re-apply routine and its task with the journal',
  'app-store-erasure › Erasures hold after a restore from backup › A restore brings an erased shopper back':
    "needs the database of the installation the tests drive to be restored from a backup; covered by custom/spec/lib/inclamo/erasure/reapply_shoppers_spec.rb, which brings back the shopper and the waiting ticket a backup taken before the deletion holds and runs the re-apply routine and its task with the journal",
  'app-store-erasure › Without a decision the helpdesk deletes after the waiting time › A reminder before the date':
    'the reminders come 7 days and 1 day before the date of automatic deletion and the tests cannot move the installation\'s clock by days; covered by custom/spec/jobs/inclamo/erasure_check_job_shoppers_spec.rb ("reminds a waiting erasure 7 days and 1 day before its date, each once")',
  "app-store-erasure › The app learns the state of requests without shopper data › Counting a store's requests":
    'needs a data request received 31 days ago, and the tests cannot move the installation\'s clock; covered by custom/spec/requests/inclamo/provisioning/shopper_requests_spec.rb ("counts waiting, held and overdue requests of the store"); the end-to-end test "A hold with a reason" reads the counts of a store with held requests',
  'app-store-erasure › Requests are recorded, and readable shopper data is kept only while a ticket is open › Reading the record of a done request':
    'the record is a table no address or page shows; covered by custom/spec/jobs/inclamo/erasure_check_job_shoppers_spec.rb ("keeps the email and phone encrypted while the ticket is open, and only keyed digests afterwards, in the record and the journal")',
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
