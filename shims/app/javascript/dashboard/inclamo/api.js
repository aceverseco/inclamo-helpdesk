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

  refundPreview(conversationId, orderId, params) {
    return axios.post(`${this.conversation(conversationId)}/actions/refund_preview`, { order_id: orderId, params });
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
