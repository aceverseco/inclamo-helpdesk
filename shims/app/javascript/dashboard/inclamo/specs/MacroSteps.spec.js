import { onTestFinished } from 'vitest';
import { mount } from '@vue/test-utils';
import { h, inject, computed, defineComponent } from 'vue';
import MacroEditor from 'dashboard/routes/dashboard/settings/macros/MacroEditor.vue';
import MacroPreview from 'dashboard/routes/dashboard/conversation/Macros/MacroPreview.vue';
import MacroNode from 'dashboard/routes/dashboard/settings/macros/MacroNode.vue';
import { validateActions } from 'dashboard/helper/validations';
import { useMacroExecution } from 'dashboard/composables/useMacroExecution';
import { useBulkActions } from 'dashboard/composables/chatlist/useBulkActions';
import { useStore as useVuexStore } from 'vuex';
import { useStore, useStoreGetters, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useConversationRequiredAttributes } from 'dashboard/composables/useConversationRequiredAttributes';
import registry from 'dashboard/extensions/macroSteps';
import { checkConnection, forgetConnection, hasOrderSteps } from '../macroSteps';
import InclamoAPI from '../api';
import { connection, flush } from './helpers';

vi.mock('../api', () => ({ default: { getConnection: vi.fn(), macroPreview: vi.fn(), confirmMacro: vi.fn(), getMacro: vi.fn() } }));
vi.mock('dashboard/composables/store');
vi.mock('vuex', () => ({ useStore: vi.fn() }));
vi.mock('dashboard/composables');
vi.mock('dashboard/composables/useConversationRequiredAttributes');
vi.mock('dashboard/composables/useAdmin', () => ({ useAdmin: () => ({ isAdmin: { value: true } }) }));
vi.mock('vue-router', () => ({ useRoute: () => ({ params: {} }), useRouter: () => ({ push: vi.fn() }) }));
// The confirmation's own i18n; `broken` makes opening the confirmation fail, as a chunk that does not load.
const i18n = { broken: false };
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
  createI18n: () => {
    if (i18n.broken) throw new Error('chunk failed to load');
    return { install: () => {} };
  },
}));
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
// The conversations selected in the bulk bar.
let selected = [];
// The macros as the server holds them now, by id.
let onServer = {};

