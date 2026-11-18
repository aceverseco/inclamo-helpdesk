// The overlay's own interface strings. Chatwoot's locale index is a fixed list
// of files, so ours live here. They follow the interface language Chatwoot has
// chosen (the staff member's, else the account's): the stand-in for App.vue
// passes it on with setLanguage. A text the chosen language lacks is shown in
// English.
import { ref } from 'vue';
import en from './locale/en.json';
import uk from './locale/uk.json';
import { category, intlLanguage } from './plural';

const dictionaries = { en, uk };
// Until the application tells otherwise: the language the page was served in.
const current = ref(globalThis.window?.chatwootConfig?.selectedLocale || 'en');

export const language = () => current.value;
export const setLanguage = code => {
  current.value = code || 'en';
};
// The same language for Intl: dates, times and money.
export const formatLanguage = () => intlLanguage(current.value);

const lookup = (messages, key) =>
  key.split('.').reduce((node, part) => (node ? node[part] : undefined), messages);

// A text that depends on a number is written as its forms: one, few, many
// (and other, for fractions). The number is the parameter "count", or the one
// the forms name with "by".
const isForms = node => Boolean(node) && typeof node === 'object' && typeof node.one === 'string' && typeof node.many === 'string';
const chosenForm = (forms, params) => forms[category(current.value, params[forms.by || 'count'])] ?? forms.many;

const textOf = (messages, key, params) => {
  const found = lookup(messages, key);
  return isForms(found) ? chosenForm(found, params) : found;
};

export const t = (key, params = {}) => {
  const chosen = dictionaries[current.value];
  let text = chosen && chosen !== en ? textOf(chosen, key, params) : undefined;
  if (typeof text !== 'string') text = lookup(en, key);
  if (typeof text !== 'string') return key;
  return text.replace(/\{(\w+)\}/g, (_, name) =>
    params[name] === undefined || params[name] === null ? '' : String(params[name])
  );
};

export const has = key => typeof lookup(en, key) === 'string';
