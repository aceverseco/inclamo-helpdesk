// What the dashboard knows about the account's store and about the order each
// conversation is tied to. The Orders section writes here what it loads; the
// reply variables read it. Nothing is kept beyond the page.
import { reactive } from 'vue';
import InclamoAPI from './api';

const state = reactive({ connections: {}, tied: {} });
const asked = new Set();

// Keys carry the account, read from the address like every request of the dashboard.
const accountKey = () => InclamoAPI.url || '';
const conversationKey = conversationId => `${accountKey()}#${conversationId}`;

const working = connection => Boolean(connection?.connected) && connection.status === 'working';

// Called by the Orders section with every answer of the panel.
export const notePanel = (conversationId, panel) => {
  if (panel?.connection) state.connections[accountKey()] = working(panel.connection);
  // An answer without the key (the store did not answer) says nothing about the tie.
  if (panel && 'marked_order' in panel) state.tied[conversationKey(conversationId)] = panel.marked_order || null;
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

// The order a conversation is tied to as the panel last read it: the order,
// null when none is tied, undefined when the panel has not read it.
export const tiedOrder = conversationId => state.tied[conversationKey(conversationId)];

export const forgetOrderState = () => {
  asked.clear();
  Object.keys(state.connections).forEach(key => delete state.connections[key]);
  Object.keys(state.tied).forEach(key => delete state.tied[key]);
};
