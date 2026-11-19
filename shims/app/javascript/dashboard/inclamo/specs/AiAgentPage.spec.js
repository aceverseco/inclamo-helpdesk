import { mount } from '@vue/test-utils';
import AiAgentPage from '../components/AiAgentPage.vue';
import InclamoAPI from '../api';
import { stubs, flush } from './helpers';

vi.mock('../api', () => ({
  default: {
    getAiConnection: vi.fn(),
    connectAi: vi.fn(),
    changeAiInboxes: vi.fn(),
    disconnectAi: vi.fn(),
  },
}));

const inboxes = [
  { id: 3, name: 'Website', channel_type: 'Channel::WebWidget', connected: false, other_bot: null, selectable: true },
  { id: 4, name: 'Support email', channel_type: 'Channel::Email', connected: false, other_bot: 'Agent Bot', selectable: false },
  { id: 5, name: 'Store chat', channel_type: 'Channel::Api', connected: false, other_bot: 'Dialogflow', selectable: false },
];

const notConnected = (overrides = {}) => ({
  connected: false,
  state: 'never_connected',
  encryption_configured: true,
  get_agent_url: 'https://ai.example.com/get',
  inboxes,
  connection: null,
  last_disconnection: null,
  ...overrides,
});

const connected = (connection = {}) => ({
  ...notConnected(),
  connected: true,
  state: connection.state || 'connected',
  inboxes: [{ ...inboxes[0], connected: true }, inboxes[1]],
  connection: {
    state: 'connected',
    inbox_ids: [3],
    phone_inbox_id: 9,
    connected_at: '2026-11-07T10:00:00Z',
    last_delivered_at: '2026-11-07T10:05:00Z',
    last_failed_at: null,
    last_error: null,
    last_reply_at: '2026-11-07T10:05:02Z',
    ...connection,
  },
});

const mountPage = async data => {
  InclamoAPI.getAiConnection.mockResolvedValue({ data });
  const wrapper = mount(AiAgentPage, { global: { stubs } });
  await flush();
  return wrapper;
};
const find = (wrapper, id) => wrapper.find(`[data-testid="${id}"]`);

beforeEach(() => vi.clearAllMocks());

