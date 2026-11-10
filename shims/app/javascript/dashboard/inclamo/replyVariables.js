// The order variables of replies: `{{order.number}}` and the others. Chatwoot's
// variable list offers them and its editor resolves them through the reply
// variables seam. The values are the ones the server computed for the panel
// (`marked_order.variables`), so the editor and the server say the same.
import { t } from './i18n';
import { storeConnected, knownOrder } from './orderState';

export const ORDER_VARIABLES = ['number', 'date', 'total', 'payment_status', 'fulfillment_status', 'tracking_number', 'tracking_link', 'status_link', 'items'];
const offered = () => (storeConnected() ? ORDER_VARIABLES.map(name => ({ key: `order.${name}`, description: t(`REPLY_VARIABLES.${name}`) })) : []);

// With an order the panel knows (tied, or the customer's latest) every
// variable has a key: its value, or '' for what the order does not have. While
// the panel has not been read the keys are there with empty values: the editor
// leaves such a variable as a placeholder and the server fills it on send.
// Only when the panel found no order are there no keys, and the editor warns
// before sending.
const values = ({ conversation }) => {
  if (!conversation?.id || !storeConnected()) return {};
  const order = knownOrder(conversation.id);
  if (order === null) return {};
  return Object.fromEntries(ORDER_VARIABLES.map(name => [`order.${name}`, order?.variables?.[name] ?? '']));
};

export default [{ variables: offered, values }];
