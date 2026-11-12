import { mount, enableAutoUnmount } from '@vue/test-utils';
import { captureFrame } from '../support/capture';
import { locationContext, submissionId } from '../support/state';
import SupportForm from '../support/SupportForm.vue';
enableAutoUnmount(afterEach);

describe('support privacy and fallbacks', () => {
  afterEach(() => vi.unstubAllGlobals());
  it('retains only a section name from paths with customer identifiers, tokens or fragments', () => {
    expect(locationContext('/app/accounts/4/conversations/8?token=secret#customer@email.test')).toBe('conversation');
    expect(locationContext('/app/accounts/4/contacts/customer@email.test')).toBe('contacts');
    expect(locationContext('/unknown?credential=secret')).toBe('workspace');
  });

  it('creates secure stable-format submission identities on HTTP upload-only installations', () => {
    const fill = globalThis.crypto.getRandomValues.bind(globalThis.crypto);
    vi.stubGlobal('crypto', { getRandomValues: fill });
    const first = submissionId();
    expect(first).toMatch(/^[a-f\d]{8}-[a-f\d]{4}-4[a-f\d]{3}-[89ab][a-f\d]{3}-[a-f\d]{12}$/);
    expect(submissionId()).not.toBe(first);
  });

  it('does not upload on capture denial and preserves the support draft', async () => {
    const capture = vi.fn().mockRejectedValue(new DOMException('Cancelled', 'NotAllowedError'));
    vi.stubGlobal('navigator', { mediaDevices: { getDisplayMedia: capture } });
    const post = vi.fn(); vi.stubGlobal('axios', { post });
    const draft = { body: 'Keep this description', category: 'question', files: [], context: {} };
    const wrapper = mount(SupportForm, { props: { draft, metadata: { author: { name: 'Synthetic Author' }, account: { name: 'Synthetic Account' } } } });
    await wrapper.findAll('button').find(button => button.text() === 'Take screenshot').trigger('click');
    await new Promise(resolve => setTimeout(resolve, 0));
    expect(draft.body).toBe('Keep this description');
    expect(draft.files).toEqual([]);
    expect(wrapper.text()).toContain('Capture was cancelled or unavailable');
    expect(post).not.toHaveBeenCalled();
  });

  it('stops every capture track even when frame conversion fails', async () => {
    const stop = vi.fn();
    const stream = { getTracks: () => [{ stop }] };
    vi.stubGlobal('navigator', { mediaDevices: { getDisplayMedia: vi.fn().mockResolvedValue(stream) } });
    const video = { play: vi.fn().mockResolvedValue(), videoWidth: 200, videoHeight: 100, srcObject: null };
    const canvas = { width: 0, height: 0, getContext: () => ({ drawImage() { throw new Error('conversion failure'); } }) };
    const create = vi.spyOn(document, 'createElement').mockImplementation(name => name === 'video' ? video : canvas);
    const after = vi.fn();
    try {
      await expect(captureFrame(() => {}, after)).rejects.toThrow('conversion failure');
      expect(stop).toHaveBeenCalled(); expect(video.srcObject).toBeNull(); expect(after).toHaveBeenCalledOnce();
    } finally { create.mockRestore(); }
  });

  it('requires description while allowing a text-only request without browser capture', async () => {
    vi.stubGlobal('navigator', {});
    const draft = { body: '', category: 'question', files: [], context: {} };
    const wrapper = mount(SupportForm, { props: { draft, metadata: { author: { name: 'Synthetic Author', email: 'author@example.test' }, account: { name: 'Synthetic Account' } } } });
    const submit = wrapper.get('[data-testid="support-submit"]');
    expect(submit.attributes()).toHaveProperty('disabled');
    await wrapper.get('textarea').setValue('A question without a screenshot');
    await wrapper.setProps({ draft: { ...draft } });
    expect(submit.attributes()).not.toHaveProperty('disabled');
    await submit.trigger('click');
    expect(wrapper.emitted('submit')).toHaveLength(1);
    expect(wrapper.text()).toContain('author@example.test');
    expect(wrapper.text()).not.toContain('Take screenshot');
  });
  it('times out a stream that never produces a frame and stops its tracks', async () => {
    vi.useFakeTimers();
    const stop = vi.fn(); const cancel = vi.fn();
    vi.stubGlobal('navigator', { mediaDevices: { getDisplayMedia: vi.fn().mockResolvedValue({ getTracks: () => [{ stop }] }) } });
    const video = { play: vi.fn().mockResolvedValue(), requestVideoFrameCallback: () => 17, cancelVideoFrameCallback: cancel };
    const canvas = {};
    const create = vi.spyOn(document, 'createElement').mockImplementation(name => name === 'video' ? video : canvas);
    try {
      const result = expect(captureFrame()).rejects.toThrow('capture_unavailable');
      await vi.advanceTimersByTimeAsync(10001); await result;
      expect(stop).toHaveBeenCalled(); expect(cancel).toHaveBeenCalledWith(17); expect(video.srcObject).toBeNull();
    } finally { create.mockRestore(); vi.useRealTimers(); }
  });

});
