import { describe, it, expect, afterEach } from 'vitest';
import { resolveSettings, pageAllowed, decorateLauncher } from '../inclamoWidget';

describe('Website widget launcher', () => {
  afterEach(() => {
    document.body.innerHTML = '';
    delete window.$chatwoot;
  });
  const launcher = () => {
    document.body.innerHTML =
      '<div id="cw-bubble-holder"><button class="woot-widget-bubble"><svg><path d="M0 0"/></svg></button></div>';
    return document.querySelector('.woot-widget-bubble');
  };
  const images = button => button.querySelectorAll('.inclamo-launcher-image');

  it('shows one custom icon however often the widget reports it loaded', () => {
    const button = launcher();
    window.$chatwoot = {
      baseUrl: 'https://help.example.test',
      inclamoWidget: { icon: 'custom', icon_url: '/icons/one.png' },
    };
    decorateLauncher({ checkVisibility: false });
    // $chatwoot.reset() reloads the frame, and the frame reports 'loaded' again.
    decorateLauncher({ checkVisibility: false });
    expect(images(button)).toHaveLength(1);

    window.$chatwoot.inclamoWidget = { icon: 'custom', icon_url: '/icons/two.png' };
    decorateLauncher({ checkVisibility: false });
    expect(images(button)).toHaveLength(1);
    expect(images(button)[0].src).toBe('https://help.example.test/icons/two.png');
  });

  it('drops the custom icon when the saved icon is no longer custom', () => {
    const button = launcher();
    window.$chatwoot = {
      baseUrl: 'https://help.example.test',
      inclamoWidget: { icon: 'custom', icon_url: '/icons/one.png' },
    };
    decorateLauncher({ checkVisibility: false });
    button.querySelector('svg').style.display = 'none';
    window.$chatwoot.inclamoWidget = { icon: 'help' };
    decorateLauncher({ checkVisibility: false });
    expect(images(button)).toHaveLength(0);
    expect(button.querySelector('svg').style.display).toBe('');
  });
});
const channel = {
  locale: 'en',
  enabledLanguages: [{ iso_639_1_code: 'en' }, { iso_639_1_code: 'fr' }],
  inclamoWidget: {
    position: 'left',
    type: 'expanded_bubble',
    launcher_title: 'Help',
    theme: 'dark',
    language_mode: 'browser',
    locale: 'en',
  },
};
describe('Published website widget configuration', () => {
  it('uses shared settings without confusing SDK defaults with explicit site choices', () => {
    expect(resolveSettings(channel, {}, 'fr-CA')).toEqual({
      position: 'left',
      type: 'expanded_bubble',
      launcherTitle: 'Help',
      darkMode: 'dark',
      locale: 'fr',
    });
    expect(
      resolveSettings(
        channel,
        { position: 'right', darkMode: 'light', locale: 'en' },
        'fr'
      )
    ).toMatchObject({ position: 'right', darkMode: 'light', locale: 'en' });
  });
  it('falls back to account locale and preserves explicit browser-language selection', () => {
    expect(resolveSettings(channel, {}, 'zz')).toHaveProperty('locale', 'en');
    expect(
      resolveSettings(channel, { locale: 'en', useBrowserLanguage: true }, 'fr')
    ).toHaveProperty('locale', 'fr');
  });
  it('keeps the native behavior when no extension is published', () => {
    expect(
      resolveSettings({ ...channel, inclamoWidget: undefined }, {}, 'en')
    ).toMatchObject({
      position: 'right',
      type: 'standard',
      darkMode: 'light',
      locale: 'en',
    });
  });
  it('honors explicit browser-language opt-out and ignores malformed overrides', () => {
    expect(
      resolveSettings(channel, { useBrowserLanguage: false }, 'fr')
    ).toHaveProperty('locale', 'en');
    expect(
      resolveSettings(
        channel,
        { locale: 42, useBrowserLanguage: 'false' },
        'fr'
      )
    ).toHaveProperty('locale', 'fr');
    expect(
      resolveSettings(
        channel,
        { useBrowserLanguage: false, locale: 'fr' },
        'en'
      )
    ).toHaveProperty('locale', 'fr');
  });
  it('matches path rules across query strings and fragments without substring false positives', () => {
    const exclude = {
      mode: 'exclude',
      rules: [{ match: 'exact', path: '/checkout' }],
    };
    expect(pageAllowed(exclude, 'https://shop.test/checkout?cart=1#pay')).toBe(
      false
    );
    expect(pageAllowed(exclude, 'https://shop.test/checkout-help')).toBe(true);
    expect(
      pageAllowed(
        { mode: 'include', rules: [{ match: 'prefix', path: '/help/' }] },
        'https://shop.test/help/returns'
      )
    ).toBe(true);
    expect(
      pageAllowed(
        { mode: 'include', rules: [{ match: 'prefix', path: '/help/' }] },
        'https://shop.test/products'
      )
    ).toBe(false);
  });
  it('falls back to native defaults for unusable saved values', () => {
    const unusable = {
      ...channel,
      inclamoWidget: {
        position: 'middle',
        type: 'giant',
        theme: 'neon',
        launcher_title: 42,
        language_mode: 'browser',
      },
    };
    expect(resolveSettings(unusable, {}, 'zz')).toEqual({
      position: 'right',
      type: 'standard',
      launcherTitle: '',
      darkMode: 'light',
      locale: 'en',
    });
    expect(
      resolveSettings({ ...channel, inclamoWidget: 'broken' }, {}, 'en')
    ).toMatchObject({ position: 'right', type: 'standard' });
    expect(pageAllowed({ mode: 'sideways' }, 'https://shop.test/a')).toBe(true);
    expect(
      pageAllowed({ mode: 'exclude', rules: 'broken' }, 'https://shop.test/a')
    ).toBe(true);
    expect(
      pageAllowed(
        { mode: 'exclude', rules: [null, { match: 'prefix', path: 7 }] },
        'https://shop.test/a'
      )
    ).toBe(true);
  });
});
