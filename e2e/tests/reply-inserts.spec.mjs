// Scenarios of behavior contract `reply-inserts`: a product of the store and
// a discount code made from an administrator's preset go into the reply the
// agent is writing. Each describe is a requirement, each test one of its
// scenarios. Every code the helpdesk creates is checked in the store through
// the Admin API.
import { test, expect } from '@playwright/test';
import { signIn, openOrders, apiAs, proxy, bench, runTag, users, eventually } from '../lib/helpdesk.mjs';
import { openStore } from '../lib/store.mjs';

const account = process.env.E2E_ACCOUNT_ID || '1';
const run = runTag('ins');
// Presets are named after the run, so that the codes made from them can be
// found and removed: a code's title starts with its preset's name.
const named = name => `E2E-${run} ${name}`;
const CODE = /^THANKS-[A-HJ-NP-Z2-9]{8}$/;
let admin;
let agent;
let inbox;
let store;
let maya;
let products;
let conversation;
let stranger;

test.describe.configure({ mode: 'serial' });

const presets = async () => (await admin.get('/inclamo/discount_presets')).body.presets;
const removePresets = async () => {
  for (const preset of await presets()) await admin.delete(`/inclamo/discount_presets/${preset.id}`);
};
const SORRY = { kind: 'percentage', value: '10', expires_in_days: 30, usage_limit: 1, audience: 'customer' };
const THANKS = { kind: 'amount', value: '5.00', expires_in_days: '', usage_limit: 3, audience: 'anyone' };
// The preset of this name, made through the API when an earlier test did not make it.
const preset = async (name, attributes) => {
  const existing = (await presets()).find(entry => entry.name === named(name));
  if (existing) return existing;
  const made = await admin.post('/inclamo/discount_presets', { name: named(name), ...attributes });
  expect(made.status).toBe(201);
  return made.body.preset;
};
const giveDiscounts = id => admin.post('/inclamo/discount_grants', { user_id: id });
const takeDiscounts = id => admin.delete(`/inclamo/discount_grants/${id}`);

test.beforeAll(async ({ playwright }) => {
  test.setTimeout(600_000);
  const request = await playwright.request.newContext({ baseURL: process.env.HELPDESK_URL });
  admin = await apiAs(request, users.admin);
  agent = await apiAs(request, users.agent);
  inbox = await admin.inbox([admin.userId, agent.userId]);
  await proxy.reset();
  await admin.disconnect();
  await admin.connect(bench());
  await admin.takeRole(agent.userId);
  await takeDiscounts(agent.userId);
  await removePresets();

  store = await openStore(run);
  products = await store.storefrontProducts();
  maya = await store.customer('Maya');
  conversation = await admin.conversation(inbox, { name: 'Inserts Example', email: maya.email });
  // The customer is chosen as an agent would: the store's search may not show a customer made a moment ago.
  expect((await admin.post(`/inclamo/shopify/conversations/${conversation.id}/customer`, { customer_id: maya.id })).status).toBe(200);
  stranger = await admin.conversation(inbox, { name: 'Stranger Example', email: `stranger.example.${run}@example.com`.toLowerCase() });
});

test.beforeEach(async () => {
  await proxy.reset();
});

test.afterAll(async () => {
  await proxy.reset();
  await admin.recheck();
  await admin.takeRole(agent.userId);
  await takeDiscounts(agent.userId);
  await removePresets();
  const removed = await store.clean();
  console.log(`removed from the store: ${JSON.stringify({ orders: removed.orders, customers: removed.customers, discounts: removed.discounts, products: removed.products })}`);
  // Nothing of the run is left in the store.
  expect(removed.kept).toEqual([]);
  expect(await store.discounts()).toEqual([]);
});