beforeEach(() => {
  forgetConnection();
  vi.clearAllMocks();
  dispatch.mockResolvedValue(undefined);
  InclamoAPI.getConnection.mockResolvedValue({ data: { connected: false } });
  onServer = { 7: refundMacro, 8: plainMacro };
  InclamoAPI.getMacro.mockImplementation(id => Promise.resolve({ data: { payload: onServer[id] } }));
  const store = { dispatch, getters: { getConversationById: () => ({ custom_attributes: {} }) } };
  useStore.mockReturnValue(store);
  useVuexStore.mockReturnValue(store);
  useStoreGetters.mockReturnValue(getters);
  selected = [];
  useMapGetter.mockImplementation(key => {
    if (key === 'getConversationById') return { value: () => ({ custom_attributes: {} }) };
    if (key === 'bulkActions/getSelectedConversationIds') return { value: selected };
    return { value: null };
  });
  useConversationRequiredAttributes.mockReturnValue({ checkMissingAttributes: () => ({ hasMissing: false, missing: [] }) });
  agentAnswer.value = true;
  agentAnswer.mounted = [];
  i18n.broken = false;
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

  it('offers the steps the next time the editor opens once the store is connected, not half a minute later', async () => {
    const now = vi.spyOn(Date, 'now').mockReturnValue(1_000_000);
    onTestFinished(() => now.mockRestore());
    expect((await editorOffers()).some(type => type.key.startsWith('inclamo_'))).toBe(false);

    InclamoAPI.getConnection.mockResolvedValue({ data: connection() });
    now.mockReturnValue(1_000_000 + 5_000);

    expect((await editorOffers()).some(type => type.key.startsWith('inclamo_'))).toBe(true);
  });

  it('drops an answer about the connection that comes back after it was forgotten', async () => {
    let late;
    InclamoAPI.getConnection.mockReturnValueOnce(new Promise(resolve => (late = resolve)));
    checkConnection();
    await flush();
    forgetConnection();
    InclamoAPI.getConnection.mockResolvedValue({ data: { connected: false } });

    const offered = editorOffers();
    late({ data: connection() });

    expect((await offered).some(type => type.key.startsWith('inclamo_'))).toBe(false);
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

  it('runs a macro without order steps without a confirmation', async () => {
    const { execute } = useMacroExecution();

    execute(plainMacro, 42);
    await flush();

    expect(dispatch).toHaveBeenCalledWith('macros/execute', { macroId: 8, conversationIds: [42] });
    expect(agentAnswer.mounted).toEqual([]);
    expect(await registry.beforeRun(plainMacro, [1, 2])).toBe(true);
  });

  it('asks for the confirmation of a macro that gained an order step after the page loaded it', async () => {
    onServer[8] = { ...plainMacro, actions: [step('inclamo_refund_full'), ...plainMacro.actions] };
    agentAnswer.value = false;
    const { execute } = useMacroExecution();

    execute(plainMacro, 42);
    await flush();

    expect(InclamoAPI.getMacro).toHaveBeenCalledWith(8);
    expect(agentAnswer.mounted).toEqual([{ macro: onServer[8], conversationId: 42 }]);
    expect(dispatch).not.toHaveBeenCalled();
  });

  it('goes by its own copy of a macro the server cannot be asked about; the server refuses order steps not confirmed', async () => {
    InclamoAPI.getMacro.mockRejectedValue(new Error('network'));

    expect(await registry.beforeRun(plainMacro, [42])).toBe(true);
    expect(await registry.beforeRun(refundMacro, [42])).toBe(true);
    expect(agentAnswer.mounted).toEqual([{ macro: refundMacro, conversationId: 42 }]);
  });

  it('runs a macro with order steps in one conversation at a time', async () => {
    expect(await registry.beforeRun(refundMacro, [41, 42])).toBe(false);
    expect(useAlert).toHaveBeenCalledWith('A macro that acts on orders runs in one conversation at a time, after a confirmation.');
    expect(agentAnswer.mounted).toEqual([]);
    expect(hasOrderSteps(refundMacro)).toBe(true);
    expect(hasOrderSteps(plainMacro)).toBe(false);
  });

  it('does not run, and says so, when the confirmation cannot be opened', async () => {
    i18n.broken = true;

    expect(await registry.beforeRun(refundMacro, [42])).toBe(false);
    expect(useAlert).toHaveBeenCalledWith('The confirmation of this macro could not be opened, so it did not run. Try again in a moment.');
  });
});

describe('The bulk bar runs macros through the same check', () => {
  it('runs a macro with order steps on one selected conversation after the confirmation', async () => {
    selected = [42];
    const { onExecuteMacro } = useBulkActions();

    await onExecuteMacro(refundMacro);

    expect(agentAnswer.mounted).toEqual([{ macro: refundMacro, conversationId: 42 }]);
    expect(dispatch).toHaveBeenCalledWith('macros/execute', { macroId: 7, conversationIds: [42] });
  });

  it('runs no macro with order steps on several selected conversations', async () => {
    selected = [41, 42];
    const { onExecuteMacro } = useBulkActions();

    await onExecuteMacro(refundMacro);

    expect(dispatch).not.toHaveBeenCalledWith('macros/execute', expect.anything());
    expect(useAlert).toHaveBeenCalledWith('A macro that acts on orders runs in one conversation at a time, after a confirmation.');
  });

  it('runs a macro without order steps on several conversations as before', async () => {
    selected = [41, 42];
    const { onExecuteMacro } = useBulkActions();

    await onExecuteMacro(plainMacro);

    expect(dispatch).toHaveBeenCalledWith('macros/execute', { macroId: 8, conversationIds: [41, 42] });
  });

  it('tells the agent when the check before the run fails, and runs nothing', async () => {
    selected = [42];
    const check = vi.spyOn(registry, 'beforeRun').mockRejectedValue(new Error('chunk failed to load'));
    onTestFinished(() => check.mockRestore());
    const { onExecuteMacro } = useBulkActions();

    await expect(onExecuteMacro(refundMacro)).resolves.toBeUndefined();

    expect(dispatch).not.toHaveBeenCalledWith('macros/execute', expect.anything());
    expect(useAlert).toHaveBeenCalledWith('MACROS.ERROR');
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
  const tied = steps => ({ order: { id: 'gid://shopify/Order/1', number: '#1042' }, steps, digest: 'shown-digest' });

  it('names the order and what each order step will do, with the amount, and answers yes on Run', async () => {
    const { wrapper, answers } = await open(tied([{ position: 0, step: 'inclamo_refund_full', amount: '54.0', currency: 'EUR' }]));

    expect(InclamoAPI.macroPreview).toHaveBeenCalledWith(7, 42);
    expect(wrapper.find('[data-testid="dialog-title"]').text()).toContain('Refund and close');
    expect(wrapper.find('[data-testid="inclamo-macro-order"]').text()).toContain('#1042');
    const refund = wrapper.find('[data-testid="inclamo-macro-step-inclamo_refund_full"]').text();
    expect(refund).toContain('Refund the order in full');
    expect(refund).toMatch(/Refunds €54\.00|Refunds 54\.00/);
    InclamoAPI.confirmMacro.mockResolvedValue({ status: 204 });
    await wrapper.find('[data-testid="dialog-confirm"]').trigger('click');
    await flush();

    expect(InclamoAPI.confirmMacro).toHaveBeenCalledWith(7, 42, 'shown-digest');
    expect(answers).toEqual([true]);
  });

  it('does not run a macro that was changed since the agent looked at it', async () => {
    const { wrapper, answers } = await open(tied([{ position: 0, step: 'inclamo_refund_full', amount: '54.0', currency: 'EUR' }]));
    InclamoAPI.confirmMacro.mockRejectedValue({ response: { status: 409 } });

    await wrapper.find('[data-testid="dialog-confirm"]').trigger('click');
    await flush();

    expect(answers).toEqual([]);
    expect(wrapper.find('[data-testid="inclamo-macro-not-run"]').text()).toContain('was changed while you looked at it');
    expect(wrapper.find('[data-testid="dialog-confirm"]').exists()).toBe(false);
    await wrapper.find('[data-testid="dialog-cancel"]').trigger('click');
    expect(answers).toEqual([false]);
  });

  it('does not run when the confirmation does not reach the server, and lets the agent try again', async () => {
    const { wrapper, answers } = await open(tied([{ position: 0, step: 'inclamo_refund_full', amount: '54.0', currency: 'EUR' }]));
    InclamoAPI.confirmMacro.mockRejectedValueOnce(new Error('network')).mockResolvedValueOnce({ status: 204 });

    await wrapper.find('[data-testid="dialog-confirm"]').trigger('click');
    await flush();
    expect(answers).toEqual([]);
    expect(wrapper.find('[data-testid="inclamo-macro-not-run"]').text()).toContain('did not reach the server');

    await wrapper.find('[data-testid="dialog-confirm"]').trigger('click');
    await flush();
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
    expect(cancel).toContain('Will not be done: An administrator has not allowed you to perform this action.');
    expect(cancel).toContain('The macro stops at this step');
  });

  it('says that the steps after a step that stops the macro do not run', async () => {
    const { wrapper } = await open(tied([
      { position: 0, step: 'inclamo_refund_full', refusal: 'nothing_to_refund', message: null },
      { position: 1, step: 'inclamo_replacement', after_stop: true },
    ]));

    expect(wrapper.find('[data-testid="inclamo-macro-step-inclamo_replacement"]').text()).toContain('Will not run: the macro stops at an earlier step.');
  });

  it('tells a cancellation of an order refunded before, and one whose refund could not be checked, from an unpaid one', async () => {
    const before = await open(tied([{ position: 0, step: 'inclamo_cancel_order', refund: 'none_left' }]));
    const cancel = before.wrapper.find('[data-testid="inclamo-macro-step-inclamo_cancel_order"]').text();
    expect(cancel).toContain('Everything paid was refunded before');
    expect(cancel).not.toContain('Nothing was paid');

    const unknown = await open(tied([{ position: 0, step: 'inclamo_cancel_order', refund: 'unknown' }]));
    expect(unknown.wrapper.find('[data-testid="inclamo-macro-step-inclamo_cancel_order"]').text()).toContain('how much could not be checked just now');
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
