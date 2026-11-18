// Scenarios of behavior contract `interface-language`. Each describe is a
// requirement, each test one of its scenarios; scripts/check-e2e-coverage.mjs
// relies on the names. Scenarios that need a wording to be missing, a text of
// Chatwoot with chosen forms, or a store's order are covered by the component
// tests and the string check (see that script).
//
// The words expected on a screen are read from the overlay's own dictionaries,
// so a corrected wording needs no change here. Every test that changes a
// profile's or the account's language puts it back.
import { test, expect } from '@playwright/test';
import { existsSync, mkdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { signIn, apiAs, eventually, openOrders, users, runTag } from '../lib/helpdesk.mjs';

const account = process.env.E2E_ACCOUNT_ID || '1';
const origin = process.env.HELPDESK_URL || 'http://rails:3000';
const accountPath = `/app/accounts/${account}`;
const profileUrl = `${origin}/api/v1/profile`;
const accountUrl = `${origin}/api/v1/accounts/${account}`;

// The repository is beside the tests in a checkout and at /repo in the
// container the tests run in.
const here = dirname(fileURLToPath(import.meta.url));
const locales = [process.env.E2E_REPO, join(here, '..', '..'), '/repo']
  .filter(Boolean)
  .map(root => join(root, 'shims', 'app', 'javascript', 'dashboard', 'inclamo', 'locale'))
  .find(directory => existsSync(join(directory, 'uk.json')));
if (!locales) throw new Error("the overlay's dictionaries were not found");
const dictionary = code => JSON.parse(readFileSync(join(locales, `${code}.json`), 'utf8'));
const en = dictionary('en');
const uk = dictionary('uk');
const word = (messages, key) => key.split('.').reduce((node, part) => node[part], messages);
// A counted text of the Ukrainian dictionary for a number.
const counted = (key, count) => {
  const forms = word(uk, key);
  const form = new Intl.PluralRules('uk').select(count);
  return (typeof forms === 'string' ? forms : forms[form]).replace('{count}', String(count));
};

const shots = join(process.env.E2E_OUTPUT || './output', 'interface-language');
const capture = async (page, name) => {
  mkdirSync(shots, { recursive: true });
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: join(shots, `${name}.png`), animations: 'disabled' });
};

let admin;
let agent;
const original = {};

test.describe.configure({ mode: 'serial' });

test.beforeAll(async ({ playwright }) => {
  const request = await playwright.request.newContext({ baseURL: origin });
  admin = await apiAs(request, users.admin);
  agent = await apiAs(request, users.agent);
  original.admin = (await admin.get(profileUrl)).body.ui_settings || {};
  original.agent = (await agent.get(profileUrl)).body.ui_settings || {};
  original.account = (await admin.get(accountUrl)).body.locale || 'en';
});

test.afterAll(async () => {
  await admin.put(profileUrl, { profile: { ui_settings: original.admin } });
  await agent.put(profileUrl, { profile: { ui_settings: original.agent } });
  await admin.patch(accountUrl, { locale: original.account });
});

// --- helpers of this file ---------------------------------------------------

// The language of a staff member's profile; null leaves the choice to the account.
async function profileLanguage(api, settings, code) {
  const { locale, ...rest } = settings;
  const saved = await api.put(profileUrl, { profile: { ui_settings: code ? { ...rest, locale: code } : rest } });
  expect(saved.status).toBe(200);
}

async function accountLanguage(code) {
  const saved = await admin.patch(accountUrl, { locale: code });
  expect(saved.status).toBe(200);
  await eventually(async () => (await admin.get(accountUrl)).body.locale, value => value === code);
}

// The workspace navigation: its heading and the button of its tools menu.
const navigationHeading = page => page.locator('.nav-heading').first();
const toolsButton = (page, messages) => page.getByRole('button', { name: word(messages, 'WORKSPACE.MORE'), exact: true });

async function navigationReads(page, messages) {
  await expect(navigationHeading(page)).toHaveText(word(messages, 'WORKSPACE.HEADING'), { timeout: 45_000 });
  await expect(toolsButton(page, messages)).toBeVisible();
}

