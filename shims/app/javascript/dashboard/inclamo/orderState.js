// What the dashboard knows about the account's store and about the order each
// conversation is about. The Orders section writes here what it loads; the
// reply variables read it. Nothing is kept beyond the page.
import { reactive } from 'vue';
import InclamoAPI from './api';

const state = reactive({ connections: {}, orders: {} });
const asked = new Set();

// Keys carry the account, read from the address like every request of the dashboard.
const accountKey = () => InclamoAPI.url || '';
const conversationKey = conversationId => `${accountKey()}#${conversationId}`;

const working = connection => Boolean(connection?.connected) && connection.status === 'working';

// Called by the Orders section with every answer of the panel.
export const notePanel = (conversationId, panel, account = accountKey()) => {
  if (panel?.connection) state.connections[account] = working(panel.connection);
  // The order the conversation is about: the tied one, else the newest of the
  // matched customer's list. An answer without the key (the store did not
  // answer) says nothing about it.
  if (panel && 'marked_order' in panel) state.orders[`${account}#${conversationId}`] = panel.marked_order || panel.orders?.[0] || null;
};

// Whether the account has a working store connection. Asks the server once
// per account; false until the answer is here.
export const storeConnected = () => {
  const account = accountKey();
  if (!asked.has(account)) {
    asked.add(account);
    // Whatever goes wrong with the question, the editor that asked is not disturbed.
    Promise.resolve()
      .then(() => InclamoAPI.getConnection())
      .then(({ data }) => {
        state.connections[account] = working(data);
      })
      .catch(() => {});
  }
  return state.connections[account] === true;
};

// The order a conversation is about as the panel last read it: the order,
// null when the panel found none, undefined when the panel has not read it.
export const knownOrder = conversationId => state.orders[conversationKey(conversationId)];

export const invalidateKnownOrder = (conversationId, account = accountKey()) => {
  delete state.orders[`${account}#${conversationId}`];
};

export const forgetOrderState = () => {
  asked.clear();
  Object.keys(state.connections).forEach(key => delete state.connections[key]);
  Object.keys(state.orders).forEach(key => delete state.orders[key]);
};