const open = async (page, user, chat = conversation, state = 'matched') => {
  await signIn(page, user);
  const section = await openOrders(page, account, chat.id);
  await expect(section).toHaveAttribute('data-state', state);
  return section;
};
const editor = page => page.locator('.ProseMirror[contenteditable="true"]').first();
const productDialog = page => page.getByTestId('inclamo-insert-product-dialog');
const productRow = (page, product) => productDialog(page).getByTestId('inclamo-product').filter({ hasText: product.title });
// The store's search shows a product it has just made only after a moment:
// when `product` should be found, the search is made again until it is.
const search = async (page, text, product) => {
  const query = productDialog(page).getByTestId('inclamo-product-query');
  const deadline = Date.now() + 90_000;
  for (;;) {
    await query.fill(text);
    await expect(productDialog(page).getByTestId('inclamo-product-searching')).toHaveCount(0, { timeout: 15_000 });
    if (!product || Date.now() > deadline) return;
    if (await productRow(page, product).first().waitFor({ timeout: 3_000 }).then(() => true, () => false)) return;
    await query.fill('');
    await page.waitForTimeout(3_000);
  }
};
const discountDialog = page => page.getByTestId('inclamo-action-dialog');
const pickPreset = (page, made) => discountDialog(page).locator(`[data-preset-id="${made.id}"] input`).check();
const createCode = page => page.getByRole('button', { name: 'Create the code', exact: true }).click();
const settingsPage = async (page, user) => {
  await signIn(page, user);
  await page.goto(`/app/accounts/${account}/settings/discount-codes`);
};
const newestCode = async chat => (await admin.actions(chat.id)).find(record => record.action === 'discount' && record.outcome === 'accepted');
// The code as the store holds it; the store's search shows a new code after a moment.
const inStore = async code => (await eventually(() => store.discounts(), list => list.some(node => node.codeDiscount.codes.nodes[0]?.code === code))).find(
  node => node.codeDiscount.codes.nodes[0]?.code === code
).codeDiscount;
const days = (from, to) => (new Date(to) - new Date(from)) / 86_400_000;
// Gives a code from a preset through the dialog and returns its text.
const giveCode = async (page, made, chat = conversation, state = 'matched') => {
  const section = await open(page, users.agent, chat, state);
  await section.getByTestId('inclamo-discount-open').click();
  await pickPreset(page, made);
  await createCode(page);
  await expect(discountDialog(page)).toBeHidden();
  const record = await eventually(() => newestCode(chat), found => Boolean(found?.result?.code));
  return record.result.code;
};

test.describe('A product is inserted into the reply', () => {
  // The store's search may need a while to show the products of this run.
  test.describe.configure({ timeout: 180_000 });
  test('Product with a link', async ({ page }) => {
    // The development store is password-protected and gives no storefront link:
    // the proxy answers as the open store does for the published product.
    await proxy.rule({ match: { operation: 'product_search' }, effect: 'patch', value: { patch: 'storefront', urls: { [products.shown.id]: products.shown.url } } });
    const section = await open(page, users.agent);
    await section.getByTestId('inclamo-insert-product-open').click();
    await search(page, products.shown.title, products.shown);
    await productRow(page, products.shown).getByTestId('inclamo-product-variant').click();

    await expect(productDialog(page)).toBeHidden();
    // The E2E inbox is an API inbox: its editor is plain text, so the link is written out.
    await expect(editor(page)).toContainText(products.shown.title);
    await expect(editor(page)).toContainText('150');
    await expect(editor(page)).toContainText(products.shown.url);
    await editor(page).press('End');
    await editor(page).pressSequentially(' It fits.');
    await expect(editor(page)).toContainText(`${products.shown.url} It fits.`);
  });

  test('Search by SKU', async ({ page }) => {
    const section = await open(page, users.agent);
    await section.getByTestId('inclamo-insert-product-open').click();
    await search(page, products.hidden.sku, products.hidden);

    await expect(productRow(page, products.hidden)).toHaveCount(1);
    await expect(productRow(page, products.hidden).getByTestId('inclamo-product-variant')).toContainText(products.hidden.sku);
  });

  test('Product not in the online store', async ({ page }) => {
    const section = await open(page, users.agent);
    await section.getByTestId('inclamo-insert-product-open').click();
    await search(page, products.hidden.title, products.hidden);

    await expect(productRow(page, products.hidden).getByTestId('inclamo-product-no-link')).toBeVisible();
    await productRow(page, products.hidden).getByTestId('inclamo-product-variant').click();

    await expect(editor(page)).toContainText(products.hidden.title);
    await expect(editor(page)).toContainText('150');
    await expect(editor(page)).not.toContainText('http');
  });

  test('Nothing found', async ({ page }) => {
    const section = await open(page, users.agent);
    await section.getByTestId('inclamo-insert-product-open').click();
    await search(page, `zzqx${run}nothing`);

    await expect(productDialog(page).getByTestId('inclamo-product-none')).toBeVisible();
    await expect(productDialog(page).getByTestId('inclamo-product')).toHaveCount(0);
    await expect(editor(page)).not.toContainText(run);
  });
});