describe('AiAgentPage without a connection', () => {
  it('describes the agent, links to where it is obtained and lists the inboxes', async () => {
    const wrapper = await mountPage(notConnected());

    expect(find(wrapper, 'inclamo-ai-page').attributes('data-state')).toBe('never_connected');
    expect(find(wrapper, 'inclamo-ai-about').text()).toContain('hands a conversation to your team');
    expect(find(wrapper, 'inclamo-ai-get').attributes('href')).toBe('https://ai.example.com/get');
    expect(find(wrapper, 'inclamo-ai-code').exists()).toBe(true);
    expect(find(wrapper, 'inclamo-ai-inbox-3').attributes('data-selectable')).toBe('true');
    expect(find(wrapper, 'inclamo-ai-disconnect').exists()).toBe(false);
  });

  it('shows an inbox with another bot or Dialogflow and does not let it be picked', async () => {
    const wrapper = await mountPage(notConnected());

    const email = find(wrapper, 'inclamo-ai-inbox-4');
    expect(email.attributes('data-selectable')).toBe('false');
    expect(email.text()).toContain('Has another bot');
    expect(email.find('input').attributes('disabled')).toBeDefined();
    expect(find(wrapper, 'inclamo-ai-inbox-5').text()).toContain('Dialogflow');
  });

  it('connects only with a code and an inbox, sends them, and forgets the code', async () => {
    const wrapper = await mountPage(notConnected());
    const button = find(wrapper, 'inclamo-ai-connect');
    expect(button.attributes('disabled')).toBeDefined();

    await find(wrapper, 'inclamo-ai-code').setValue('  aic1.abc  ');
    expect(button.attributes('disabled')).toBeDefined();
    await find(wrapper, 'inclamo-ai-inbox-3').find('input').trigger('change');
    expect(button.attributes('disabled')).toBeUndefined();

    InclamoAPI.connectAi.mockResolvedValue({ data: connected() });
    await button.trigger('click');
    await flush();

    expect(InclamoAPI.connectAi).toHaveBeenCalledWith({ connection_code: 'aic1.abc', inbox_ids: [3] });
    expect(find(wrapper, 'inclamo-ai-page').attributes('data-state')).toBe('connected');
    expect(wrapper.html()).not.toContain('aic1.abc');
  });

  it('says a code is not valid', async () => {
    const wrapper = await mountPage(notConnected());
    InclamoAPI.connectAi.mockRejectedValue({ response: { status: 422, data: { error: 'invalid_code', message: 'x' } } });
    await find(wrapper, 'inclamo-ai-code').setValue('hello');
    await find(wrapper, 'inclamo-ai-inbox-3').find('input').trigger('change');
    await find(wrapper, 'inclamo-ai-connect').trigger('click');
    await flush();

    expect(find(wrapper, 'inclamo-ai-error').text()).toContain('not a valid connection code');
    expect(find(wrapper, 'inclamo-ai-page').attributes('data-state')).toBe('never_connected');
  });

  it("shows the AI service's own words when it refuses, and that it did not answer", async () => {
    const wrapper = await mountPage(notConnected());
    await find(wrapper, 'inclamo-ai-code').setValue('aic1.abc');
    await find(wrapper, 'inclamo-ai-inbox-3').find('input').trigger('change');

    InclamoAPI.connectAi.mockRejectedValueOnce({ response: { status: 422, data: { error: 'refused', message: 'This connection code has expired.' } } });
    await find(wrapper, 'inclamo-ai-connect').trigger('click');
    await flush();
    expect(find(wrapper, 'inclamo-ai-error').text()).toBe('This connection code has expired.');

    InclamoAPI.connectAi.mockRejectedValueOnce({ response: { status: 502, data: { error: 'not_answered' } } });
    await find(wrapper, 'inclamo-ai-connect').trigger('click');
    await flush();
    expect(find(wrapper, 'inclamo-ai-error').text()).toContain('did not answer');
  });

  it('cannot connect on an installation without encryption keys', async () => {
    const wrapper = await mountPage(notConnected({ encryption_configured: false }));
    await find(wrapper, 'inclamo-ai-code').setValue('aic1.abc');
    await find(wrapper, 'inclamo-ai-inbox-3').find('input').trigger('change');

    expect(find(wrapper, 'inclamo-ai-encryption').exists()).toBe(true);
    expect(find(wrapper, 'inclamo-ai-connect').attributes('disabled')).toBeDefined();
  });

  it('says when it was disconnected and when the AI service could not be told', async () => {
    const wrapper = await mountPage(notConnected({ state: 'disconnected', last_disconnection: { disconnected_at: '2026-11-07T11:00:00Z', ai_service_told: false } }));

    expect(find(wrapper, 'inclamo-ai-page').attributes('data-state')).toBe('disconnected');
    expect(find(wrapper, 'inclamo-ai-disconnected').text()).toContain('could not be told');
    expect(find(wrapper, 'inclamo-ai-code').exists()).toBe(true);
  });
});

