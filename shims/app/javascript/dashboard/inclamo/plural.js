// Which form of a counted word a language needs. English has two forms and is
// served by the defaults; Ukrainian has three (1 розмова, 2 розмови, 5 розмов)
// and neither Chatwoot nor its translation library knows them.

// A language code as Chatwoot writes it (pt_BR) in the form Intl accepts.
export const intlLanguage = code => {
  const tag = String(code || 'en').replace(/_/g, '-');
  try {
    return Intl.getCanonicalLocales(tag)[0] || 'en';
  } catch (error) {
    return 'en';
  }
};

// The form a number takes: 'one', 'few', 'many' or 'other'.
export const category = (language, count) => {
  const number = Math.abs(Number(count));
  return new Intl.PluralRules(intlLanguage(language)).select(Number.isNaN(number) ? 0 : number);
};

// For the translation library: the place of the right form among the forms a
// text gives, separated by "|". A text with three forms gives one, few, many.
// A text with two keeps what it meant before: the first for 1, the second for
// every other number.
const ORDER = { one: 0, few: 1, many: 2, other: 2 };
const threeForms = language => (choice, formsCount) => {
  if (formsCount < 3) return Math.abs(choice) === 1 ? 0 : 1;
  return ORDER[category(language, choice)];
};

export const pluralRules = { uk: threeForms('uk') };

// The library holds its rules where only it can set them, under a symbol with
// this description. If a later version of the library has no such setter the
// rules are not installed, and texts with two forms read as they always did.
const SETTER = '__setPluralRules';
export const installPluralRules = composer => {
  const setter = composer && Object.getOwnPropertySymbols(composer).find(symbol => symbol.description === SETTER);
  if (!setter || typeof composer[setter] !== 'function') return false;
  composer[setter]({ ...(composer.pluralRules || {}), ...pluralRules });
  return true;
};
