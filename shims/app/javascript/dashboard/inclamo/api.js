/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class InclamoAPI extends ApiClient {
  constructor() {
    super('inclamo', { accountScoped: true });
  }

  conversation(id) {
    return `${this.url}/shopify/conversations/${id}`;
  }

  getConnection() {
    return axios.get(`${this.url}/shopify/connection`);
  }

  connect(payload) {
    return axios.post(`${this.url}/shopify/connection`, payload);
  }

  recheck() {
    return axios.post(`${this.url}/shopify/connection/recheck`);
  }

  disconnect() {
    return axios.delete(`${this.url}/shopify/connection`);
  }

  getRoles() {
    return axios.get(`${this.url}/order_roles`);
  }

  giveRole(userId) {
    return axios.post(`${this.url}/order_roles`, { user_id: userId });
  }

  takeRole(userId) {
    return axios.delete(`${this.url}/order_roles/${userId}`);
  }

  getRulePresets() {
    return axios.get(`${this.url}/rule_presets`);
  }

  // payload: { active, value } — the value only for a preset that needs one.
  switchRulePreset(key, payload) {
    return axios.put(`${this.url}/rule_presets/${key}`, payload);
  }

  getPanel(conversationId, after) {
    return axios.get(`${this.conversation(conversationId)}/panel`, { params: after ? { after } : {} });
  }

  lookup(conversationId, number) {
    return axios.get(`${this.conversation(conversationId)}/lookup`, { params: { number } });
  }

  chooseCustomer(conversationId, customerId) {
    return axios.post(`${this.conversation(conversationId)}/customer`, { customer_id: customerId });
  }

  forgetCustomer(conversationId) {
    return axios.delete(`${this.conversation(conversationId)}/customer`);
  }

  markOrder(conversationId, orderId) {
    return axios.put(`${this.conversation(conversationId)}/order`, { order_id: orderId });
  }

  clearOrder(conversationId) {
    return axios.delete(`${this.conversation(conversationId)}/order`);
  }

  // The tags and note of an order ({ order_id }) or a customer ({ customer_id })
  // as the store holds them now, past the panel's cache.
  marks(conversationId, target) {
    return axios.get(`${this.conversation(conversationId)}/marks`, { params: target });
  }

  // What the order steps of a macro would do in a conversation.
  macroPreview(macroId, conversationId) {
    return axios.post(`${this.url}/macro_previews`, { macro_id: macroId, conversation_id: conversationId });
  }

  // The agent's "Run" for the macro as the preview showed it (`digest`).
  confirmMacro(macroId, conversationId, digest) {
    return axios.post(`${this.url}/macro_confirmations`, { macro_id: macroId, conversation_id: conversationId, digest });
  }

  // Chatwoot's macro as the server holds it now.
  getMacro(macroId) {
    return axios.get(`${this.baseUrl()}/macros/${macroId}`);
  }

  refundPreview(conversationId, orderId, params) {
    return axios.post(`${this.conversation(conversationId)}/actions/refund_preview`, { order_id: orderId, params });
  }

  // What an order becomes after an edit of its items, as the store calculates
  // it; nothing is changed.
  editItemsPreview(conversationId, orderId, params) {
    return axios.post(`${this.conversation(conversationId)}/actions/edit_items_preview`, { order_id: orderId, params });
  }

  // The store's catalogue by title or SKU; `after` asks for the next page.
  searchProducts(conversationId, { query, after } = {}) {
    return axios.get(`${this.conversation(conversationId)}/products`, { params: after ? { query, after } : { query } });
  }

  // What a new order would cost, as the store calculates it; nothing is created.
  newOrderPreview(conversationId, params) {
    return axios.post(`${this.conversation(conversationId)}/actions/new_order_preview`, { params });
  }

  // The items of an order of the customer, to start a new order from.
  newOrderPrefill(conversationId, orderId) {
    return axios.get(`${this.conversation(conversationId)}/actions/new_order_prefill`, { params: { order_id: orderId } });
  }

  // Resolves with the action record whatever its outcome: a refusal is an
  // answer, not a failure of the request.
  performAction(conversationId, payload) {
    return axios
      .post(`${this.conversation(conversationId)}/actions`, payload)
      .catch(error => {
        if (error.response?.data?.outcome) return error.response;
        throw error;
      });
  }
}

export default new InclamoAPI();
