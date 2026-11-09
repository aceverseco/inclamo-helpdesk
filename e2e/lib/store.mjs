// Store data for the end-to-end tests, created through the seeding app and
// tagged per run so that it can be removed again. Nothing untagged is touched.
import { randomUUID } from 'node:crypto';
import { connect } from './shopify.mjs';

const money = (amount, currencyCode) => ({ shopMoney: { amount: amount.toFixed(2), currencyCode } });
const ADDRESS = { address1: '1 Example Street', city: 'Kyiv', countryCode: 'UA', zip: '01001' };
// The tests refund 20 of an order of one item, so every product they order
// costs clearly more than that.
const MIN_PRICE = 50;
const CATALOG = [['E2E Mug', '120.00'], ['E2E Notebook', '185.00'], ['E2E Tote Bag', '250.00']];

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
  let catalog = await shopify('seed_catalog');
  const currency = catalog.shop.currencyCode;
  const variantsOf = found => found.products.nodes.flatMap(product => product.variants.nodes.slice(0, 1)).filter(variant => Number(variant.price) >= MIN_PRICE);
  // A store that was just created has nothing to sell, and another may sell
  // only cheap things: give it the three products the tests order. They stay
  // as the store's catalogue.
  for (const [title, price] of CATALOG.slice(variantsOf(catalog).length)) {
    await shopify('seed_product', {
      input: {
        title,
        status: 'ACTIVE',
        tags: ['e2e-catalog'],
        productOptions: [{ name: 'Title', values: [{ name: 'Default Title' }] }],
        variants: [{ optionValues: [{ optionName: 'Title', name: 'Default Title' }], price, inventoryItem: { tracked: false } }],
      },
    });
  }
  if (variantsOf(catalog).length < 3) {
    // The store's search lags behind what was just created.
    for (let attempt = 0; attempt < 20 && variantsOf(catalog).length < 3; attempt += 1) {
      await new Promise(resolve => setTimeout(resolve, 3_000));
      catalog = await shopify('seed_catalog');
    }
  }
  const variants = variantsOf(catalog);
  if (variants.length < 3) throw new Error('the store needs at least three active products, and creating them did not help');
  let counter = 0;

  const store = {
    run,
    currency,
    domain: shopify.domain,
    shopify,

    async customer(first, { phone = true, email = true, tags: extra = [], note } = {}) {
      counter += 1;
      const number = String(Math.floor(Math.random() * 9000) + 1000);
      const address = email ? `${first}.example.${run}.${counter}@example.com`.toLowerCase() : undefined;
      const data = await shopify('seed_customer', {
        input: { firstName: first, lastName: 'Example', email: address, phone: phone ? `+1500555${number}` : undefined, tags: [...tags, ...extra], note },
      });
      const customer = data.customerCreate.customer;
      return { ...customer, email: address || null, phone: phone ? `+1500555${number}` : null };
    },

    async order(customer, { items = 1, quantity = 1, note, shipping, tags: extra = [] } = {}) {
      const chosen = variants.slice(0, items);
      const total = chosen.reduce((sum, variant) => sum + Number(variant.price) * quantity, 0) + (shipping || 0);
      const [firstName, ...rest] = customer.displayName.split(' ');
      const data = await paced(() => shopify('seed_order', {
        order: {
          customer: { toAssociate: { id: customer.id } },
          lineItems: chosen.map(variant => ({ variantId: variant.id, quantity })),
          financialStatus: 'PAID',
          transactions: [{ kind: 'SALE', status: 'SUCCESS', gateway: 'manual', amountSet: money(total, currency) }],
          shippingAddress: { firstName, lastName: rest.join(' '), ...ADDRESS },
          shippingLines: shipping ? [{ title: 'E2E shipping', priceSet: money(shipping, currency) }] : undefined,
          tags: [...tags, ...extra],
          note: note || `e2e ${run}`,
        },
        options: { inventoryBehaviour: 'BYPASS', sendReceipt: false, sendFulfillmentReceipt: false },
      }));
      const order = data.orderCreate.order;
      return { ...order, number: order.name, total: Number(order.totalPriceSet.shopMoney.amount) };
    },

    // A product of this run whose stock the store tracks: `units` at the
    // store's first location. clean() removes it.
    async trackedProduct(title = 'E2E Tracked Mug', { units = 10 } = {}) {
      const location = catalog.locations.nodes[0].id;
      const data = await shopify('seed_tracked_product', {
        input: {
          title: `${title} ${run}`,
          status: 'ACTIVE',
          tags,
          productOptions: [{ name: 'Title', values: [{ name: 'Default Title' }] }],
          variants: [{ optionValues: [{ optionName: 'Title', name: 'Default Title' }], price: '80.00', inventoryItem: { tracked: true }, inventoryQuantities: [{ locationId: location, name: 'available', quantity: units }] }],
        },
      });
      const product = data.productSet.product;
      return { id: product.id, title: product.title, variantId: product.variants.nodes[0].id, price: Number(product.variants.nodes[0].price), location };
    },

    // Units of a variant available at a location, as the store counts them.
    async available(variantId, location = catalog.locations.nodes[0].id) {
      const level = (await shopify('seed_stock', { id: variantId, location })).productVariant.inventoryItem.inventoryLevel;
      return level?.quantities.find(quantity => quantity.name === 'available')?.quantity ?? null;
    },

    // An order completed from a draft, paid. The store lets the helpdesk's
    // app edit such an order, not one another app made with orderCreate.
    // `lines` adds items beyond the first `items` of the catalogue, e.g. a
    // tracked product: [{ variantId, quantity }].
    async draftOrder(customer, { items = 1, quantity = 1, lines = [], note } = {}) {
      const [firstName, ...rest] = customer.displayName.split(' ');
      const lineItems = [...variants.slice(0, items).map(variant => ({ variantId: variant.id, quantity })), ...lines];
      const draft = await shopify('seed_draft_order', {
        input: { customerId: customer.id, lineItems, shippingAddress: { firstName, lastName: rest.join(' '), ...ADDRESS }, tags, note: note || `e2e ${run}` },
      });
      const data = await paced(() => shopify('seed_draft_complete', { id: draft.draftOrderCreate.draftOrder.id }));
      const order = data.draftOrderComplete.draftOrder.order;
      return { ...order, number: order.name, total: Number(order.totalPriceSet.shopMoney.amount) };
    },

    // Ships the chosen lines in full, each from the fulfilment order that holds it.
    async ship(order, lineItemIndexes, tracking) {
      const wanted = lineItemIndexes.map(index => order.lineItems.nodes[index].id);
      for (const fulfillmentOrder of order.fulfillmentOrders.nodes) {
        const lines = fulfillmentOrder.lineItems.nodes.filter(line => wanted.includes(line.lineItem.id) && line.remainingQuantity > 0);
        // An empty list would ship the whole fulfilment order.
        if (lines.length === 0) continue;
        await shopify('seed_fulfillment', {
          fulfillment: {
            notifyCustomer: false,
            trackingInfo: tracking,
            lineItemsByFulfillmentOrder: [{ fulfillmentOrderId: fulfillmentOrder.id, fulfillmentOrderLineItems: lines.map(line => ({ id: line.id, quantity: line.remainingQuantity })) }],
          },
        });
      }
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

    // Waits until the store's customer search, which lags behind what was just
    // created, shows the customer the way `accept` wants: { orders, spent,
    // tags, latest: { name, fulfillment } }.
    async known(customer, accept, { timeout = 240_000 } = {}) {
      const deadline = Date.now() + timeout;
      for (;;) {
        const node = (await shopify('seeded_customer_facts', { query: `email:"${customer.email}"` })).customers.nodes[0];
        const latest = node?.orders.nodes[0];
        const facts = node && {
          orders: Number(node.numberOfOrders),
          spent: Number(node.amountSpent.amount),
          tags: node.tags,
          latest: latest ? { name: latest.name, fulfillment: latest.displayFulfillmentStatus } : null,
        };
        if (facts && accept(facts)) return facts;
        if (Date.now() > deadline) throw new Error(`the store still does not show ${customer.email} as expected: ${JSON.stringify(facts)}`);
        await new Promise(resolve => setTimeout(resolve, 4_000));
      }
    },

    // The order as the store holds it now.
    async read(order) {
      return (await shopify('seeded_order', { id: order.id })).order;
    },

    // The customer's tags and note as the store holds them now.
    async readCustomer(customer) {
      return (await shopify('seeded_customer', { id: customer.id })).customer;
    },

    // Orders of this run, e.g. to find a replacement the helpdesk created.
    async tagged(tag) {
      return (await shopify('seeded_orders', { query: `tag:'${tag}'`, after: null })).orders.nodes;
    },

    // Two products of this run for the reply inserts, each with its own SKU:
    // `shown` is published in the online store, `hidden` is active but not
    // published there. Removed by clean(). A development store is
    // password-protected, so the store gives neither a storefront link;
    // `shown.url` is the address it has once the store opens, for the proxy
    // to answer with as a live store does (patch `storefront`).
    async storefrontProducts() {
      const online = (await shopify('seed_publications')).publications.nodes.find(publication => publication.name === 'Online Store');
      if (!online) throw new Error('the store has no Online Store sales channel');
      const made = {};
      for (const [key, label, publish] of [['shown', 'Shown Mug', true], ['hidden', 'Hidden Mug', false]]) {
        const sku = `E2E-${run}-${key}`.toUpperCase();
        const data = await shopify('seed_product', {
          input: {
            title: `E2E ${run} ${label}`,
            status: 'ACTIVE',
            tags,
            productOptions: [{ name: 'Title', values: [{ name: 'Default Title' }] }],
            variants: [{ optionValues: [{ optionName: 'Title', name: 'Default Title' }], price: '150.00', sku, inventoryItem: { tracked: false } }],
          },
        });
        const id = data.productSet.product.id;
        if (publish) await shopify('seed_publish', { id, input: [{ publicationId: online.id }] });
        made[key] = { id, title: `E2E ${run} ${label}`, sku, price: 150 };
      }
      const shown = (await shopify('seeded_product_publication', { id: made.shown.id, publicationId: online.id })).product;
      if (!shown.publishedOnPublication) throw new Error('the product was not published in the online store');
      made.shown.url = shown.onlineStorePreviewUrl;
      // The store's search lags behind what was just made.
      for (let attempt = 0; attempt < 30; attempt += 1) {
        const nodes = (await shopify('seeded_products', { query: `tag:'e2e-${run}'` })).products.nodes;
        if (nodes.some(node => node.id === made.shown.id) && nodes.some(node => node.id === made.hidden.id)) return made;
        await new Promise(resolve => setTimeout(resolve, 2_000));
      }
      throw new Error('the store search does not show the products of the run after a minute');
    },

    // Discount codes the helpdesk made from this run's presets: their titles
    // start with the preset's name, and the tests name presets after the run.
    async discounts() {
      const prefix = `E2E-${run}`;
      const nodes = (await shopify('seeded_discounts', { query: `title:${prefix}*` })).codeDiscountNodes.nodes;
      return nodes.filter(node => (node.codeDiscount?.title || '').startsWith(prefix));
    },

    async clean() {
      const removed = { orders: 0, customers: 0, kept: [] };
      const replacements = (await shopify('seeded_orders', { query: `tag:'replacement'`, after: null })).orders.nodes;
      const own = (await shopify('seeded_orders', { query: `tag:'e2e-${run}'`, after: null })).orders.nodes.filter(order => order.tags.includes(`e2e-${run}`));
      // A replacement the helpdesk created carries only its own tag: it is
      // known by its note, which names the order of this run it replaces.
      const replaces = order => own.some(known => (order.note || '').endsWith(` ${known.name}`));
      const orders = [...own, ...replacements.filter(order => !own.find(known => known.id === order.id) && (order.tags.includes(`e2e-${run}`) || replaces(order)))];
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
      // Drafts the helpdesk made for the run's customers carry its own tag, not the run's;
      // the drafts the seed completed into orders are theirs too.
      removed.drafts = 0;
      for (const customer of customers) {
        const drafts = (await shopify('seeded_drafts', { query: `customer_id:${customer.id.split('/').pop()}` })).draftOrders.nodes;
        for (const draft of drafts) {
          try {
            await shopify('delete_draft', { input: { id: draft.id } });
            removed.drafts += 1;
          } catch (error) {
            removed.kept.push(`${draft.name}: ${error.message.slice(0, 120)}`);
          }
        }
      }
      for (const customer of customers) {
        try {
          await shopify('delete_customer', { id: customer.id });
          removed.customers += 1;
        } catch (error) {
          removed.kept.push(`${customer.displayName}: ${error.message.slice(0, 120)}`);
        }
      }
      // Discount codes made from this run's presets, and the run's own products.
      removed.discounts = 0;
      for (const node of await store.discounts()) {
        try {
          await shopify('delete_discount', { id: node.id });
          removed.discounts += 1;
        } catch (error) {
          removed.kept.push(`${node.codeDiscount?.title}: ${error.message.slice(0, 120)}`);
        }
      }
      removed.products = 0;
      const products = (await shopify('seeded_products', { query: `tag:'e2e-${run}'` })).products.nodes.filter(product => product.tags.includes(`e2e-${run}`));
      for (const product of products) {
        try {
          await shopify('delete_product', { input: { id: product.id } });
          removed.products += 1;
        } catch (error) {
          removed.kept.push(`${product.title}: ${error.message.slice(0, 120)}`);
        }
      }
      return removed;
    },
  };
  return store;
}
