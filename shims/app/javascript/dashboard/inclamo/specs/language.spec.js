import { h, nextTick } from 'vue';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { formatLanguage, has, language, setLanguage, t } from '../i18n';
import { category, installPluralRules, intlLanguage } from '../plural';
import { useInterfaceLanguage } from '../language';
import { date, dateTime, money } from '../format';
import ActivityTime from '../workspace/ActivityTime.vue';

vi.mock('../locale/en.json', () => ({
  default: {
    TITLE: 'Orders',
    RELOAD: 'Reload the page',
    QUEUE: { COUNT: '{count} conversations', OVERDUE: '{overdue} overdue of {total}' },
    WHY_NOT: { other: 'Another reason' },
    WORKSPACE: { TIME: { now: 'now', m: '{count}m', h: '{count}h', d: '{count}d', mo: '{count}mo', y: '{count}y' } },
  },
}));
vi.mock('../locale/uk.json', () => ({
  default: {
    TITLE: 'Замовлення',
    QUEUE: {
      COUNT: { one: '{count} розмова', few: '{count} розмови', many: '{count} розмов', other: '{count} розмови' },
      OVERDUE: { by: 'overdue', one: '{overdue} прострочена з {total}', few: '{overdue} прострочені з {total}', many: '{overdue} прострочених з {total}' },
    },
    WHY_NOT: { other: 'Інша причина' },
    WORKSPACE: { TIME: { now: 'щойно', m: '{count} хв', h: '{count} год', d: '{count} д', mo: '{count} міс', y: '{count} р' } },
  },
}));

const plain = text => text.replace(/\s/g, ' ');

afterEach(() => setLanguage('en'));

describe('the language of the overlay\'s own texts', () => {
  it('is English until told otherwise, with the texts as they were', () => {
    expect(language()).toBe('en');
    expect(t('TITLE')).toBe('Orders');
    expect(t('QUEUE.COUNT', { count: 1 })).toBe('1 conversations');
    expect(t('QUEUE.COUNT', { count: 5 })).toBe('5 conversations');
  });

  it('gives the chosen language\'s text', () => {
    setLanguage('uk');

    expect(t('TITLE')).toBe('Замовлення');
    expect(t('WHY_NOT.other')).toBe('Інша причина');
  });

  it('gives the English text where the chosen language has none, never the key', () => {
    setLanguage('uk');

    expect(t('RELOAD')).toBe('Reload the page');
    expect(has('RELOAD')).toBe(true);
  });

  it.each(['de', 'pt_BR', 'zh_CN', '', null, undefined])('is English for a language without a file: %s', code => {
    setLanguage(code);

    expect(t('TITLE')).toBe('Orders');
    expect(t('QUEUE.COUNT', { count: 2 })).toBe('2 conversations');
  });

  it('changes a text already on the screen when the language changes', async () => {
    const wrapper = mount({ render: () => h('p', t('TITLE')) });
    expect(wrapper.text()).toBe('Orders');

    setLanguage('uk');
    await nextTick();
    expect(wrapper.text()).toBe('Замовлення');

    setLanguage('en');
    await nextTick();
    expect(wrapper.text()).toBe('Orders');
  });
});

describe('counted words', () => {
  it.each([
    [0, '0 розмов'],
    [1, '1 розмова'],
    [2, '2 розмови'],
    [3, '3 розмови'],
    [5, '5 розмов'],
    [11, '11 розмов'],
    [14, '14 розмов'],
    [21, '21 розмова'],
    [22, '22 розмови'],
    [25, '25 розмов'],
    [101, '101 розмова'],
    [1.5, '1.5 розмови'],
  ])('take the Ukrainian form for %s', (count, text) => {
    setLanguage('uk');

    expect(t('QUEUE.COUNT', { count })).toBe(text);
  });

  it('follow the parameter the forms name', () => {
    setLanguage('uk');

    expect(t('QUEUE.OVERDUE', { overdue: 1, total: 5 })).toBe('1 прострочена з 5');
    expect(t('QUEUE.OVERDUE', { overdue: 3, total: 5 })).toBe('3 прострочені з 5');
    expect(t('QUEUE.OVERDUE', { overdue: 7, total: 9 })).toBe('7 прострочених з 9');
  });

  it('fall back to the form for many when a form is not written', () => {
    setLanguage('uk');

    expect(t('QUEUE.OVERDUE', { overdue: 1.5, total: 5 })).toBe('1.5 прострочених з 5');
  });

  it('know the forms of a language written the way Chatwoot writes it', () => {
    expect(intlLanguage('pt_BR')).toBe('pt-BR');
    expect(intlLanguage('not a language')).toBe('en');
    expect(category('uk', 21)).toBe('one');
    expect(category('en', 21)).toBe('other');
  });
});