// --- the scenarios ----------------------------------------------------------

test.describe('Own screens follow the chosen interface language', () => {
  test('Profile language is Ukrainian', async ({ page }) => {
    const inbox = await admin.inbox([admin.userId, agent.userId]);
    const conversation = await admin.conversation(inbox, { name: 'E2E Language', email: `${runTag('-language')}@example.test`, message: 'Where is my order?' });
    await profileLanguage(agent, original.agent, 'uk');
    try {
      await signIn(page, users.agent);
      await page.goto(`${accountPath}/dashboard`);
      await navigationReads(page, uk);
      await capture(page, 'workspace');

      const section = await openOrders(page, account, conversation.id, word(uk, 'ORDERS.TITLE'));
      await expect(section).toBeVisible();
      await expect(page.locator('[data-widget-host="conversation-sidebar"] .inclamo-widget-heading', { hasText: word(uk, 'ORDERS.TITLE') }).first()).toBeVisible();
      await capture(page, 'conversation');
    } finally {
      await profileLanguage(agent, original.agent, null);
    }
  });

  test('Account language applies when the profile has none', async ({ page }) => {
    await profileLanguage(agent, original.agent, null);
    await accountLanguage('uk');
    try {
      await signIn(page, users.agent);
      await page.goto(`${accountPath}/dashboard`);
      await navigationReads(page, uk);
    } finally {
      await accountLanguage(original.account);
    }
  });

  test("Profile language wins over the account's", async ({ page }) => {
    await profileLanguage(agent, original.agent, 'en');
    await accountLanguage('uk');
    try {
      await signIn(page, users.agent);
      await page.goto(`${accountPath}/dashboard`);
      await navigationReads(page, en);
    } finally {
      await accountLanguage(original.account);
      await profileLanguage(agent, original.agent, null);
    }
  });

  test('Language is switched', async ({ page }) => {
    await profileLanguage(agent, original.agent, 'en');
    try {
      await signIn(page, users.agent);
      await page.goto(`${accountPath}/profile/settings`);
      await expect(toolsButton(page, en)).toBeVisible({ timeout: 45_000 });

      let reloaded = false;
      page.on('load', () => {
        reloaded = true;
      });
      await page.locator('select[name="language"]').selectOption('uk');

      await expect(toolsButton(page, uk)).toBeVisible({ timeout: 30_000 });
      await expect(toolsButton(page, en)).toHaveCount(0);
      expect(reloaded, 'the page was not reloaded').toBe(false);
    } finally {
      await profileLanguage(agent, original.agent, null);
    }
  });
});

test.describe('A missing wording is shown in English', () => {
  test('Language the own screens are not translated into', async ({ page }) => {
    await profileLanguage(agent, original.agent, 'de');
    try {
      await signIn(page, users.agent);
      await page.goto(`${accountPath}/profile/settings`);
      // Chatwoot's own page, in German as Chatwoot ships it.
      await expect(page.getByText('Profileinstellungen').first()).toBeVisible({ timeout: 45_000 });
      await expect(toolsButton(page, en)).toBeVisible();
    } finally {
      await profileLanguage(agent, original.agent, null);
    }
  });
});

test.describe('English reads as before', () => {
  test('English interface', async ({ page }) => {
    await profileLanguage(agent, original.agent, 'en');
    try {
      await signIn(page, users.agent);
      await page.goto(`${accountPath}/dashboard`);
      await navigationReads(page, en);
      await expect(navigationHeading(page)).toHaveText('Workspace');
      await expect(page.getByRole('button', { name: 'Workspace tools', exact: true })).toBeVisible();
    } finally {
      await profileLanguage(agent, original.agent, null);
    }
  });
});

// The Helpdesk's own settings pages and the key of each page's title.
const PAGES = [
  ['setup', 'SETUP.TITLE'],
  ['website-widget', 'WEBSITE_WIDGET.WEBSITE_WIDGET'],
  ['workspace-widgets', 'WIDGETS.ADMIN_TITLE'],
  ['order-actions', 'SETTINGS.ORDER_ROLES.TITLE'],
  ['preset-rules', 'SETTINGS.RULE_PRESETS.TITLE'],
  ['discount-codes', 'SETTINGS.DISCOUNTS.TITLE'],
  ['team-queues', 'SETTINGS.TEAM_QUEUES.TITLE'],
  ['sla-policies', 'SETTINGS.SLA.TITLE'],
  ['ai-agent', 'SETTINGS.AI_AGENT.TITLE'],
];

