import { mount } from '@vue/test-utils';
import { h, inject, computed, defineComponent } from 'vue';
import MacroEditor from 'dashboard/routes/dashboard/settings/macros/MacroEditor.vue';
import MacroPreview from 'dashboard/routes/dashboard/conversation/Macros/MacroPreview.vue';
import MacroNode from 'dashboard/routes/dashboard/settings/macros/MacroNode.vue';
import { validateActions } from 'dashboard/helper/validations';
import { useMacroExecution } from 'dashboard/composables/useMacroExecution';
import { useStore, useStoreGetters, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useConversationRequiredAttributes } from 'dashboard/composables/useConversationRequiredAttributes';
import registry from 'dashboard/extensions/macroSteps';
import { forgetConnection, hasOrderSteps } from '../macroSteps';
import InclamoAPI from '../api';
import { connection, flush } from './helpers';

vi.mock('../api', () => ({ default: { getConnection: vi.fn(), macroPreview: vi.fn() } }));
vi.mock('dashboard/composables/store');
vi.mock('dashboard/composables');
vi.mock('dashboard/composables/useConversationRequiredAttributes');
vi.mock('dashboard/composables/useAdmin', () => ({ useAdmin: () => ({ isAdmin: { value: true } }) }));
vi.mock('vue-router', () => ({ useRoute: () => ({ params: {} }), useRouter: () => ({ push: vi.fn() }) }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }), createI18n: () => ({ install: () => {} }) }));
vi.mock('dashboard/store', () => ({ default: { install: app => Object.assign(app.config.globalProperties, { $store: { getters: {} } }) } }));

// The confirmation, reduced to its answer: what the agent does is set per test.
const agentAnswer = { value: true, mounted: [] };
vi.mock('../components/MacroConfirmation.vue', () => ({
  default: {
    props: ['macro', 'conversationId', 'onAnswer'],
    setup(props) {
      agentAnswer.mounted.push({ macro: props.macro, conversationId: props.conversationId });
      Promise.resolve().then(() => props.onAnswer(agentAnswer.value));
      return () => null;
    },
  },
}));

const step = (name, params = []) => ({ action_name: name, action_params: params });
const refundMacro = { id: 7, name: 'Refund and close', actions: [step('inclamo_refund_full'), step('send_message', ['Sorry']), step('resolve_conversation')] };
const plainMacro = { id: 8, name: 'Close', actions: [step('add_label', ['spam']), step('resolve_conversation')] };

const getters = {
  'labels/getLabels': { value: [] },
  'teams/getTeams': { value: [] },
  'agents/getVerifiedAgents': { value: [] },
  'macros/getUIFlags': { value: { isFetchingItem: false } },
};
const dispatch = vi.fn();

beforeEach(() => {
  forgetConnection();
  vi.clearAllMocks();
  dispatch.mockResolvedValue(undefined);
  InclamoAPI.getConnection.mockResolvedValue({ data: { connected: false } });
  useStore.mockReturnValue({ dispatch, getters: {} });
  useStoreGetters.mockReturnValue(getters);
  useMapGetter.mockImplementation(key => (key === 'getConversationById' ? { value: () => ({ custom_attributes: {} }) } : { value: null }));
  useConversationRequiredAttributes.mockReturnValue({ checkMissingAttributes: () => ({ hasMissing: false, missing: [] }) });
  agentAnswer.value = true;
  agentAnswer.mounted = [];
});

// What the editor offers, as its form receives it.
const FormProbe = defineComponent({
  name: 'MacroForm',
  setup() {
    const types = inject('macroActionTypes');
    return () => h('ul', types.value.map(type => h('li', { 'data-key': type.key, 'data-description': type.description || '' }, type.label)));
  },
});
const editorOffers = async () => {
  const wrapper = mount(MacroEditor, { global: { stubs: { MacroForm: FormProbe, 'woot-loading-state': true } } });
  await flush();
  await flush();
  const offered = wrapper.findAll('li').map(item => ({ key: item.attributes('data-key'), label: item.text(), description: item.attributes('data-description') }));
  wrapper.unmount();
  return offered;
};

