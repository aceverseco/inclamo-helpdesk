// The overlay's own interface strings. Chatwoot's locale index is a fixed list
// of files, so ours live here; one language for now.
import en from './locale/en.json';

const lookup = (messages, key) =>
  key.split('.').reduce((node, part) => (node ? node[part] : undefined), messages);

export const t = (key, params = {}) => {
  const text = lookup(en, key);
  if (typeof text !== 'string') return key;
  return text.replace(/\{(\w+)\}/g, (_, name) =>
    params[name] === undefined || params[name] === null ? '' : String(params[name])
  );
};

export const has = key => typeof lookup(en, key) === 'string';
