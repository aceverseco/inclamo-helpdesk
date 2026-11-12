// Small presentation adapter; messaging stays in Chatwoot's existing SDK.
import css from './inclamoWidget.css?inline';

// Values the widget can use; anything else falls back to the native default.
const isObject = value =>
  value !== null && typeof value === 'object' && !Array.isArray(value);
const SAVED = {
  position: ['left', 'right'],
  type: ['standard', 'expanded_bubble'],
  theme: ['light', 'dark', 'auto'],
};
const savedChoice = (saved, key, fallback) =>
  SAVED[key].includes(saved[key]) ? saved[key] : fallback;
export const savedWidget = channel =>
  isObject(channel?.inclamoWidget) ? channel.inclamoWidget : {};

export function pageAllowed(visibility, url) {
  if (!isObject(visibility) || !['include', 'exclude'].includes(visibility.mode))
    return true;
  let pathname;
  try {
    pathname = new URL(url, window.location.href).pathname;
  } catch {
    return true;
  }
  const rules = Array.isArray(visibility.rules) ? visibility.rules : [];
  const matches = rules.some(
    rule =>
      isObject(rule) &&
      typeof rule.path === 'string' &&
      (rule.match === 'prefix'
        ? pathname.startsWith(rule.path)
        : pathname === rule.path)
  );
  return visibility.mode === 'include' ? matches : !matches;
}

export function resolveSettings(
  channel,
  explicit = {},
  browserLanguage = navigator.language
) {
  const saved = savedWidget(channel);
  const locales = (channel.enabledLanguages || []).map(l => l.iso_639_1_code);
  const chooseLocale = value => {
    const locale = (typeof value === 'string' ? value : '').replace('-', '_');
    if (locales.includes(locale)) return locale;
    const base = locale.split('_')[0];
    return locales.includes(base) ? base : channel.locale;
  };
  const has = key => Object.prototype.hasOwnProperty.call(explicit, key);
  const result = {
    position: savedChoice(saved, 'position', 'right'),
    type: savedChoice(saved, 'type', 'standard'),
    launcherTitle:
      typeof saved.launcher_title === 'string' ? saved.launcher_title : '',
    darkMode: savedChoice(saved, 'theme', 'light'),
    locale: chooseLocale(
      saved.language_mode === 'browser'
        ? browserLanguage
        : saved.locale || channel.locale
    ),
  };
  const options = {
    position: ['left', 'right'],
    type: ['standard', 'expanded_bubble'],
    darkMode: ['light', 'dark', 'auto'],
  };
  Object.entries(options).forEach(([key, allowed]) => {
    if (has(key) && allowed.includes(explicit[key]))
      result[key] = explicit[key];
  });
  if (has('launcherTitle') && typeof explicit.launcherTitle === 'string')
    result.launcherTitle = explicit.launcherTitle;
  if (explicit.useBrowserLanguage === true)
    result.locale = chooseLocale(browserLanguage);
  else if (has('locale') && typeof explicit.locale === 'string')
    result.locale = chooseLocale(explicit.locale);
  else if (explicit.useBrowserLanguage === false)
    result.locale = chooseLocale(saved.locale || channel.locale);
  return result;
}

export function applySettings(channel) {
  Object.assign(
    window.$chatwoot,
    resolveSettings(channel, window.chatwootSettings || {})
  );
  window.$chatwoot.inclamoWidget = savedWidget(channel);
  const holder = document.getElementById('cw-widget-holder');
  holder?.classList.remove('woot-elements--left', 'woot-elements--right');
  holder?.classList.add(`woot-elements--${window.$chatwoot.position}`);
  const style = document.getElementById('cw-widget-styles');
  if (style && !style.dataset.inclamo) {
    style.append(document.createTextNode(css));
    style.dataset.inclamo = 'true';
  }
}

export function updatePageVisibility(
  url = window.location.href,
  explicitOpen = false
) {
  const cw = window.$chatwoot;
  const allowed = pageAllowed(cw.inclamoWidget?.visibility, url);
  cw.inclamoPageAllowed = allowed;
  ['cw-widget-holder', 'cw-bubble-holder'].forEach(id => {
    document
      .getElementById(id)
      ?.classList.toggle('inclamo-page-hidden', !allowed && !explicitOpen);
  });
  return allowed;
}

const paths = {
  message: 'M30 35h180v135H85l-55 40V35zm25 25v101l22-16h108V60H55z',
  help: 'M120 10a110 110 0 1 0 0 220 110 110 0 0 0 0-220zm0 195a85 85 0 1 1 0-170 85 85 0 0 1 0 170zm-13-49h26v26h-26zm0-17v-13c0-29 31-28 31-49 0-23-36-24-37 1H77c0-56 86-55 86-1 0 35-30 34-30 52v10z',
};

export function decorateLauncher({ checkVisibility = true } = {}) {
  const cw = window.$chatwoot;
  const saved = cw.inclamoWidget || {};
  const button = document.querySelector(
    '#cw-bubble-holder .woot-widget-bubble:not(.woot--close)'
  );
  const svg = button?.querySelector('svg');
  const close = document.querySelector('#cw-bubble-holder .woot--close');
  if (!button) return;
  button.setAttribute('aria-label', cw.launcherTitle || 'Open chat');
  close?.setAttribute('aria-label', 'Close chat');
  if (paths[saved.icon])
    svg?.querySelector('path')?.setAttribute('d', paths[saved.icon]);
  // The widget reports 'loaded' again after $chatwoot.reset(): the launcher
  // keeps one custom icon, the one the settings name now.
  const wanted =
    saved.icon === 'custom' && typeof saved.icon_url === 'string' && saved.icon_url && svg
      ? new URL(saved.icon_url, cw.baseUrl).href
      : null;
  const shown = button.querySelector('.inclamo-launcher-image');
  if (shown && shown.src !== wanted) {
    shown.remove();
    if (svg) svg.style.display = '';
  }
  if (wanted && !button.querySelector('.inclamo-launcher-image')) {
    const img = document.createElement('img');
    img.className = 'inclamo-launcher-image';
    img.alt = '';
    img.src = wanted;
    img.onload = () => {
      svg.style.display = 'none';
    };
    img.onerror = () => {
      img.remove();
      svg.style.display = '';
    };
    button.prepend(img);
  }
  ['cw-widget-holder', 'cw-bubble-holder'].forEach(id => {
    const node = document.getElementById(id);
    node?.style.setProperty(
      '--inclamo-widget-x',
      `${Number.isInteger(saved.offset_x) ? Math.min(160, Math.max(0, saved.offset_x)) : 20}px`
    );
    node?.style.setProperty(
      '--inclamo-widget-y',
      `${Number.isInteger(saved.offset_y) ? Math.min(160, Math.max(0, saved.offset_y)) : 20}px`
    );
  });
  if (checkVisibility) updatePageVisibility();
  document
    .getElementById('chatwoot_live_chat_widget')
    ?.setAttribute('title', 'Customer support chat');
}
