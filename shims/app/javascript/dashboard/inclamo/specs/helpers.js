import { h } from 'vue';

// Chatwoot's dialog, reduced to what the overlay uses: open(), close(), a
// title, a body and a confirm button.
export const DialogStub = {
  name: 'Dialog',
  props: ['title', 'confirmButtonLabel', 'cancelButtonLabel', 'disableConfirmButton', 'isLoading', 'showConfirmButton'],
  emits: ['confirm', 'close'],
  data: () => ({ shown: false }),
  methods: {
    open() {
      this.shown = true;
    },
    close() {
      this.shown = false;
    },
  },
  render() {
    if (!this.shown) return null;
    return h('div', { 'data-testid': 'dialog' }, [
      h('h2', { 'data-testid': 'dialog-title' }, this.title),
      this.$slots.default?.(),
      this.showConfirmButton === false
        ? null
        : h('button', { 'data-testid': 'dialog-confirm', disabled: this.disableConfirmButton, onClick: () => this.$emit('confirm') }, this.confirmButtonLabel),
    ]);
  },
};

export const stubs = { Dialog: DialogStub, Spinner: true };

export const order = (overrides = {}) => ({
  id: 'gid://shopify/Order/1',
  number: '#1001',
  admin_url: 'https://admin.shopify.com/store/example-store/orders/1',
  created_at: '2026-11-05T10:00:00Z',
  cancelled_at: null,
  financial_status: 'PAID',
  fulfillment_status: 'UNFULFILLED',
  currency: 'EUR',
  total: { amount: '54.0', currency: 'EUR' },
  refunded: { amount: '0.0', currency: 'EUR' },
  refundable: { amount: '54.0', currency: 'EUR' },
  items: [
    { id: 'gid://shopify/LineItem/1', title: 'Blue Mug', quantity: 2, refundable_quantity: 2, unit_price: { amount: '12.0', currency: 'EUR' } },
    { id: 'gid://shopify/LineItem/2', title: 'Red Plate', quantity: 1, refundable_quantity: 1, unit_price: { amount: '30.0', currency: 'EUR' } },
  ],
  shipments: [],
  refunds: [],
  customer: { id: 'gid://shopify/Customer/1', name: 'Maya Example' },
  shipping_address: { name: 'Maya Example', address1: '1 Example Street', address2: null, city: 'Springfield', province_code: 'IL', zip: '62701', country: 'United States', country_code: 'US', phone: null },
  actions: {
    cancel: { allowed: true, reason: null },
    refund: { allowed: true, reason: null },
    address: { allowed: true, reason: null },
    replacement: { allowed: true, reason: null },
  },
  ...overrides,
});

export const connection = (overrides = {}) => ({
  connected: true,
  status: 'working',
  shop_name: 'Example Store',
  shop_domain: 'example-store.myshopify.com',
  customer_data: 'full',
  actions: ['cancel', 'refund', 'address', 'replacement'].map(name => ({ name, available: true, reason: null, missing_scopes: [] })),
  ...overrides,
});

export const agent = { administrator: false, can_act_on_orders: false };
export const allowedAgent = { administrator: false, can_act_on_orders: true };
export const admin = { administrator: true, can_act_on_orders: true };

export const flush = () => new Promise(resolve => setTimeout(resolve, 0));
