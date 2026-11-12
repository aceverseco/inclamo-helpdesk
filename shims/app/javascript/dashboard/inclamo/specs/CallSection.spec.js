import { h } from 'vue';
import { mount } from '@vue/test-utils';
import CallSection from '../components/CallSection.vue';
import sidebarSections from '../sidebarSections';
import { dateTime } from '../format';

vi.mock('../api', () => ({ default: { getConversationSla: vi.fn() } }));

const attributes = (overrides = {}) => ({
  inclamo_call_entry: 'inbound',
  inclamo_call_line: '+15550100100',
  inclamo_call_caller: '+15550100001',
  inclamo_call_duration: 192,
  inclamo_call_ended_at: '2026-11-07T14:03:12Z',
  inclamo_call_outcome: 'request',
  inclamo_call_matched_by: 'phone',
  inclamo_call_recording: 'https://example.com/calls/c-17',
  ...overrides,
});

// The dashboard's store, reduced to the conversations the sidebar reads.
const storeWith = conversations => ({
  getters: { getConversationById: id => conversations.find(conversation => conversation.id === Number(id)) },
});
const dashboard = { store: storeWith([]) };
vi.mock('dashboard/composables/store', () => ({ useStore: () => dashboard.store }));

const show = (custom, id = 7) => {
  dashboard.store = storeWith([{ id: 7, custom_attributes: custom }]);
  return mount(CallSection, { props: { conversationId: id } });
};
const row = (wrapper, name) => wrapper.find(`[data-testid="inclamo-call-${name}"]`);

describe('CallSection', () => {
  it('shows the entry, the line, the caller, the duration, the end, the outcome, how the contact was found and the recording', () => {
    const wrapper = show(attributes());

    expect(row(wrapper, 'entry').text()).toBe("Call to the shop's number");
    expect(row(wrapper, 'line').text()).toContain('+15550100100');
    expect(row(wrapper, 'caller').text()).toContain('+15550100001');
    expect(row(wrapper, 'duration').text()).toContain('3 min 12 s');
    expect(row(wrapper, 'ended').text()).toContain(dateTime('2026-11-07T14:03:12Z'));
    expect(row(wrapper, 'outcome').text()).toContain('Request for the team');
    expect(row(wrapper, 'matched').text()).toContain('Found by number');
    const link = row(wrapper, 'recording');
    expect(link.attributes()).toMatchObject({ href: 'https://example.com/calls/c-17', target: '_blank', rel: 'noopener noreferrer' });
  });

  it('has no recording link when the AI service sent none', () => {
    const wrapper = show(attributes({ inclamo_call_recording: undefined }));

    expect(row(wrapper, 'recording').exists()).toBe(false);
    expect(row(wrapper, 'outcome').exists()).toBe(true);
  });

  it('offers no link that is not https', () => {
    const wrapper = show(attributes({ inclamo_call_recording: 'javascript:alert(1)' }));

    expect(row(wrapper, 'recording').exists()).toBe(false);
  });

  it('says there was no number, and leaves out the line of a call from the storefront', () => {
    const wrapper = show(attributes({ inclamo_call_entry: 'web', inclamo_call_line: undefined, inclamo_call_caller: undefined, inclamo_call_matched_by: 'anonymous' }));

    expect(row(wrapper, 'entry').text()).toBe('Call from the storefront button');
    expect(row(wrapper, 'caller').text()).toContain('No number');
    expect(row(wrapper, 'line').exists()).toBe(false);
    expect(row(wrapper, 'matched').text()).toContain('New contact, no caller id');
  });

  it('shows an outcome it has no words for as the AI service sent it', () => {
    const wrapper = show(attributes({ inclamo_call_outcome: 'voicemail_left' }));

    expect(row(wrapper, 'outcome').text()).toContain('voicemail_left');
  });

  it('shows a call of no seconds and one without a duration', () => {
    expect(row(show(attributes({ inclamo_call_duration: 0 })), 'duration').text()).toContain('0 s');
    expect(row(show(attributes({ inclamo_call_duration: undefined })), 'duration').exists()).toBe(false);
  });

  it('shows nothing for a conversation that is not a call', () => {
    expect(show({ order_number: '1042' }).find('[data-testid="inclamo-call-section"]').exists()).toBe(false);
    expect(show(attributes(), 8).find('[data-testid="inclamo-call-section"]').exists()).toBe(false);
  });

  describe('in the sidebar', () => {
    const entry = () => sidebarSections.find(section => section.name === 'inclamo_call');
    // Asked the way ContactPanel asks: while it renders.
    const visibleFor = (id, conversations) =>
      mount({ render: () => h('span', entry().visible(id) ? 'shown' : 'hidden') }, { global: { mocks: { $store: storeWith(conversations) } } }).text();

    it('is a section of its own', () => {
      expect(entry()).toMatchObject({ openKey: 'is_inclamo_call_open', component: CallSection });
      expect(entry().title()).toBe('Call');
    });

    it('is shown on a conversation filed as a call and on no other', () => {
      const conversations = [
        { id: 7, custom_attributes: attributes() },
        { id: 8, custom_attributes: {} },
        { id: 9 },
      ];

      expect(visibleFor(7, conversations)).toBe('shown');
      expect(visibleFor(8, conversations)).toBe('hidden');
      expect(visibleFor(9, conversations)).toBe('hidden');
      expect(visibleFor(10, conversations)).toBe('hidden');
    });
  });
});
