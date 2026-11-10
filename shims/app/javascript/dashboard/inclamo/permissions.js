// Older panel responses only had aggregate rights. A supplied map is always
// authoritative, including explicit false entries.
export const canPerform = (viewer, action) => {
  if (viewer?.permissions) return viewer.permissions[action] === true;
  if (viewer?.administrator) return true;
  return action === 'discount' ? Boolean(viewer?.can_give_discounts) : Boolean(viewer?.can_act_on_orders);
};
export const ACTION_RIGHTS = ['address', 'edit_items', 'cancel', 'refund', 'new_order', 'replacement', 'discount', 'order_tags', 'order_note', 'customer_tags', 'customer_note'];
