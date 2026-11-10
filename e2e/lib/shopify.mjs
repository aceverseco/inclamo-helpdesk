// Minimal Admin API access for the end-to-end tests: the seeding app's token
// and GraphQL calls with the documents kept in e2e/graphql.
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
export const API_VERSION = readFileSync(join(here, '..', '..', 'custom', 'graphql', 'shopify', 'API_VERSION'), 'utf8').trim();

export function document(name) {
  return readFileSync(join(here, '..', 'graphql', `${name}.graphql`), 'utf8');
}

export function credentials(prefix) {
  const read = key => {
    const value = process.env[`${prefix}_${key}`];
    if (!value) throw new Error(`${prefix}_${key} is not set`);
    return value;
  };
  return { domain: read('DOMAIN'), clientId: read('CLIENT_ID'), clientSecret: read('CLIENT_SECRET') };
}

export async function accessToken({ domain, clientId, clientSecret }) {
  const response = await fetch(`https://${domain}/admin/oauth/access_token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'client_credentials', client_id: clientId, client_secret: clientSecret }),
  });
  if (!response.ok) throw new Error(`token exchange for ${domain} failed: HTTP ${response.status}`);
  return (await response.json()).access_token;
}

// Returns `run(name, variables)`: sends e2e/graphql/<name>.graphql and returns
// its data. GraphQL errors and userErrors of mutations are thrown.
export async function connect(prefix) {
  const { domain, clientId, clientSecret } = credentials(prefix);
  const token = await accessToken({ domain, clientId, clientSecret });
  const run = async (name, variables = {}) => {
    for (let attempt = 0; ; attempt += 1) {
      const response = await fetch(`https://${domain}/admin/api/${API_VERSION}/graphql.json`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Shopify-Access-Token': token },
        body: JSON.stringify({ query: document(name), variables }),
      });
      const payload = await response.json();
      const throttled = (payload.errors || []).some(error => error.extensions?.code === 'THROTTLED');
      if (throttled && attempt < 5) {
        await new Promise(resolve => setTimeout(resolve, 2000));
        continue;
      }
      if (payload.errors) throw new Error(`${name}: ${JSON.stringify(payload.errors).slice(0, 600)}`);
      for (const [field, value] of Object.entries(payload.data || {})) {
        if (value?.userErrors?.length) throw new Error(`${name}.${field}: ${JSON.stringify(value.userErrors)}`);
      }
      return payload.data;
    }
  };
  run.domain = domain;
  return run;
}
