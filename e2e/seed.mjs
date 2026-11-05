// Creates and removes the store data the end-to-end tests work on.
//
//   node e2e/seed.mjs seed  [run]   create the data set, print what was created as JSON
//   node e2e/seed.mjs clean [run]   delete every order and customer tagged with that run
//
// Everything is tagged `e2e` and `e2e-<run>`; nothing untagged is ever touched.
// Credentials of the seeding app come from SHOPIFY_SEEDER_DOMAIN, _CLIENT_ID
// and _CLIENT_SECRET.
import { randomUUID } from 'node:crypto';
import { connect } from './lib/shopify.mjs';

const [action = 'seed', run = 'manual'] = process.argv.slice(2);
const tags = ['e2e', `e2e-${run}`];
const shopify = await connect('SHOPIFY_SEEDER');

const money = (amount, currencyCode) => ({ shopMoney: { amount: amount.toFixed(2), currencyCode } });

async function createCustomer(index, first, last) {
  const data = await shopify('seed_customer', {
    input: {
      firstName: first,
      lastName: last,
      email: `${first}.${last}.${run}@example.com`.toLowerCase(),
      phone: `+1500555${String(1000 + (Number.parseInt(run.replace(/\D/g, '').slice(-3) || '0', 10) * 10 + index) % 9000).padStart(4, '0')}`,
      tags,
    },
  });
  return data.customerCreate.customer;
}

async function createOrder(customer, variants, currency, { quantity = 1, note } = {}) {
  const total = variants.reduce((sum, variant) => sum + Number(variant.price) * quantity, 0);
  const data = await shopify('seed_order', {
    order: {
      customer: { toAssociate: { id: customer.id } },
      lineItems: variants.map(variant => ({ variantId: variant.id, quantity })),
      financialStatus: 'PAID',
      transactions: [{ kind: 'SALE', status: 'SUCCESS', gateway: 'manual', amountSet: money(total, currency) }],
      shippingAddress: {
        firstName: customer.displayName.split(' ')[0],
        lastName: customer.displayName.split(' ').slice(1).join(' '),
        address1: '1 Example Street',
        city: 'Springfield',
        provinceCode: 'IL',
        countryCode: 'US',
        zip: '62701',
      },
      tags,
      note: note || `e2e ${run}`,
    },
    options: { inventoryBehaviour: 'BYPASS', sendReceipt: false, sendFulfillmentReceipt: false },
  });
  return data.orderCreate.order;
}

async function ship(order, lineItemIndexes, tracking) {
  const fulfillmentOrder = order.fulfillmentOrders.nodes[0];
  const wanted = lineItemIndexes.map(index => order.lineItems.nodes[index].id);
  const lines = fulfillmentOrder.lineItems.nodes.filter(line => wanted.includes(line.lineItem.id));
  const data = await shopify('seed_fulfillment', {
    fulfillment: {
      notifyCustomer: false,
      trackingInfo: tracking,
      lineItemsByFulfillmentOrder: [{
        fulfillmentOrderId: fulfillmentOrder.id,
        fulfillmentOrderLineItems: lines.map(line => ({ id: line.id, quantity: line.remainingQuantity })),
      }],
    },
  });
  return data.fulfillmentCreate.fulfillment;
}

async function refund(order, amount, currency) {
  const sale = order.transactions.find(transaction => transaction.kind === 'SALE');
  const data = await shopify('seed_refund', {
    key: randomUUID(),
    input: {
      orderId: order.id,
      notify: false,
      note: 'e2e partial refund',
      transactions: [{ orderId: order.id, parentId: sale.id, kind: 'REFUND', gateway: sale.gateway, amount: amount.toFixed(2) }],
    },
  });
  return data.refundCreate.refund;
}

async function seed() {
  const catalog = await shopify('seed_catalog');
  const currency = catalog.shop.currencyCode;
  const variants = catalog.products.nodes.flatMap(product => product.variants.nodes.slice(0, 1).map(variant => ({ ...variant, product: product.title })));
  if (variants.length < 3) throw new Error('the store needs at least three active products');

  const maya = await createCustomer(1, 'Maya', 'Example');
  const noah = await createCustomer(2, 'Noah', 'Example');

  const open = await createOrder(maya, variants.slice(0, 3), currency, { note: 'e2e open order' });
  const shipped = await createOrder(maya, variants.slice(0, 2), currency, { note: 'e2e two shipments' });
  await ship(shipped, [0], { company: 'DHL Express', number: `E2E${run}A`, url: `https://example.com/track/E2E${run}A` });
  await ship(shipped, [1], { company: 'UPS', number: `E2E${run}B`, url: `https://example.com/track/E2E${run}B` });
  const refunded = await createOrder(maya, variants.slice(1, 2), currency, { quantity: 2, note: 'e2e partial refund' });
  await refund(refunded, 20, currency);
  const others = await createOrder(noah, variants.slice(2, 3), currency, { note: 'e2e order of another customer' });
  const cancelled = await createOrder(noah, variants.slice(0, 1), currency, { note: 'e2e cancelled' });
  await shopify('seed_cancel', { orderId: cancelled.id });

  const brief = order => ({ id: order.id, name: order.name, total: order.totalPriceSet.shopMoney });
  return {
    run,
    domain: shopify.domain,
    currency,
    customers: { maya, noah },
    orders: { open: brief(open), shipped: brief(shipped), refunded: brief(refunded), others: brief(others), cancelled: brief(cancelled) },
  };
}

async function clean() {
  const removed = { orders: 0, customers: 0, kept: [] };
  for (let after = null; ;) {
    const page = (await shopify('seeded_orders', { query: `tag:'e2e-${run}'`, after })).orders;
    for (const order of page.nodes) {
      if (!order.tags.includes(`e2e-${run}`)) continue; // never trust the search alone
      try {
        if (!order.cancelledAt) await shopify('seed_cancel', { orderId: order.id }).catch(() => {});
        await new Promise(resolve => setTimeout(resolve, 1500));
        await shopify('delete_order', { orderId: order.id });
        removed.orders += 1;
      } catch (error) {
        removed.kept.push(`${order.name}: ${error.message.slice(0, 160)}`);
      }
    }
    if (!page.pageInfo.hasNextPage) break;
    after = page.pageInfo.endCursor;
  }
  const customers = (await shopify('seeded_customers', { query: `tag:'e2e-${run}'` })).customers.nodes;
  for (const customer of customers) {
    if (!customer.tags.includes(`e2e-${run}`)) continue;
    try {
      await shopify('delete_customer', { id: customer.id });
      removed.customers += 1;
    } catch (error) {
      removed.kept.push(`${customer.displayName}: ${error.message.slice(0, 160)}`);
    }
  }
  return removed;
}

const result = action === 'clean' ? await clean() : await seed();
console.log(JSON.stringify(result, null, 2));
