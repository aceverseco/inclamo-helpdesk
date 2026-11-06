// A proxy between the helpdesk and Shopify for the end-to-end tests. Without
// rules it forwards everything untouched. A test adds rules to make the store
// misbehave on purpose: not answer, lose an answer, refuse a token, or answer
// with fewer scopes than it really granted.
//
//   POST   /__e2e/rules   { match: { operation?, path? }, effect, times?, value? }
//   DELETE /__e2e/rules   remove every rule
//   GET    /__e2e/log     what was forwarded since the last DELETE /__e2e/log
//   DELETE /__e2e/log
//
// Effects:
//   hang          never answer (the helpdesk gives up after its time limit)
//   lose_answer   let Shopify act, then never answer
//   status        answer `value.status` with `value.body`, without asking Shopify
//   patch         let Shopify answer, then change the answer by `value.patch`:
//                 scopes (value.scopes), customers_denied, orders_denied,
//                 second_customer, no_fulfillment_orders,
//                 expires_in (value.seconds), job_pending, not_cancelled
//   refuse        answer as the store does when it refuses a mutation: HTTP 200
//                 with `value.message` as a user error of `value.mutation`,
//                 without asking Shopify, so that nothing changes in the store
import { createServer } from 'node:http';

const port = Number(process.env.PORT || 8080);
let rules = [];
let log = [];

const readBody = request =>
  new Promise(resolve => {
    const chunks = [];
    request.on('data', chunk => chunks.push(chunk));
    request.on('end', () => resolve(Buffer.concat(chunks)));
  });

const operationOf = body => {
  try {
    return JSON.parse(body.toString('utf8')).query.match(/^\s*(?:#[^\n]*\n\s*)*(?:query|mutation)\s+(\w+)/)?.[1] || null;
  } catch (error) {
    return null;
  }
};

const takeRule = (path, operation) => {
  const index = rules.findIndex(rule => (!rule.match.path || rule.match.path === path) && (!rule.match.operation || rule.match.operation === operation));
  if (index === -1) return null;
  const rule = rules[index];
  if (rule.times !== null && rule.times !== undefined) {
    rule.times -= 1;
    if (rule.times <= 0) rules.splice(index, 1);
  }
  return rule;
};

// The store's refusal of a root field, as recorded from a development store.
const denied = (path, object = 'Customer') => ({
  errors: [{ message: `This app is not approved to access the ${object} object.`, extensions: { code: 'ACCESS_DENIED' }, path }],
  data: null,
});

const patches = {
  scopes: (payload, value) => {
    if (payload.data?.currentAppInstallation) payload.data.currentAppInstallation.accessScopes = value.scopes.map(handle => ({ handle }));
    return payload;
  },
  customers_denied: payload => (payload.data && ('customers' in payload.data || 'customer' in payload.data) ? denied(['customers']) : payload),
  orders_denied: payload => (payload.data && 'orders' in payload.data ? denied(['orders'], 'Order') : payload),
  second_customer: payload => {
    const nodes = payload.data?.customers?.nodes;
    if (nodes?.length === 1) nodes.push({ ...nodes[0], id: `${nodes[0].id}9`, displayName: 'Mia Example' });
    return payload;
  },
  // An order whose fulfilment orders the app is not shown.
  no_fulfillment_orders: payload => {
    if (payload.data?.order?.fulfillmentOrders) payload.data.order.fulfillmentOrders.nodes = [];
    return payload;
  },
  expires_in: (payload, value) => (payload.access_token ? { ...payload, expires_in: value.seconds } : payload),
  job_pending: payload => {
    if (payload.data?.job) payload.data.job.done = false;
    if (payload.data?.orderCancel?.job) payload.data.orderCancel.job.done = false;
    return payload;
  },
  not_cancelled: payload => {
    if (payload.data?.order) payload.data.order.cancelledAt = null;
    return payload;
  },
};

const json = (response, status, body) => {
  response.writeHead(status, { 'Content-Type': 'application/json' });
  response.end(JSON.stringify(body));
};

const control = async (request, response, path) => {
  if (path === '/__e2e/rules' && request.method === 'POST') {
    const rule = JSON.parse((await readBody(request)).toString('utf8'));
    rules.push({ match: {}, times: null, ...rule });
    return json(response, 201, { rules: rules.length });
  }
  if (path === '/__e2e/rules' && request.method === 'DELETE') {
    rules = [];
    return json(response, 200, { rules: 0 });
  }
  if (path === '/__e2e/log' && request.method === 'GET') return json(response, 200, { log });
  if (path === '/__e2e/log' && request.method === 'DELETE') {
    log = [];
    return json(response, 200, { log: [] });
  }
  return json(response, 404, { error: 'unknown control request' });
};

createServer(async (request, response) => {
  const path = new URL(request.url, 'http://proxy').pathname;
  if (path.startsWith('/__e2e/')) return control(request, response, path);

  const shop = request.headers['x-shopify-shop-domain'];
  if (!shop || !/^[a-z0-9][a-z0-9-]*\.myshopify\.com$/.test(shop)) return json(response, 400, { error: 'the request does not name a shop' });

  const body = await readBody(request);
  const operation = operationOf(body);
  const rule = takeRule(path, operation);
  const entry = { path, operation, effect: rule?.effect || 'forward', at: new Date().toISOString() };
  log.push(entry);

  if (rule?.effect === 'hang') return undefined;
  if (rule?.effect === 'refuse') {
    const errors = rule.value.errorsKey || 'userErrors';
    return json(response, 200, { data: { [rule.value.mutation]: { ...(rule.value.empty || {}), [errors]: [{ field: [rule.value.field || 'id'], message: rule.value.message }] } } });
  }
  if (rule?.effect === 'status') {
    response.writeHead(rule.value.status, { 'Content-Type': rule.value.contentType || 'application/json' });
    return response.end(typeof rule.value.body === 'string' ? rule.value.body : JSON.stringify(rule.value.body ?? {}));
  }

  const headers = { ...request.headers };
  delete headers.host;
  delete headers['content-length'];
  delete headers.connection;
  let upstream;
  try {
    upstream = await fetch(`https://${shop}${request.url}`, { method: request.method, headers, body: ['GET', 'HEAD'].includes(request.method) ? undefined : body });
  } catch (error) {
    entry.effect = `upstream failed: ${error.message}`;
    return json(response, 502, { error: 'the proxy could not reach Shopify' });
  }
  let text = await upstream.text();
  entry.status = upstream.status;
  if (rule?.effect === 'lose_answer') return undefined;
  if (rule?.effect === 'patch') {
    try {
      text = JSON.stringify(patches[rule.value.patch](JSON.parse(text), rule.value));
    } catch (error) {
      entry.effect = `patch failed: ${error.message}`;
    }
  }
  response.writeHead(upstream.status, { 'Content-Type': upstream.headers.get('content-type') || 'application/json' });
  return response.end(text);
}).listen(port, () => console.log(`shopify proxy for end-to-end tests on ${port}`));
