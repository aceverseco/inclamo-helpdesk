// Read-only verification after a completed run. Shared catalogue fixtures are
// deliberately excluded; only tags and discount titles of the named run match.
import { connect } from './lib/shopify.mjs';

const runs = process.argv.slice(2);
if (!runs.length || runs.some(run => !/^[a-zA-Z0-9-]{6,40}$/.test(run))) {
  throw new Error('Supply the exact E2E_RUN names (at least six alphanumeric characters).');
}
const shopify = await connect('SHOPIFY_SEEDER');
const reports = [];
for (const run of runs) {
  const prefix = `e2e-${run}`;
  const own = item => item.tags?.some(tag => tag.startsWith(prefix));
  const query = `tag:${prefix}*`;
  let after = null;
  let orders = [];
  do {
    const found = (await shopify('seeded_orders', { query, after })).orders;
    orders.push(...found.nodes.filter(own));
    after = found.pageInfo.hasNextPage ? found.pageInfo.endCursor : null;
  } while (after);
  const customers = (await shopify('seeded_customers', { query })).customers.nodes.filter(own);
  const products = (await shopify('seeded_products', { query })).products.nodes.filter(own);
  const drafts = (await shopify('seeded_drafts', { query })).draftOrders.nodes.filter(own);
  const discountPrefix = `E2E-${run}`;
  const discounts = (await shopify('seeded_discounts', { query: `title:${discountPrefix}*` })).codeDiscountNodes.nodes
    .filter(node => node.codeDiscount?.title?.startsWith(discountPrefix));
  const remaining = Object.fromEntries(Object.entries({ orders, customers, products, drafts, discounts }).map(([kind, list]) => [kind, list.length]));
  reports.push({ run, remaining, clean: Object.values(remaining).every(count => count === 0) });
}
console.log(JSON.stringify({ verified_at: new Date().toISOString(), reports }, null, 2));
if (reports.some(report => !report.clean)) process.exitCode = 1;