describe('The macro editor offers order steps', () => {
  it('offers the four steps after Chatwoot steps, each with the behaviour in its description, with a working connection', async () => {
    InclamoAPI.getConnection.mockResolvedValue({ data: connection() });

    const offered = await editorOffers();
    const ours = offered.filter(type => type.key.startsWith('inclamo_'));

    expect(offered.findIndex(type => type.key === 'inclamo_refund_full')).toBeGreaterThan(offered.findIndex(type => type.key === 'send_webhook_event'));
    expect(ours.map(type => type.label)).toEqual(['Refund the order in full', 'Refund the shipping cost', 'Cancel the order', 'Send a free replacement']);
    expect(ours[0].description).toMatch(/everything still refundable.*not put back in stock.*Shopify notifies the customer/);
    expect(ours[1].description).toMatch(/only the shipping cost.*items are not refunded/);
    expect(ours[2].description).toMatch(/refunds it in full and puts the items back in stock.*Shopify notifies the customer/);
    expect(ours[3].description).toMatch(/same items.*same address, at no charge/);
  });

  it('offers none without a store connection', async () => {
    InclamoAPI.getConnection.mockResolvedValue({ data: { connected: false } });

    expect((await editorOffers()).some(type => type.key.startsWith('inclamo_'))).toBe(false);
  });

  it('offers none while the connection is broken, or when it cannot be read', async () => {
    InclamoAPI.getConnection.mockResolvedValue({ data: connection({ status: 'broken' }) });
    expect((await editorOffers()).some(type => type.key.startsWith('inclamo_'))).toBe(false);

    forgetConnection();
    InclamoAPI.getConnection.mockRejectedValue(new Error('network'));
    expect((await editorOffers()).some(type => type.key.startsWith('inclamo_'))).toBe(false);
  });

  it('lets an order step be saved without parameters', () => {
    expect(validateActions([step('inclamo_refund_full'), step('send_message', ['Sorry']), step('resolve_conversation')])).toEqual({});
    expect(validateActions([step('send_message')])).toEqual({ action_0: 'ACTION_PARAMETERS_REQUIRED' });
  });

  it('shows the description under the step and keeps a step it does not list from breaking the node', () => {
    const types = computed(() => [{ key: 'inclamo_refund_full', label: 'Refund the order in full', description: 'Refunds everything still refundable.', inputType: null }]);
    const node = model => mount(MacroNode, { props: { modelValue: model }, global: { provide: { macroActionTypes: types }, stubs: { NextButton: true }, directives: { tooltip: {} }, mocks: { $t: key => key } } });

    expect(node(step('inclamo_refund_full')).find('[data-testid="macro-step-description"]').text()).toBe('Refunds everything still refundable.');
    expect(node(step('inclamo_cancel_order')).find('[data-testid="macro-step-description"]').exists()).toBe(false);
  });

  it('lists the steps of a macro in its order in the preview, an order step by its name', () => {
    const wrapper = mount(MacroPreview, { props: { macro: refundMacro }, global: { mocks: { $t: key => key } } });

    expect(wrapper.findAll('p.text-xs').map(item => item.text())).toEqual(['Refund the order in full', 'MACROS.ACTIONS.SEND_MESSAGE', 'MACROS.ACTIONS.RESOLVE_CONVERSATION']);
  });
});

describe('Order steps act on the tied order after a confirmation', () => {
  it('runs a macro with order steps only after the agent confirms, in that conversation', async () => {
    const { execute } = useMacroExecution();

    execute(refundMacro, 42);
    await flush();

    expect(agentAnswer.mounted).toEqual([{ macro: refundMacro, conversationId: 42 }]);
    expect(dispatch).toHaveBeenCalledWith('macros/execute', { macroId: 7, conversationIds: [42] });
  });

  it('runs no step when the agent declines', async () => {
    agentAnswer.value = false;
    const { execute, executingMacroId } = useMacroExecution();

    execute(refundMacro, 42);
    await flush();

    expect(dispatch).not.toHaveBeenCalled();
    expect(useAlert).not.toHaveBeenCalled();
    expect(executingMacroId.value).toBeNull();
  });

  it('runs a macro without order steps at once, without a confirmation', () => {
    const { execute } = useMacroExecution();

    execute(plainMacro, 42);

    expect(dispatch).toHaveBeenCalledWith('macros/execute', { macroId: 8, conversationIds: [42] });
    expect(agentAnswer.mounted).toEqual([]);
    expect(registry.beforeRun(plainMacro, [1, 2])).toBe(true);
  });

  it('runs a macro with order steps in one conversation at a time', () => {
    expect(registry.beforeRun(refundMacro, [41, 42])).toBe(false);
    expect(useAlert).toHaveBeenCalledWith('A macro that acts on orders runs in one conversation at a time, after a confirmation.');
    expect(agentAnswer.mounted).toEqual([]);
    expect(hasOrderSteps(refundMacro)).toBe(true);
    expect(hasOrderSteps(plainMacro)).toBe(false);
  });
});