describe('AiAgentPage with a connection', () => {
  it('shows the inboxes, the state and the last reply', async () => {
    const wrapper = await mountPage(connected());

    expect(find(wrapper, 'inclamo-ai-state').attributes('data-state')).toBe('connected');
    expect(find(wrapper, 'inclamo-ai-state').text()).toBe('Connected');
    expect(find(wrapper, 'inclamo-ai-inboxes').text()).toBe('Website');
    expect(find(wrapper, 'inclamo-ai-last-reply').text()).not.toBe('No reply yet');
    expect(find(wrapper, 'inclamo-ai-last-error').text()).toBe('None');
    expect(find(wrapper, 'inclamo-ai-code').exists()).toBe(false);
  });

  it('shows a failing connection with the kind and time of the last failure', async () => {
    const wrapper = await mountPage(connected({ state: 'failing', last_failed_at: '2026-11-07T10:06:00Z', last_error: 'http_503' }));

    expect(find(wrapper, 'inclamo-ai-state').attributes('data-state')).toBe('failing');
    expect(find(wrapper, 'inclamo-ai-failing').exists()).toBe(true);
    const lastError = find(wrapper, 'inclamo-ai-last-error');
    expect(lastError.attributes('data-kind')).toBe('http_503');
    expect(lastError.text()).toContain('error 503');
    expect(lastError.text()).toMatch(/\d/);
  });

  it('names a failure of another kind in words', async () => {
    const wrapper = await mountPage(connected({ state: 'failing', last_failed_at: '2026-11-07T10:06:00Z', last_error: 'connection_failed' }));

    expect(find(wrapper, 'inclamo-ai-last-error').text()).toContain('could not be reached');
  });

  it('disconnects only after the confirmation, which says pending conversations go to the team', async () => {
    const wrapper = await mountPage(connected());
    await find(wrapper, 'inclamo-ai-disconnect').trigger('click');
    await flush();

    expect(InclamoAPI.disconnectAi).not.toHaveBeenCalled();
    expect(find(wrapper, 'inclamo-ai-confirm').text()).toContain('goes to your team');

    InclamoAPI.disconnectAi.mockResolvedValue({ data: { ...notConnected({ state: 'disconnected', last_disconnection: { disconnected_at: '2026-11-07T11:00:00Z', ai_service_told: true } }), ai_service_told: true } });
    await find(wrapper, 'dialog-confirm').trigger('click');
    await flush();

    expect(InclamoAPI.disconnectAi).toHaveBeenCalledTimes(1);
    expect(find(wrapper, 'inclamo-ai-page').attributes('data-state')).toBe('disconnected');
    expect(find(wrapper, 'inclamo-ai-notice').exists()).toBe(false);
  });

  it('says so when the AI service could not be told about the disconnection', async () => {
    const wrapper = await mountPage(connected());
    await find(wrapper, 'inclamo-ai-disconnect').trigger('click');
    InclamoAPI.disconnectAi.mockResolvedValue({ data: { ...notConnected({ state: 'disconnected', last_disconnection: { disconnected_at: '2026-11-07T11:00:00Z', ai_service_told: false } }), ai_service_told: false } });
    await find(wrapper, 'dialog-confirm').trigger('click');
    await flush();

    expect(find(wrapper, 'inclamo-ai-notice').text()).toContain('could not be told');
  });

  it('names the person who connected with a code', async () => {
    const wrapper = await mountPage(connected({ connected_via: 'page', connected_by: 'Alex Admin' }));

    const by = find(wrapper, 'inclamo-ai-connected-by');
    expect(by.attributes('data-via')).toBe('page');
    expect(by.text()).toBe('Alex Admin');
  });

  it('says the store app made a connection it made, instead of naming a person', async () => {
    const wrapper = await mountPage(connected({ connected_via: 'app', connected_by: null }));

    const by = find(wrapper, 'inclamo-ai-connected-by');
    expect(by.attributes('data-via')).toBe('app');
    expect(by.text()).toBe('The store app');
    expect(find(wrapper, 'inclamo-ai-inboxes').text()).toBe('Website');
    expect(find(wrapper, 'inclamo-ai-disconnect').exists()).toBe(true);
  });

  it('says a connection without an inbox takes calls only', async () => {
    const data = connected({ connected_via: 'app', connected_by: null, inbox_ids: [] });
    data.inboxes = inboxes;
    const wrapper = await mountPage(data);

    expect(find(wrapper, 'inclamo-ai-calls-only').text()).toContain('Finished calls are filed in the Phone inbox');
    expect(find(wrapper, 'inclamo-ai-state').attributes('data-state')).toBe('connected');
  });

  it('shows no line for who connected when nobody is known', async () => {
    const wrapper = await mountPage(connected({ connected_by: null }));

    expect(find(wrapper, 'inclamo-ai-connected-by').exists()).toBe(false);
    expect(find(wrapper, 'inclamo-ai-calls-only').exists()).toBe(false);
  });

  it('says when the page cannot be loaded', async () => {
    InclamoAPI.getAiConnection.mockRejectedValue({ response: { status: 403 } });
    const wrapper = mount(AiAgentPage, { global: { stubs } });
    await flush();

    expect(find(wrapper, 'inclamo-ai-failed').exists()).toBe(true);
  });
});

