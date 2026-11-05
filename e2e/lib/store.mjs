// Store data for the end-to-end tests, created through the seeding app and
// tagged per run so that it can be removed again. Nothing untagged is touched.
import { randomUUID } from 'node:crypto';
import { connect } from './shopify.mjs';

const money = (amount, currencyCode) => ({ shopMoney: { amount: amount.toFixed(2), currencyCode } });
const ADDRESS = { address1: '1 Example Street', city: 'Kyiv', countryCode: 'UA', zip: '01001' };

// A development store lets an app create only a few orders a minute and
// answers "Too many attempts" beyond that: wait and try again.
async function paced(create) {
  for (let attempt = 0; ; attempt += 1) {
    try {
      return await create();
    } catch (error) {
      if (attempt >= 10 || !/Too many attempts/i.test(error.message)) throw error;
      await new Promise(resolve => setTimeout(resolve, 15_000));
    }
  }
}

export async function openStore(run) {
  const shopify = await connect('SHOPIFY_SEEDER');
  const tags = ['e2e', `e2e-${run}`];
  const catalog = await shopify('seed_catalog');
  const currency = catalog.shop.currencyCode;
  const variants = catalog.products.nodes.flatMap(product => product.variants.nodes.slice(0, 1));
  if (variants.length < 3) throw new Error('the store needs at least three active products');
  let counter = 0;

  const store = {
    run,
    currency,
    domain: shopify.domain,
    shopify,

    async customer(first, { phone = true } = {}) {
      counter += 1;
      const number = String(Math.floor(Math.random() * 9000) + 1000);
      const data = await shopify('seed_customer', {
        input: { firstName: first, lastName: 'Example', email: `${first}.example.${run}.${counter}@example.com`.toLowerCase(), phone: phone ? `+1500555${number}` : undefined, tags },
      });
      const customer = data.customerCreate.customer;
      return { ...customer, email: `${first}.example.${run}.${counter}@example.com`.toLowerCase(), phone: phone ? `+1500555${number}` : null };
    },

    async order(customer, { items = 1, quantity = 1, note } = {}) {
      const chosen = variants.slice(0, items);
      const total = chosen.reduce((sum, variant) => sum + Number(variant.price) * quantity, 0);
      const [firstName, ...rest] = customer.displayName.split(' ');
      const data = await paced(() => shopify('seed_order', {
        order: {
          customer: { toAssociate: { id: customer.id } },
          lineItems: chosen.map(variant => ({ variantId: variant.id, quantity })),
          financialStatus: 'PAID',
          transactions: [{ kind: 'SALE', status: 'SUCCESS', gateway: 'manual', amountSet: money(total, currency) }],
          shippingAddress: { firstName, lastName: rest.join(' '), ...ADDRESS },
          tags,
          note: note || `e2e ${run}`,
        },
        options: { inventoryBehaviour: 'BYPASS', sendReceipt: false, sendFulfillmentReceipt: false },
      }));
      const order = data.orderCreate.order;
      return { ...order, number: order.name, total: Number(order.totalPriceSet.shopMoney.amount) };
    },

    async ship(order, lineItemIndexes, tracking) {
      const fulfillmentOrder = order.fulfillmentOrders.nodes[0];
      const wanted = lineItemIndexes.map(index => order.lineItems.nodes[index].id);
      const lines = fulfillmentOrder.lineItems.nodes.filter(line => wanted.includes(line.lineItem.id));
      await shopify('seed_fulfillment', {
        fulfillment: {
          notifyCustomer: false,
          trackingInfo: tracking,
          lineItemsByFulfillmentOrder: [{ fulfillmentOrderId: fulfillmentOrder.id, fulfillmentOrderLineItems: lines.map(line => ({ id: line.id, quantity: line.remainingQuantity })) }],
        },
      });
    },

    async refund(order, amount) {
      const sale = order.transactions.find(transaction => transaction.kind === 'SALE');
      await shopify('seed_refund', {
        key: randomUUID(),
        input: { orderId: order.id, notify: false, transactions: [{ orderId: order.id, parentId: sale.id, kind: 'REFUND', gateway: sale.gateway, amount: amount.toFixed(2) }] },
      });
    },

    async cancel(order) {
      await shopify('seed_cancel', { orderId: order.id });
    },

    // The order as the store holds it now.
    async read(order) {
      return (await shopify('seeded_order', { id: order.id })).order;
    },

    // Orders of this run, e.g. to find a replacement the helpdesk created.
    async tagged(tag) {
      return (await shopify('seeded_orders', { query: `tag:'${tag}'`, after: null })).orders.nodes;
    },

    async clean() {
      const removed = { orders: 0, customers: 0, kept: [] };
      const replacements = (await shopify('seeded_orders', { query: `tag:'replacement'`, after: null })).orders.nodes;
      const own = (await shopify('seeded_orders', { query: `tag:'e2e-${run}'`, after: null })).orders.nodes.filter(order => order.tags.includes(`e2e-${run}`));
      // A replacement carries the tags of the order it was copied from.
      const orders = [...own, ...replacements.filter(order => order.tags.includes(`e2e-${run}`) && !own.find(known => known.id === order.id))];
      for (const order of orders) {
        try {
          if (!order.cancelledAt) await shopify('seed_cancel', { orderId: order.id }).catch(() => {});
          await new Promise(resolve => setTimeout(resolve, 1200));
          await shopify('delete_order', { orderId: order.id });
          removed.orders += 1;
        } catch (error) {
          removed.kept.push(`${order.name}: ${error.message.slice(0, 120)}`);
        }
      }
      const customers = (await shopify('seeded_customers', { query: `tag:'e2e-${run}'` })).customers.nodes.filter(customer => customer.tags.includes(`e2e-${run}`));
      for (const customer of customers) {
        try {
          await shopify('delete_customer', { id: customer.id });
          removed.customers += 1;
        } catch (error) {
          removed.kept.push(`${customer.displayName}: ${error.message.slice(0, 120)}`);
        }
      }
      return removed;
    },
  };
  return store;
}
