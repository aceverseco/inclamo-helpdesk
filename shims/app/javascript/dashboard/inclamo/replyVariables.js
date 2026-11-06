// The order variables of replies: `{{order.number}}` and the others. Chatwoot's
// variable list offers them and its editor resolves them through the reply
// variables seam. The values are the ones the server computed for the panel
// (`marked_order.variables`), so the editor and the server say the same.
import { t } from './i18n';
import { storeConnected, tiedOrder } from './orderState';

export const ORDER_VARIABLES = ['number', 'date', 'total', 'payment_status', 'fulfillment_status', 'tracking_number', 'tracking_link', 'status_link', 'items'];
// The conversation attribute that says an order is tied, for a conversation
// whose Orders section has not been read on this page.
const TIED_ATTRIBUTE = 'shopify_order_id';

const offered = () => (storeConnected() ? ORDER_VARIABLES.map(name => ({ key: `order.${name}`, description: t(`REPLY_VARIABLES.${name}`) })) : []);

// With a tied order every variable has a key: its value, or '' for what the
// order does not have or the page has not read. The editor leaves a variable
// with an empty value as a placeholder, and the server fills it on send.
// Without a tied order there are no keys, and the editor warns before sending.
const values = ({ conversation }) => {
  if (!conversation?.id || !storeConnected()) return {};
  const order = tiedOrder(conversation.id);
  const tied = order === undefined ? Boolean(conversation.custom_attributes?.[TIED_ATTRIBUTE]) : order !== null;
  if (!tied) return {};
  return Object.fromEntries(ORDER_VARIABLES.map(name => [`order.${name}`, order?.variables?.[name] ?? '']));
};

export default [{ variables: offered, values }];