// Capability agent-inbox-selection: the inboxes of a live connection are changed on the page.
describe('AiAgentPage changing the inboxes of a connection', () => {
  const live = (overrides = {}, connection = {}) => {
    const data = connected(connection);
    data.inboxes = [
      { ...inboxes[0], connected: true, pending_for_agent: 2 },
      { id: 6, name: 'Returns email', channel_type: 'Channel::Email', connected: false, other_bot: null, selectable: true, pending_for_agent: 0 },
      { ...inboxes[1], pending_for_agent: 0 },
    ];
    return { ...data, ...overrides };
  };
  const tick = (wrapper, id) => find(wrapper, `inclamo-ai-inbox-${id}`).find('input').trigger('change');
  const saveButton = wrapper => find(wrapper, 'inclamo-ai-save');
  const afterSave = ids => {
    const data = live();
    data.inboxes = data.inboxes.map(inbox => ({ ...inbox, connected: ids.includes(inbox.id) }));
    data.connection = { ...data.connection, inbox_ids: ids };
    return data;
  };

  it('ticks the inboxes the agent answers in, and keeps Save off until the ticks differ', async () => {
    const wrapper = await mountPage(live());

    expect(find(wrapper, 'inclamo-ai-inbox-3').find('input').element.checked).toBe(true);
    expect(find(wrapper, 'inclamo-ai-inbox-6').find('input').element.checked).toBe(false);
    expect(saveButton(wrapper).attributes('disabled')).toBeDefined();

    await tick(wrapper, 6);
    expect(saveButton(wrapper).attributes('disabled')).toBeUndefined();
    await tick(wrapper, 6);
    expect(saveButton(wrapper).attributes('disabled')).toBeDefined();
  });

  it('shows an inbox with another bot and does not let it be ticked', async () => {
    const wrapper = await mountPage(live());

    const email = find(wrapper, 'inclamo-ai-inbox-4');
    expect(email.attributes('data-selectable')).toBe('false');
    expect(email.text()).toContain('Has another bot');
    expect(email.find('input').attributes('disabled')).toBeDefined();
    await email.find('input').trigger('change');
    expect(saveButton(wrapper).attributes('disabled')).toBeDefined();
  });

  it('saves an added inbox at once, with the whole list, and shows the new inboxes', async () => {
    const wrapper = await mountPage(live());
    InclamoAPI.changeAiInboxes.mockResolvedValue({ data: afterSave([3, 6]) });

    await tick(wrapper, 6);
    await saveButton(wrapper).trigger('click');
    await flush();

    expect(InclamoAPI.changeAiInboxes).toHaveBeenCalledWith({ inbox_ids: [3, 6] });
    expect(find(wrapper, 'inclamo-ai-change-confirm').exists()).toBe(false);
    expect(find(wrapper, 'inclamo-ai-connected-6').text()).toBe('Returns email');
    expect(find(wrapper, 'inclamo-ai-connected-3').exists()).toBe(true);
    expect(find(wrapper, 'inclamo-ai-saved').exists()).toBe(true);
    expect(saveButton(wrapper).attributes('disabled')).toBeDefined();
    expect(find(wrapper, 'inclamo-ai-page').attributes('data-state')).toBe('connected');
  });

  it('asks first, naming how many conversations go to the team, when an inbox the agent holds conversations in is unticked', async () => {
    const wrapper = await mountPage(live());
    await tick(wrapper, 3);
    await tick(wrapper, 6);

    await saveButton(wrapper).trigger('click');
    await flush();

    expect(InclamoAPI.changeAiInboxes).not.toHaveBeenCalled();
    const handover = find(wrapper, 'inclamo-ai-change-handover');
    expect(handover.attributes('data-count')).toBe('2');
    expect(handover.text()).toContain('go to your team as Open: 2');
    expect(find(wrapper, 'inclamo-ai-change-calls-only').exists()).toBe(false);

    InclamoAPI.changeAiInboxes.mockResolvedValue({ data: afterSave([6]) });
    await find(wrapper, 'dialog-confirm').trigger('click');
    await flush();

    expect(InclamoAPI.changeAiInboxes).toHaveBeenCalledWith({ inbox_ids: [6] });
    expect(find(wrapper, 'inclamo-ai-inboxes').text()).toBe('Returns email');
  });

  it('asks first when no inbox is left: the agent takes calls only', async () => {
    const data = live();
    data.inboxes[0].pending_for_agent = 0;
    const wrapper = await mountPage(data);
    await tick(wrapper, 3);

    await saveButton(wrapper).trigger('click');
    await flush();

    expect(InclamoAPI.changeAiInboxes).not.toHaveBeenCalled();
    expect(find(wrapper, 'inclamo-ai-change-calls-only').text()).toContain('take calls only');
    expect(find(wrapper, 'inclamo-ai-change-handover').exists()).toBe(false);

    InclamoAPI.changeAiInboxes.mockResolvedValue({ data: afterSave([]) });
    await find(wrapper, 'dialog-confirm').trigger('click');
    await flush();

    expect(InclamoAPI.changeAiInboxes).toHaveBeenCalledWith({ inbox_ids: [] });
    expect(find(wrapper, 'inclamo-ai-calls-only').exists()).toBe(true);
    expect(find(wrapper, 'inclamo-ai-page').attributes('data-state')).toBe('connected');
  });

  it('words every refusal and leaves the inboxes as they were', async () => {
    const wrapper = await mountPage(live());
    await tick(wrapper, 6);
    const answers = [
      [{ status: 422, data: { error: 'refused', message: 'One inbox on this plan.' } }, 'One inbox on this plan.'],
      [{ status: 422, data: { error: 'change_unsupported', message: 'x' } }, 'This AI service cannot change inboxes. Disconnect and connect again to choose other inboxes.'],
      [{ status: 502, data: { error: 'not_answered' } }, 'did not answer'],
      [{ status: 422, data: { error: 'invalid_inbox' } }, 'cannot be given to the agent'],
      [{ status: 422, data: { error: 'inbox_has_bot' } }, 'has another bot now'],
      [{ status: 409, data: { error: 'busy' } }, 'being changed right now'],
      [{ status: 404, data: { error: 'not_connected' } }, 'not connected'],
      [{ status: 403, data: { error: 'forbidden' } }, 'Only an administrator'],
    ];

    for (const [response, words] of answers) {
      InclamoAPI.changeAiInboxes.mockRejectedValueOnce({ response });
      // eslint-disable-next-line no-await-in-loop
      await saveButton(wrapper).trigger('click');
      // eslint-disable-next-line no-await-in-loop
      await flush();
      expect(find(wrapper, 'inclamo-ai-error').text()).toContain(words);
      expect(find(wrapper, 'inclamo-ai-inboxes').text()).toBe('Website');
    }
  });

  it('shows the connection as it stands when the change was not completed', async () => {
    const wrapper = await mountPage(live());
    await tick(wrapper, 6);
    InclamoAPI.changeAiInboxes.mockRejectedValueOnce({ response: { status: 500, data: { error: 'not_applied' } } });
    InclamoAPI.getAiConnection.mockResolvedValue({ data: live({}, { inbox_change_error: 'not_applied' }) });

    await saveButton(wrapper).trigger('click');
    await flush();
    await flush();

    expect(find(wrapper, 'inclamo-ai-error').text()).toContain('was not completed');
    expect(find(wrapper, 'inclamo-ai-change-error').attributes('data-error')).toBe('not_applied');
    expect(find(wrapper, 'inclamo-ai-inboxes').text()).toBe('Website');
    expect(find(wrapper, 'inclamo-ai-inbox-6').find('input').element.checked).toBe(true);
  });

  it('says why the last change was not completed, for each reason', async () => {
    const reasons = {
      not_applied: 'save again',
      not_applied_service_not_told: 'could not be told',
      storefront_not_added: 'storefront chat was made again',
    };
    for (const [reason, words] of Object.entries(reasons)) {
      // eslint-disable-next-line no-await-in-loop
      const wrapper = await mountPage(live({}, { inbox_change_error: reason }));
      const line = find(wrapper, 'inclamo-ai-change-error');
      expect(line.attributes('data-error')).toBe(reason);
      expect(line.text()).toContain(words);
    }
    const quiet = await mountPage(live());
    expect(find(quiet, 'inclamo-ai-change-error').exists()).toBe(false);
  });

  it('offers the same control for a connection the store app made', async () => {
    const wrapper = await mountPage(live({}, { connected_via: 'app', connected_by: null }));

    expect(find(wrapper, 'inclamo-ai-connected-by').text()).toBe('The store app');
    expect(find(wrapper, 'inclamo-ai-change').exists()).toBe(true);
    expect(find(wrapper, 'inclamo-ai-inbox-3').find('input').element.checked).toBe(true);
    InclamoAPI.changeAiInboxes.mockResolvedValue({ data: { ...afterSave([3, 6]), connection: { ...afterSave([3, 6]).connection, connected_via: 'app', connected_by: null } } });

    await tick(wrapper, 6);
    await saveButton(wrapper).trigger('click');
    await flush();

    expect(InclamoAPI.changeAiInboxes).toHaveBeenCalledWith({ inbox_ids: [3, 6] });
    expect(find(wrapper, 'inclamo-ai-connected-by').text()).toBe('The store app');
  });
});