// Chatwoot's dialog with both of its buttons.
const DialogStub = {
  name: 'Dialog',
  props: ['title', 'confirmButtonLabel', 'cancelButtonLabel', 'showConfirmButton'],
  emits: ['confirm', 'close'],
  data: () => ({ shown: false }),
  methods: {
    open() {
      this.shown = true;
    },
    close() {
      this.shown = false;
      this.$emit('close');
    },
  },
  render() {
    if (!this.shown) return null;
    return h('div', { 'data-testid': 'dialog' }, [
      h('h2', { 'data-testid': 'dialog-title' }, this.title),
      this.$slots.default?.(),
      h('button', { 'data-testid': 'dialog-cancel', onClick: () => this.close() }, this.cancelButtonLabel),
      this.showConfirmButton === false ? null : h('button', { 'data-testid': 'dialog-confirm', onClick: () => this.$emit('confirm') }, this.confirmButtonLabel),
    ]);
  },
};

describe('The confirmation', () => {
  // The real component, not the reduced one above.
  let Confirmation;
  beforeAll(async () => {
    Confirmation = (await vi.importActual('../components/MacroConfirmation.vue')).default;
  });
  const open = async data => {
    if (data instanceof Error) InclamoAPI.macroPreview.mockRejectedValue(data);
    else InclamoAPI.macroPreview.mockResolvedValue({ data });
    const answers = [];
    const wrapper = mount(Confirmation, { props: { macro: refundMacro, conversationId: 42, onAnswer: answer => answers.push(answer) }, global: { stubs: { Dialog: DialogStub } } });
    await flush();
    return { wrapper, answers };
  };
  const tied = steps => ({ order: { id: 'gid://shopify/Order/1', number: '#1042' }, steps });

  it('names the order and what each order step will do, with the amount, and answers yes on Run', async () => {
    const { wrapper, answers } = await open(tied([{ position: 0, step: 'inclamo_refund_full', amount: '54.0', currency: 'EUR' }]));

    expect(InclamoAPI.macroPreview).toHaveBeenCalledWith(7, 42);
    expect(wrapper.find('[data-testid="dialog-title"]').text()).toContain('Refund and close');
    expect(wrapper.find('[data-testid="inclamo-macro-order"]').text()).toContain('#1042');
    const refund = wrapper.find('[data-testid="inclamo-macro-step-inclamo_refund_full"]').text();
    expect(refund).toContain('Refund the order in full');
    expect(refund).toMatch(/Refunds €54\.00|Refunds 54\.00/);
    await wrapper.find('[data-testid="dialog-confirm"]').trigger('click');

    expect(answers).toEqual([true]);
  });

  it('answers no when the agent declines', async () => {
    const { wrapper, answers } = await open(tied([{ position: 0, step: 'inclamo_refund_full', amount: '54.0', currency: 'EUR' }]));

    await wrapper.find('[data-testid="dialog-cancel"]').trigger('click');

    expect(answers).toEqual([false]);
  });

  it('says that no order is tied and offers only to close', async () => {
    const { wrapper, answers } = await open({ order: null, steps: [{ position: 0, step: 'inclamo_refund_full' }] });

    expect(wrapper.find('[data-testid="inclamo-macro-no-order"]').text()).toContain('No order is tied to this conversation');
    expect(wrapper.find('[data-testid="dialog-confirm"]').exists()).toBe(false);
    await wrapper.find('[data-testid="dialog-cancel"]').trigger('click');
    expect(answers).toEqual([false]);
  });

  it('says beforehand which step will not be done and why, and that the macro stops there', async () => {
    const { wrapper } = await open(tied([
      { position: 0, step: 'inclamo_refund_shipping', amount: '5.0', currency: 'EUR' },
      { position: 2, step: 'inclamo_cancel_order', refusal: 'not_allowed', message: null },
    ]));

    expect(wrapper.find('[data-testid="inclamo-macro-step-inclamo_refund_shipping"]').text()).toContain('Refunds the shipping cost');
    const cancel = wrapper.find('[data-testid="inclamo-macro-step-inclamo_cancel_order"]').text();
    expect(cancel).toContain('Will not be done: An administrator has not allowed you to act on orders.');
    expect(cancel).toContain('The macro stops at this step');
  });

  it('describes a cancellation of an unpaid order and a replacement', async () => {
    const { wrapper } = await open(tied([{ position: 0, step: 'inclamo_cancel_order' }, { position: 1, step: 'inclamo_replacement', units: 3 }]));

    expect(wrapper.find('[data-testid="inclamo-macro-step-inclamo_cancel_order"]').text()).toContain('Nothing was paid, so nothing is refunded');
    expect(wrapper.find('[data-testid="inclamo-macro-step-inclamo_replacement"]').text()).toContain('the same 3 items to the same address, at no charge');
  });

  it('offers only to close when the preview could not be read', async () => {
    const { wrapper } = await open(new Error('network'));

    expect(wrapper.find('[data-testid="inclamo-macro-failed"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="dialog-confirm"]').exists()).toBe(false);
  });
});