// The real library, as Chatwoot creates it: no rules of its own.
const application = () =>
  createI18n({
    legacy: false,
    locale: 'en',
    messages: {
      en: { COUNT: '{n} conversation | {n} conversations' },
      uk: { COUNT: '{n} розмова | {n} розмови | {n} розмов', OLD: '{n} діалог | {n} діалогів' },
    },
  });
const counted = (composer, key, numbers) => numbers.map(n => composer.t(key, { n }, n));

describe('the forms of counted words in Chatwoot\'s texts', () => {
  it('are three for Ukrainian once the rule is installed', () => {
    const composer = application().global;
    composer.locale.value = 'uk';
    expect(counted(composer, 'COUNT', [1, 2])).toEqual(['1 розмови', '2 розмов']);

    expect(installPluralRules(composer)).toBe(true);

    expect(counted(composer, 'COUNT', [1, 2, 5, 11, 21, 22, 101])).toEqual([
      '1 розмова',
      '2 розмови',
      '5 розмов',
      '11 розмов',
      '21 розмова',
      '22 розмови',
      '101 розмова',
    ]);
  });

  it('leave a Ukrainian text with two forms reading as before', () => {
    const composer = application().global;
    composer.locale.value = 'uk';
    const before = counted(composer, 'OLD', [0, 1, 2, 5, 21]);

    installPluralRules(composer);

    expect(counted(composer, 'OLD', [0, 1, 2, 5, 21])).toEqual(before);
    expect(before).toEqual(['0 діалогів', '1 діалог', '2 діалогів', '5 діалогів', '21 діалогів']);
  });

  it('leave English untouched', () => {
    const composer = application().global;
    installPluralRules(composer);

    expect(counted(composer, 'COUNT', [1, 2, 21])).toEqual(['1 conversation', '2 conversations', '21 conversations']);
  });

  it('do nothing, without an error, where the library has no setter', () => {
    expect(installPluralRules({ pluralRules: {} })).toBe(false);
    expect(installPluralRules(null)).toBe(false);
  });
});

describe('following Chatwoot\'s choice of language', () => {
  const start = () => {
    const i18n = application();
    const wrapper = mount(
      {
        setup() {
          useInterfaceLanguage();
          return () => h('p', t('TITLE'));
        },
      },
      { global: { plugins: [i18n] } }
    );
    return { i18n, wrapper };
  };

  it('takes the language the application has and every later one', async () => {
    const { i18n, wrapper } = start();
    expect(language()).toBe('en');

    i18n.global.locale.value = 'uk';
    await nextTick();
    expect(language()).toBe('uk');
    expect(wrapper.text()).toBe('Замовлення');

    i18n.global.locale.value = 'de';
    await nextTick();
    expect(wrapper.text()).toBe('Orders');
  });

  it('gives Chatwoot\'s texts the Ukrainian forms', () => {
    const { i18n } = start();
    i18n.global.locale.value = 'uk';

    expect(counted(i18n.global, 'COUNT', [1, 3, 5])).toEqual(['1 розмова', '3 розмови', '5 розмов']);
  });
});

describe('dates, times and money', () => {
  const day = '2026-11-12T10:00:00Z';

  it('are written the Ukrainian way in a Ukrainian interface', () => {
    setLanguage('uk');

    expect(formatLanguage()).toBe('uk');
    expect(plain(date(day))).toBe('12 лист. 2026 р.');
    expect(plain(dateTime(day))).toContain('12 лист. 2026 р.');
    expect(plain(money(1234.5, 'USD'))).toBe('1 234,50 USD');
    expect(plain(money('20.00', 'UAH'))).toBe('20,00 ₴');
  });

  it('are written the English way in an English interface', () => {
    expect(date(day)).toBe('Nov 12, 2026');
    expect(money(1234.5, 'USD')).toBe('$1,234.50');
  });

  it('survive a language Intl does not know', () => {
    setLanguage('not a language');

    expect(money(5, 'USD')).toBe('$5.00');
  });
});

describe('the age of a moment on the workspace', () => {
  const now = Date.parse('2026-11-12T10:00:00Z') / 1000;
  const ages = { now: now - 10, minutes: now - 5 * 60, hours: now - 2 * 3600, days: now - 3 * 86400, months: now - 65 * 86400, years: now - 800 * 86400 };
  const shown = () => Object.fromEntries(Object.entries(ages).map(([name, timestamp]) => [name, mount(ActivityTime, { props: { timestamp } }).text()]));

  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(now * 1000);
  });
  afterEach(() => vi.useRealTimers());

  it('reads in English as Chatwoot words it', () => {
    expect(shown()).toEqual({ now: 'now', minutes: '5m', hours: '2h', days: '3d', months: '2mo', years: '2y' });
  });

  it('reads in Ukrainian in a Ukrainian interface', () => {
    setLanguage('uk');

    expect(shown()).toEqual({ now: 'щойно', minutes: '5 хв', hours: '2 год', days: '3 д', months: '2 міс', years: '2 р' });
  });
});