test.describe('Discount presets are set by an administrator', () => {
  const add = async (page, fields) => {
    await page.getByTestId('inclamo-preset-add').click();
    const form = page.getByTestId('inclamo-preset-form');
    await form.getByTestId('inclamo-preset-field-name').fill(fields.name);
    await form.getByTestId('inclamo-preset-field-kind').selectOption(fields.kind);
    await form.getByTestId('inclamo-preset-field-value').fill(fields.value);
    await form.getByTestId('inclamo-preset-field-expires').fill(fields.expires);
    await form.getByTestId('inclamo-preset-field-uses').fill(fields.uses);
    await form.getByTestId('inclamo-preset-field-audience').selectOption(fields.audience);
    await form.getByTestId('inclamo-preset-save').click();
  };
  const row = (page, name) => page.getByTestId('inclamo-preset').filter({ hasText: name });

  test('Preset created', async ({ page }) => {
    await settingsPage(page, users.admin);
    await add(page, { name: named('Sorry'), kind: 'percentage', value: '10', expires: '30', uses: '1', audience: 'customer' });

    await expect(row(page, named('Sorry')).getByTestId('inclamo-preset-conditions')).toHaveText('10% off the order · expires in 30 days · usable once · this customer only');
    expect((await presets()).find(entry => entry.name === named('Sorry'))).toMatchObject(SORRY);
  });

  test('Preset that never expires', async ({ page }) => {
    await settingsPage(page, users.admin);
    await add(page, { name: named('Forever'), kind: 'amount', value: '200', expires: '', uses: '1', audience: 'anyone' });

    await expect(row(page, named('Forever')).getByTestId('inclamo-preset-conditions')).toContainText('never expires');
    expect((await presets()).find(entry => entry.name === named('Forever'))).toMatchObject({ expires_in_days: null });
  });

  test('Preset outside the limits', async ({ page }) => {
    const before = (await presets()).length;
    await settingsPage(page, users.admin);
    const cases = [
      [{ kind: 'percentage', value: '0', uses: '1' }, 'value', 'The value must be above 0.'],
      [{ kind: 'percentage', value: '120', uses: '1' }, 'value', 'A percentage can be at most 100.'],
      [{ kind: 'amount', value: '0', uses: '1' }, 'value', 'The value must be above 0.'],
      [{ kind: 'percentage', value: '10', uses: '0' }, 'usage_limit', 'At least 1 use.'],
    ];
    for (const [fields, field, message] of cases) {
      await page.reload();
      await add(page, { name: named('Wrong'), expires: '30', audience: 'anyone', ...fields });
      await expect(page.getByTestId(`inclamo-preset-error-${field}`)).toHaveText(message);
    }

    expect(await presets()).toHaveLength(before);
  });

  test('Agent cannot change presets', async ({ page }) => {
    await settingsPage(page, users.agent);

    await expect(page.getByTestId('inclamo-discounts-page')).toHaveCount(0);
    expect((await agent.post('/inclamo/discount_presets', { name: named('Mine'), ...SORRY })).status).toBe(403);
    const existing = (await presets())[0];
    expect((await agent.put(`/inclamo/discount_presets/${existing.id}`, { value: '90' })).status).toBe(403);
    expect((await agent.delete(`/inclamo/discount_presets/${existing.id}`)).status).toBe(403);
    expect((await presets()).find(entry => entry.id === existing.id)).toMatchObject({ value: existing.value });
  });
});

