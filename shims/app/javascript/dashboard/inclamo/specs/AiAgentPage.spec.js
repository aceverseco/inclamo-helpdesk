import { mount } from '@vue/test-utils';
import AiAgentPage from '../components/AiAgentPage.vue';
import InclamoAPI from '../api';
import { stubs, flush } from './helpers';

vi.mock('../api', () => ({
  default: {
    getAiConnection: vi.fn(),
    connectAi: vi.fn(),
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

  it('says when the page cannot be loaded', async () => {
    InclamoAPI.getAiConnection.mockRejectedValue({ response: { status: 403 } });
    const wrapper = mount(AiAgentPage, { global: { stubs } });
    await flush();

    expect(find(wrapper, 'inclamo-ai-failed').exists()).toBe(true);
  });
});
