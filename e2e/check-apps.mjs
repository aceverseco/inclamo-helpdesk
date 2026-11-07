// Checks the custom apps the end-to-end tests rely on, on the development
// store: that each one gets a token, holds the scopes it should, and is or is
// not given customers' data as intended.
//
//   node e2e/check-apps.mjs
//
// SHOPIFY_BENCH_*   the app the helpdesk connects with: exactly the scopes the
//                   merchant guide asks for, customer data given.
// SHOPIFY_SEEDER_*  the app that creates and removes test data: wider scopes.
// SHOPIFY_LIMITED_* optional: an app with no distribution method chosen, to
//                   which the store refuses its orders and customers. The
//                   store refuses only what exists, so it must hold an order.
import { connect } from './lib/shopify.mjs';

const GUIDE = ['read_customers', 'read_orders', 'write_orders', 'write_draft_orders', 'read_products', 'read_locations', 'read_merchant_managed_fulfillment_orders', 'write_discounts'];
const SEEDER = ['write_customers', 'write_products', 'write_orders', 'write_draft_orders', 'write_inventory', 'read_locations', 'write_fulfillments', 'write_merchant_managed_fulfillment_orders', 'write_publications', 'write_discounts'];
// A write scope brings its read scope along; the store lists both.
const implied = scopes => [...new Set(scopes.flatMap(scope => (scope.startsWith('write_') ? [scope, scope.replace('write_', 'read_')] : [scope])))].sort();

const apps = [
  { prefix: 'SHOPIFY_BENCH', scopes: GUIDE, exact: true, customers: true },
  { prefix: 'SHOPIFY_SEEDER', scopes: SEEDER, exact: false, customers: true },
  // Its scopes do not matter beyond the two the connection asks for first.
  { prefix: 'SHOPIFY_LIMITED', scopes: ['read_customers', 'read_orders'], exact: false, customers: false, optional: true },
];

let failed = false;
for (const app of apps) {
  if (app.optional && !process.env[`${app.prefix}_CLIENT_ID`]) {
    console.log(`skip  ${app.prefix}: not configured`);
    continue;
  }
  const problems = [];
  try {
    const shopify = await connect(app.prefix);
    const granted = (await shopify('app_scopes')).currentAppInstallation.accessScopes.map(scope => scope.handle).sort();
    const wanted = implied(app.scopes);
    const missing = wanted.filter(scope => !granted.includes(scope));
    const extra = granted.filter(scope => !wanted.includes(scope));
    if (missing.length) problems.push(`lacks ${missing.join(', ')}`);
    if (app.exact && extra.length) problems.push(`holds more than it should: ${extra.join(', ')}`);
    const given = name => shopify(name).then(() => true, error => (/ACCESS_DENIED/.test(error.message) ? false : Promise.reject(error)));
    if ((await given('app_customers')) !== app.customers) problems.push(app.customers ? 'is refused customer data (choose custom distribution for the app)' : 'is given customers, so it cannot stand for an app with no distribution method');
    if ((await given('app_orders')) !== app.customers) problems.push(app.customers ? 'is refused orders (choose custom distribution for the app)' : 'is given orders: either a distribution method was chosen or the store holds no order');
  } catch (error) {
    problems.push(error.message.slice(0, 200));
  }
  failed = failed || problems.length > 0;
  console.log(problems.length ? `FAIL  ${app.prefix}: ${problems.join('; ')}` : `ok    ${app.prefix}`);
}
process.exit(failed ? 1 : 0);