test.describe('The right to give discounts', () => {
  test('Right given', async ({ page }) => {
    await preset('Sorry', SORRY);
    await takeDiscounts(agent.userId);
    await settingsPage(page, users.admin);
    await page.getByTestId(`inclamo-grant-${agent.userId}`).locator('input').check();
    await expect(page.getByTestId(`inclamo-grant-${agent.userId}`).locator('input')).toBeChecked();

    const section = await open(page, users.agent);
    await expect(section.getByTestId('inclamo-discount-open')).toBeVisible();
    // The order-actions role was not given.
    expect((await agent.panel(conversation.id)).viewer).toMatchObject({ can_act_on_orders: false, can_give_discounts: true });
  });

  test('Agent without the right', async ({ page }) => {
    await preset('Sorry', SORRY);
    await admin.giveRole(agent.userId);
    await takeDiscounts(agent.userId);

    const section = await open(page, users.agent);
    await expect(section.getByTestId('inclamo-insert-product-open')).toBeVisible();
    await expect(section.getByTestId('inclamo-discount-open')).toHaveCount(0);
    await admin.takeRole(agent.userId);
  });
});

test.describe('A discount code is created from a preset and inserted', () => {
  test.beforeEach(async () => {
    await giveDiscounts(agent.userId);
  });

  test('Code for the customer', async ({ page }) => {
    const sorry = await preset('Sorry', SORRY);
    const started = new Date();

    const code = await giveCode(page, sorry);

    expect(code).toMatch(CODE);
    await expect(editor(page)).toContainText(code);
    const made = await inStore(code);
    expect(made).toMatchObject({
      usageLimit: 1,
      appliesOncePerCustomer: false,
      context: { __typename: 'DiscountCustomers', customers: [{ id: maya.id }] },
      customerGets: { value: { __typename: 'DiscountPercentage', percentage: 0.1 }, items: { allItems: true } },
    });
    expect(days(started, made.endsAt)).toBeGreaterThan(29.9);
    expect(days(started, made.endsAt)).toBeLessThan(30.1);
  });

  test('Code for anyone that never expires', async ({ page }) => {
    const thanks = await preset('Thanks', THANKS);

    const code = await giveCode(page, thanks);

    const made = await inStore(code);
    expect(made).toMatchObject({
      endsAt: null,
      usageLimit: 3,
      appliesOncePerCustomer: true,
      context: { __typename: 'DiscountBuyerSelectionAll', all: 'ALL' },
      customerGets: { value: { __typename: 'DiscountAmount', amount: { amount: '5.0', currencyCode: store.currency }, appliesOnEachItem: false } },
    });
  });

  test('Contact who is not a customer', async ({ page }) => {
    const sorry = await preset('Sorry', SORRY);
    const thanks = await preset('Thanks', THANKS);
    const section = await open(page, users.agent, stranger, 'none');
    await section.getByTestId('inclamo-discount-open').click();

    const forCustomer = discountDialog(page).locator(`[data-preset-id="${sorry.id}"]`);
    await expect(forCustomer.locator('input')).toBeDisabled();
    await expect(forCustomer.getByTestId('inclamo-discount-no-customer')).toBeVisible();
    await pickPreset(page, thanks);
    await createCode(page);
    await expect(discountDialog(page)).toBeHidden();

    const record = await eventually(() => newestCode(stranger), found => Boolean(found?.result?.code));
    expect((await inStore(record.result.code)).context).toEqual({ __typename: 'DiscountBuyerSelectionAll', all: 'ALL' });
  });

  test('Code text is made by the helpdesk', async ({ page }) => {
    const thanks = await preset('Thanks', THANKS);
    const section = await open(page, users.agent);
    await section.getByTestId('inclamo-discount-open').click();

    await expect(discountDialog(page).locator('input[type="text"], textarea')).toHaveCount(0);
    await pickPreset(page, thanks);
    await createCode(page);
    await expect(discountDialog(page)).toBeHidden();

    const record = await eventually(() => newestCode(conversation), found => Boolean(found?.result?.code));
    expect(record.result.code).toMatch(CODE);
    expect((await inStore(record.result.code)).codes.nodes[0].code).toBe(record.result.code);
  });

  test('Permission missing', async ({ page }) => {
    await preset('Sorry', SORRY);
    const scopes = (await admin.connection()).scopes.filter(scope => !['write_discounts', 'read_discounts'].includes(scope));
    await proxy.rule({ match: { operation: 'shop_info' }, effect: 'patch', value: { patch: 'scopes', scopes } });
    await admin.recheck();

    const section = await open(page, users.admin);
    await expect(section.getByTestId('inclamo-discount-open')).toHaveCount(0);
    await expect(section.getByTestId('inclamo-discount-unavailable')).toContainText('write_discounts');

    await proxy.reset();
    await admin.recheck();
  });

  test('No presets yet', async ({ page }) => {
    await removePresets();

    const section = await open(page, users.admin);
    await expect(section.getByTestId('inclamo-discount-open')).toHaveCount(0);
    await expect(section.getByTestId('inclamo-discount-no-presets')).toBeVisible();
    await expect(section.getByTestId('inclamo-discount-settings-link')).toHaveAttribute('href', new RegExp(`/settings/discount-codes$`));
  });
});

