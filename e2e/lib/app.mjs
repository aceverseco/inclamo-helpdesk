// The store app's side of the end-to-end tests: the stand-in app of
// e2e/stand-in-app/server.mjs, which signs the provisioning calls of
// docs/app-provisioning.md and the storefront chat's calls of
// docs/app-storefront-chat.md and serves the storefront page with the chat,
// and a person of a provisioned account, who has no place among the users
// e2e/setup.rb prepares.
const appUrl = () => process.env.E2E_APP_URL || 'http://stand-in-app:8091';
const helpdeskUrl = () => process.env.HELPDESK_URL || 'http://localhost:3000';

async function control(name, body) {
  const response = await fetch(`${appUrl()}/__e2e/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  if (!response.ok) throw new Error(`the stand-in app answered ${response.status} to ${name}`);
  const answer = await response.json();
  if (answer.status === 503 && answer.body?.error === 'stand_in_has_no_secret') throw new Error('the stand-in app was started without the provisioning secret');
  return answer;
}

// Each answers { status, body, retry_after, provisioning, request_id } as the
// helpdesk gave it; `provisioning` is the X-Inclamo-Provisioning header, null
// when the answer has none. Switches: wrong_signature, stale, request_id,
// helpdesk_url. `provision` also takes `store_access_url`.
export const storeApp = {
  provision: (domain, options = {}) => control('provision', { domain, ...options }),
  status: (domain, switches = {}) => control('status', { domain, ...switches }),
  removal: (domain, switches = {}) => control('removal', { domain, ...switches }),
  // The store has its storefront inbox; options: storefront_url, body, switches.
  storefrontChat: (domain, options = {}) => control('storefront-chat', { domain, ...options }),
  storefrontChatStatus: (domain, switches = {}) => control('storefront-chat-status', { domain, ...switches }),
};

// The store's storefront page of the stand-in app: it loads the widget with
// the two values the helpdesk last answered for the store.
export const storefrontUrl = domain => `${appUrl()}/storefront/${domain}`;

// The helpdesk that was given no provisioning secret (dev/docker-compose.e2e.yaml).
export const unprovisionedUrl = () => process.env.E2E_UNPROVISIONED_URL || 'http://rails-unprovisioned:3000';

const json = async response => {
  const text = await response.text();
  try {
    return text ? JSON.parse(text) : null;
  } catch (error) {
    return text;
  }
};

// Signing in on the login page's own call; `headers` is the session when it worked.
export async function signInWith(email, password) {
  const response = await fetch(`${helpdeskUrl()}/auth/sign_in`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }) });
  const headers = Object.fromEntries(['access-token', 'client', 'uid', 'expiry', 'token-type'].map(name => [name, response.headers.get(name)]));
  return { status: response.status, headers: response.ok ? headers : null };
}

// Setting a password with the link of an answer, as the password page does.
export async function setPassword(link, password) {
  const token = new URL(link).searchParams.get('reset_password_token');
  const response = await fetch(`${helpdeskUrl()}/auth/password`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ reset_password_token: token, password, password_confirmation: password }),
  });
  return response.status;
}

// The helpdesk's API as a signed-in person: paths are whole ("/api/v1/...").
export async function personApi(email, password) {
  const session = await signInWith(email, password);
  if (!session.headers) throw new Error(`could not sign in as ${email}: HTTP ${session.status}`);
  const call = async (method, path, data) => {
    const response = await fetch(`${helpdeskUrl()}${path}`, {
      method,
      headers: { ...session.headers, 'Content-Type': 'application/json' },
      body: data === undefined ? undefined : JSON.stringify(data),
    });
    return { status: response.status, body: await json(response) };
  };
  const api = {
    get: path => call('GET', path),
    post: (path, data) => call('POST', path, data),
    patch: (path, data) => call('PATCH', path, data),
    delete: path => call('DELETE', path),
    // The same person with paths inside one account ("/inboxes"), which is
    // what the helpers of e2e/lib/website.mjs take.
    within: accountId => {
      const base = `/api/v1/accounts/${accountId}`;
      return {
        accountId,
        get: path => call('GET', `${base}${path}`),
        post: (path, data) => call('POST', `${base}${path}`, data),
        patch: (path, data) => call('PATCH', `${base}${path}`, data),
        delete: path => call('DELETE', `${base}${path}`),
      };
    },
    profile: async () => (await api.get('/api/v1/profile')).body,
    // The person's accounts as their profile lists them: [{ id, name, role, ... }].
    accounts: async () => (await api.profile()).accounts || [],
    // Whether the account opens for them: the status of its conversation list.
    opens: async accountId => (await api.get(`/api/v1/accounts/${accountId}/conversations?status=all&assignee_type=all`)).status,
    conversationCount: async accountId =>
      (await api.get(`/api/v1/accounts/${accountId}/conversations?status=all&assignee_type=all`)).body?.data?.meta?.all_count,
    members: async accountId => ((await api.get(`/api/v1/accounts/${accountId}/agents`)).body || []).map(member => ({ email: member.email, role: member.role })),
    // `count` conversations of invented shoppers in an API inbox of the account.
    async fill(accountId, count, tag) {
      const base = `/api/v1/accounts/${accountId}`;
      const inbox = (await api.post(`${base}/inboxes`, { name: 'Store chat', channel: { type: 'api', webhook_url: '' } })).body;
      for (let index = 1; index <= count; index += 1) {
        const made = (await api.post(`${base}/contacts`, { inbox_id: inbox.id, name: `Shopper ${index}`, email: `shopper-${tag}-${index}@example.test` })).body.payload;
        const created = await api.post(`${base}/conversations`, {
          source_id: made.contact_inbox.source_id,
          inbox_id: inbox.id,
          contact_id: made.contact.id,
          message: { content: `Question ${index} of ${tag}`, message_type: 'incoming' },
        });
        if (created.status !== 200) throw new Error(`conversation ${index} was not created: HTTP ${created.status}`);
      }
      return inbox;
    },
  };
  return api;
}
