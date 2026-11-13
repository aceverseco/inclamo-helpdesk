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

  getAiPolicies() {
    return axios.get(`${this.url}/ai_policies`);
  }

  setAiPolicy(action, payload) {
    return axios.patch(`${this.url}/ai_policies/${action}`, payload);
  }

  getAiProposals(conversationId) {
    return axios.get(`${this.url}/conversations/${conversationId}/ai_proposals`);
  }

  reviewAiProposal(conversationId, id, action, payload) {
    return axios.post(`${this.url}/conversations/${conversationId}/ai_proposals/${id}/${action}`, payload);
  }

  getAiConnection() {
    return axios.get(`${this.url}/ai/connection`);
  }

  connectAi(payload) {
    return axios.post(`${this.url}/ai/connection`, payload);
  }

  disconnectAi() {
    return axios.delete(`${this.url}/ai/connection`);
  }

  articlePreview(id) {
    return axios.post(`${this.url}/article_previews/${id}`);
  }

  cancelPreview(conversationId, orderId, params) {
    return axios.post(`${this.conversation(conversationId)}/actions/cancel_preview`, { order_id: orderId, params });
  }

  getSetup() {
    return axios.get(`${this.url}/setup`);
  }

  reviewSetup(step, digest) {
    return axios.patch(`${this.url}/setup`, { step, digest });
  }

  completeSetup() {
    return axios.post(`${this.url}/setup/complete`);
  }

  getRoles() {
    return axios.get(`${this.url}/order_roles`);
  }

  setPermission(userId, action, enabled) {
    return axios.patch(`${this.url}/order_roles/${userId}`, { action_name: action, enabled });
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

  getDiscountPresets() {
    return axios.get(`${this.url}/discount_presets`);
  }

  createDiscountPreset(preset) {
    return axios.post(`${this.url}/discount_presets`, preset);
  }

  updateDiscountPreset(id, preset) {
    return axios.patch(`${this.url}/discount_presets/${id}`, preset);
  }

  deleteDiscountPreset(id) {
    return axios.delete(`${this.url}/discount_presets/${id}`);
  }

  getDiscountGrants() {
    return axios.get(`${this.url}/discount_grants`);
  }

  giveDiscountGrant(userId) {
    return axios.post(`${this.url}/discount_grants`, { user_id: userId });
  }

  takeDiscountGrant(userId) {
    return axios.delete(`${this.url}/discount_grants/${userId}`);
  }

  getSlaPolicies() {
    return axios.get(`${this.url}/sla_policies`);
  }

  createSlaPolicy(payload) {
    return axios.post(`${this.url}/sla_policies`, payload);
  }

  updateSlaPolicy(id, payload) {
    return axios.patch(`${this.url}/sla_policies/${id}`, payload);
  }

  deleteSlaPolicy(id) {
    return axios.delete(`${this.url}/sla_policies/${id}`);
  }

  reorderSlaPolicies(ids) {
    return axios.post(`${this.url}/sla_policies/reorder`, { ids });
  }

  getSlaSummary(days) {
    return axios.get(`${this.url}/sla_policies/summary`, { params: { days } });
  }

  getConversationSla(conversationId) {
    return axios.get(`${this.url}/conversations/${conversationId}/sla`);
  }

  // The timers of several conversations (at most 100 display ids).
  getConversationSlas(ids) {
    return axios.get(`${this.url}/conversation_slas`, { params: { ids: ids.join(',') } });
  }

  // `accountUrl` keeps a page read in one account from landing in another
  // after the agent switches accounts.
  getPanel(conversationId, after, accountUrl = this.url) {
    return axios.get(`${accountUrl}/shopify/conversations/${conversationId}/panel`, { params: after ? { after } : {} });
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

  // Team queues. Everyone reads the visible ones with their counts; an
  // administrator reads the hidden ones too and changes them.
  getTeamQueues(all = false) {
    return axios.get(`${this.url}/team_queues`, { params: all ? { all: 1 } : {} });
  }

  updateTeamQueue(id, payload) {
    return axios.patch(`${this.url}/team_queues/${id}`, payload);
  }

  reorderTeamQueues(ids) {
    return axios.post(`${this.url}/team_queues/reorder`, { ids });
  }

  restoreTeamQueue(id) {
    return axios.post(`${this.url}/team_queues/${id}/restore`);
  }
}

export default new InclamoAPI();
