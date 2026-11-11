// Fixture-only Shopify. No upstream URL, credential, forwarding or fetch path.
import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';

const fixture = name => JSON.parse(readFileSync(new URL(`../../custom/spec/fixtures/shopify/${name}.json`, import.meta.url))).data;
const customers = fixture('customers_search_one');
const orders = fixture('customer_orders');
const log = [];
const scopes = ['read_customers', 'read_orders', 'write_orders', 'write_draft_orders', 'read_products'];

createServer(async (request, response) => {
  response.setHeader('Content-Type', 'application/json');
  if (request.url === '/health') return response.end(JSON.stringify({ synthetic: true }));
  if (request.url === '/requests') return response.end(JSON.stringify(log));
  let raw = '';
  for await (const chunk of request) raw += chunk;
  try {
    const { query, variables = {} } = JSON.parse(raw);
    // Documents arrive with their comments; a comment may say "query" too.
    const operation = query.replace(/^\s*#.*$/gm, '').match(/\b(?:query|mutation)\s+(\w+)/)?.[1];
    let data;
    if (operation === 'customers_search') data = customers;
    if (operation === 'customer_orders') data = orders;
    if (operation === 'order_details') data = { order: orders.customer.orders.nodes.find(order => order.id === variables.id) || null };
    if (operation === 'orders_by_number') data = { orders: { nodes: orders.customer.orders.nodes.filter(order => variables.query?.includes(order.name)) } };
    if (operation === 'customer_data_probe') data = { customers: { nodes: [] } };
    // The matched customer has no unpaid draft orders.
    if (operation === 'awaiting_payment') data = fixture('awaiting_payment_none');
    // What a full refund would return: everything received less what was
    // refunded, through one synthetic payment. The cancel dialog asks it first.
    if (operation === 'refund_suggestion') {
      const order = orders.customer.orders.nodes.find(node => node.id === variables.id);
      if (order) {
        const currencyCode = order.totalReceivedSet.shopMoney.currencyCode;
        const left = Number(order.totalReceivedSet.shopMoney.amount) - Number(order.totalRefundedSet?.shopMoney?.amount || 0);
        const money = amount => ({ shopMoney: { amount: amount.toFixed(2), currencyCode } });
        data = {
          order: {
            id: order.id, name: order.name, currencyCode,
            suggestedRefund: {
              amountSet: money(left), maximumRefundableSet: money(left),
              shipping: { amountSet: money(0), maximumRefundableSet: money(0) },
              refundLineItems: [],
              suggestedTransactions: [{ gateway: 'manual', formattedGateway: 'Manual', kind: 'SUGGESTED_REFUND', amountSet: money(left), maximumRefundableSet: money(left), parentTransaction: { id: 'gid://shopify/OrderTransaction/1' } }],
            },
          },
        };
      }
    }
    if (operation === 'shop_info') data = {
      shop: { name: 'Example Store', myshopifyDomain: 'theme-fixture.myshopify.com', currencyCode: 'UAH', plan: { publicDisplayName: 'Development', partnerDevelopment: true } },
      currentAppInstallation: { accessScopes: scopes.map(handle => ({ handle })) },
    };
    log.push({ operation, supported: !!data });
    response.end(JSON.stringify(data ? { data } : { errors: [{ message: `Unsupported synthetic operation: ${operation}` }] }));
  } catch {
    response.statusCode = 400;
    response.end(JSON.stringify({ errors: [{ message: 'Invalid synthetic request' }] }));
  }
}).listen(8080, '0.0.0.0');