test.describe('A created code leaves a record and failures are shown', () => {
  test.beforeEach(async () => {
    await giveDiscounts(agent.userId);
  });

  test('Record of a code', async ({ page }) => {
    const sorry = await preset('Sorry', SORRY);

    const code = await giveCode(page, sorry);

    const notes = await eventually(() => admin.notes(conversation.id), list => list.some(note => note.includes(code)));
    const note = notes.find(entry => entry.includes(code));
    const shape = new RegExp(`^Created discount code ${code} from the preset "${named('Sorry')}": 10% off the order, usable once, for this customer only, expires on (\\d{4}-\\d{2}-\\d{2})\\.$`);
    expect(note).toMatch(shape);
    // The expiry date is 30 days on; the day may turn between the store and this check.
    expect(Math.abs(days(Date.now() + 30 * 86_400_000, `${note.match(shape)[1]}T12:00:00Z`))).toBeLessThan(1.6);
  });

  test('Store refuses the code', async ({ page }) => {
    const sorry = await preset('Sorry', SORRY);
    const notesBefore = (await admin.notes(conversation.id)).length;
    // Search is eventually consistent: wait for every earlier accepted code
    // before taking the baseline, or a preceding code can look like a new one.
    const earlier = (await Promise.all([conversation, stranger].map(chat => admin.actions(chat.id))))
      .flat().filter(record => record.action === 'discount' && record.outcome === 'accepted').map(record => record.result.code);
    const indexed = await eventually(() => store.discounts(), nodes => earlier.every(code => nodes.some(node => node.codeDiscount.codes.nodes.some(entry => entry.code === code))));
    const codesBefore = indexed.map(node => node.id).sort();
    await proxy.rule({
      match: { operation: 'discount_code_create' },
      effect: 'refuse',
      value: { mutation: 'discountCodeBasicCreate', field: 'code', message: 'Code must be unique. Please try a different code.', empty: { codeDiscountNode: null } },
    });

    const section = await open(page, users.agent);
    await section.getByTestId('inclamo-discount-open').click();
    await pickPreset(page, sorry);
    await createCode(page);

    await expect(discountDialog(page).getByTestId('inclamo-action-message')).toContainText('Code must be unique. Please try a different code.');
    await expect(editor(page)).not.toContainText('THANKS-');
    expect(await admin.notes(conversation.id)).toHaveLength(notesBefore);
    expect((await store.discounts()).map(node => node.id).sort()).toEqual(codesBefore);
  });
});