test.describe('Own screens are complete in Ukrainian', () => {
  test('No English left on an own screen', async ({ page }) => {
    test.setTimeout(300_000);
    await profileLanguage(admin, original.admin, 'uk');
    try {
      await signIn(page, users.admin);
      await page.goto(`${accountPath}/dashboard`);
      await navigationReads(page, uk);

      for (const [path, key] of PAGES) {
        await page.goto(`${accountPath}/settings/${path}`);
        const title = word(uk, key);
        const heading = page.locator('h1, h2').filter({ hasText: new RegExp(`^\\s*${title.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*$`) }).first();
        await expect(heading, `the page ${path} carries its Ukrainian title`).toBeVisible({ timeout: 45_000 });
        if (word(en, key) !== title) {
          await expect(page.locator('h1, h2').filter({ hasText: new RegExp(`^\\s*${word(en, key)}\\s*$`) }), `the page ${path} does not carry its English title`).toHaveCount(0);
        }
        await page.waitForLoadState('networkidle').catch(() => {});
        await capture(page, `settings-${path}`);
        await page.setViewportSize({ width: 1024, height: 768 });
        await capture(page, `settings-${path}-1024`);
        await page.setViewportSize({ width: 1440, height: 900 });
      }
    } finally {
      await profileLanguage(admin, original.admin, null);
    }
  });
});

test.describe('Ukrainian counts take the right form', () => {
  test('Three forms on an own screen', async ({ page }) => {
    test.setTimeout(300_000);
    const name = `E2E Language ${runTag('')}`;
    const made = (await admin.post('/inboxes', { name, channel: { type: 'api', webhook_url: '' } })).body;
    await admin.post('/inbox_members', { inbox_id: made.id, user_ids: [admin.userId] });
    const policy = (
      await admin.post('/inclamo/sla_policies', { name, business_hours_only: false, all_inboxes: false, inbox_ids: [made.id], first_response_seconds: 3600 })
    ).body;
    const policyId = policy.policy?.id ?? policy.id;
    expect(policyId, 'the policy was created').toBeTruthy();
    const applied = async () =>
      ((await admin.get('/inclamo/sla_policies/summary?days=7')).body.policies || []).find(row => row.id === policyId)?.conversations ?? 0;
    let conversations = 0;
    const reach = async count => {
      for (; conversations < count; conversations += 1) {
        await admin.conversation(made, {
          name: `E2E Language ${conversations}`,
          email: `${runTag(`-language-${conversations}`)}@example.test`,
          message: 'Hello',
          together: true,
        });
      }
      await eventually(applied, value => value === count, { timeout: 60_000 });
    };

    await profileLanguage(admin, original.admin, 'uk');
    try {
      await signIn(page, users.admin);
      for (const count of [1, 3, 5]) {
        await reach(count);
        await page.goto(`${accountPath}/settings/sla-policies`);
        await expect(page.getByTestId(`inclamo-sla-summary-${policyId}`)).toContainText(counted('SETTINGS.SLA.SUMMARY.CONVERSATIONS', count), { timeout: 45_000 });
      }
      expect(counted('SETTINGS.SLA.SUMMARY.CONVERSATIONS', 1)).not.toBe(counted('SETTINGS.SLA.SUMMARY.CONVERSATIONS', 3).replace('3', '1'));
      expect(counted('SETTINGS.SLA.SUMMARY.CONVERSATIONS', 3)).not.toBe(counted('SETTINGS.SLA.SUMMARY.CONVERSATIONS', 5).replace('5', '3'));
      await capture(page, 'sla-policies-counts');
    } finally {
      await profileLanguage(admin, original.admin, null);
      await admin.delete(`/inclamo/sla_policies/${policyId}`);
    }
  });
});
