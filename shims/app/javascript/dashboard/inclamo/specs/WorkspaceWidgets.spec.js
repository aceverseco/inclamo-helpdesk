import { mount, flushPromises } from '@vue/test-utils';
import { defineComponent, h, nextTick } from 'vue';
import { createRegistry, manifest, productLayout, entriesFor } from '../widgets/registry';
import LayoutEditor from '../widgets/LayoutEditor.vue';
import WidgetBoundary from '../widgets/WidgetBoundary.vue';
import { commerceEntry, readCommerce, clearCommerce, acceptPanel } from '../widgets/commerce';
import InclamoAPI from '../api';
import { knownOrder, forgetOrderState } from '../orderState';

vi.mock('../api', () => ({ default: { url: '/accounts/1/inclamo', getPanel: vi.fn() } }));
const loaders = Object.fromEntries(manifest.widgets.map(widget => [widget.id, async () => ({ render: () => h('span', widget.id) })]));

describe('compiled widget catalog', () => {
  it('accepts a fifth descriptor without host changes and rejects duplicates and unsupported placements', () => {
    const fixture = { id: 'fixture', placement: 'workspace-header', label: 'fixture' };
    const extended = createRegistry({ ...manifest, widgets: [...manifest.widgets, fixture] }, { ...loaders, fixture: async () => ({ render: () => h('span') }) });
    const layout = productLayout();
    layout.placements['workspace-header'].push({ id: 'fixture', collapsed: false });
    expect(entriesFor(layout, 'workspace-header', extended).map(entry => entry.id)).toEqual(['notifications', 'fixture']);
    expect(() => createRegistry({ ...manifest, widgets: [...manifest.widgets, manifest.widgets[0]] }, loaders)).toThrow('duplicate_widget');
    expect(() => createRegistry({ ...manifest, widgets: [{ ...manifest.widgets[0], placement: 'unknown' }] }, loaders)).toThrow('unsupported_placement');
  });

  it('skips a removed widget and does not automatically pin a new one', () => {
    const layout = { schema_version: 1, placements: { 'workspace-header': [{ id: 'removed', collapsed: false }], 'conversation-sidebar': [] } };
    expect(entriesFor(layout, 'workspace-header')).toEqual([]);
    expect(entriesFor(layout, 'conversation-sidebar')).toEqual([]);
  });

  it('previews removal, addition, collapse, keyboard movement and drag movement without changing other surfaces', async () => {
    const wrapper = mount(LayoutEditor, { props: { modelValue: productLayout(), 'onUpdate:modelValue': value => wrapper.setProps({ modelValue: value }) } });
    const sidebar = () => wrapper.findAll('section')[0];
    await sidebar().findAll('li')[0].findAll('button')[1].trigger('click');
    expect(wrapper.props('modelValue').placements['conversation-sidebar'][0].id).toBe('purchase-statistics');
    await sidebar().find('input').setValue(true);
    expect(wrapper.props('modelValue').placements['conversation-sidebar'][0].collapsed).toBe(true);
    await sidebar().findAll('li')[0].findAll('button').at(-1).trigger('click');
    expect(sidebar().text()).toContain('Add');
    await sidebar().findAll('button').at(-1).trigger('click');
    const items = sidebar().findAll('li');
    await items[2].trigger('dragstart');
    await items[0].trigger('drop');
    expect(wrapper.props('modelValue').placements['conversation-sidebar'][0].id).toBe('purchase-statistics');
    expect(wrapper.props('modelValue').placements['workspace-header']).toEqual([{ id: 'notifications', collapsed: false }]);
  });

  it('contains a broken widget without hiding a sibling', async () => {
    const Broken = defineComponent({ setup() { throw new Error('fixture'); }, render() {} });
    const wrapper = mount(defineComponent({ render: () => h('div', [h(WidgetBoundary, { identity: 'broken' }, { default: () => h(Broken) }), h('span', 'healthy')]) }));
    await nextTick();
    expect(wrapper.text()).toContain('This widget could not load');
    expect(wrapper.text()).toContain('healthy');
  });
});

describe('shared commerce context', () => {
  beforeEach(() => { clearCommerce(); forgetOrderState(); InclamoAPI.url = '/accounts/1/inclamo'; });
  it('deduplicates cards, honors freshness, and preserves marked-order reply context', async () => {
    const entry = commerceEntry(InclamoAPI.url, 7, 9);
    const data = { state: 'matched', orders: [], marked_order: { id: 'tied' }, connection: { connected: true, status: 'working' } };
    InclamoAPI.getPanel.mockResolvedValue({ data });
    await Promise.all([readCommerce(entry), readCommerce(entry)]);
    await readCommerce(entry);
    expect(InclamoAPI.getPanel).toHaveBeenCalledTimes(1);
    expect(knownOrder(7).id).toBe('tied');
    entry.updatedAt -= 60001;
    await readCommerce(entry);
    expect(InclamoAPI.getPanel).toHaveBeenCalledTimes(2);
  });
  it('keeps late account/contact responses out of the current context and reply cache', async () => {
    let resolve;
    InclamoAPI.getPanel.mockReturnValueOnce(new Promise(done => { resolve = done; }));
    const old = commerceEntry(InclamoAPI.url, 7, 9);
    const pending = readCommerce(old);
    InclamoAPI.url = '/accounts/2/inclamo';
    const current = commerceEntry(InclamoAPI.url, 7, 10);
    acceptPanel(current, { state: 'limited', marked_order: null });
    resolve({ data: { state: 'matched', marked_order: { id: 'old' } } });
    await pending;
    await flushPromises();
    expect(current.panel.state).toBe('limited');
    expect(knownOrder(7)).toBeNull();
    expect(InclamoAPI.getPanel).toHaveBeenCalledWith(7, undefined, '/accounts/1/inclamo');
  });
  it('ignores old contact and previous-login responses within the same account', async () => {
    let resolve;
    const old = commerceEntry(InclamoAPI.url, 7, 9);
    InclamoAPI.getPanel.mockReturnValueOnce(new Promise(done => { resolve = done; }));
    const pending = readCommerce(old);
    const current = commerceEntry(InclamoAPI.url, 7, 10);
    acceptPanel(current, { state: 'matched', marked_order: { id: 'current' } });
    resolve({ data: { state: 'matched', marked_order: { id: 'old' } } }); await pending;
    expect(knownOrder(7).id).toBe('current');
    clearCommerce(); forgetOrderState();
    acceptPanel(current, { state: 'matched', marked_order: { id: 'previous-login' } });
    expect(knownOrder(7)).toBeUndefined();
  });
  it('answers a forced read with a read started after it, not with one already under way', async () => {
    InclamoAPI.getPanel.mockReset();
    let finishEarlier;
    InclamoAPI.getPanel
      .mockReturnValueOnce(new Promise(done => { finishEarlier = done; }))
      .mockResolvedValueOnce({ data: { state: 'matched', orders: [{ id: 'after-the-action' }] } });
    const entry = commerceEntry(InclamoAPI.url, 7, 9);
    const earlier = readCommerce(entry);
    const forced = readCommerce(entry, true);
    expect(InclamoAPI.getPanel).toHaveBeenCalledTimes(2);
    await forced;
    finishEarlier({ data: { state: 'matched', orders: [{ id: 'before-the-action' }] } });
    await earlier;
    await flushPromises();
    expect(entry.panel.orders[0].id).toBe('after-the-action');
    expect(entry.pending).toBeNull();
  });
});
