// A ticket about one shopper's data (Shopify asked to erase a shopper, or a
// shopper asked for a copy of their data): a conversation of the account's
// "Data requests" inbox whose custom attribute `inclamo_shopper_request_id`
// names its request. Its card reads the request from the helpdesk and acts on
// it; only the account's administrators may.
/* global axios */
import { getCurrentInstance } from 'vue';
import ApiClient from 'dashboard/api/ApiClient';

class ShopperRequestsAPI extends ApiClient {
  constructor() {
    super('inclamo/shopper_requests', { accountScoped: true });
  }

  read(id) {
    return axios.get(`${this.url}/${id}`);
  }

  // action: delete, hold (with { reason }), lift, answered
  act(id, action, payload = {}) {
    return axios.post(`${this.url}/${id}/${action}`, payload);
  }
}

export const shopperRequestsApi = new ShopperRequestsAPI();

export const shopperRequestIdOf = conversation => {
  const id = Number(conversation?.custom_attributes?.inclamo_shopper_request_id);
  return Number.isInteger(id) && id > 0 ? id : null;
};

// Whether the conversation the sidebar shows is such a ticket. Asked while
// the sidebar renders, so the conversations it reads are tracked.
export const isShopperRequest = conversationId => {
  const getters = getCurrentInstance()?.proxy?.$store?.getters;
  return Boolean(shopperRequestIdOf(getters?.getConversationById?.(conversationId)));
};
