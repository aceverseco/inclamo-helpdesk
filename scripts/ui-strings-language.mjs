// Compares the overlay's texts in another language with the English ones,
// which are the wording of record. Returns what is wrong, one line each:
// a text that is missing or has no English counterpart, a different set of
// {placeholders}, a counted text without its forms, a word the language's
// glossary rules out, a text left in English.
//
// A text that depends on a number is written as its forms instead of a string:
//   { "one": "{count} розмова", "few": "{count} розмови", "many": "{count} розмов" }
// with "other" for fractions and "by" naming the number when it is not "count".

const FORM_FIELDS = ['one', 'few', 'many', 'other'];
const isForms = node => Boolean(node) && typeof node === 'object' && !Array.isArray(node) && FORM_FIELDS.some(field => typeof node[field] === 'string');

// Every text of a dictionary by its dotted key. In the other language a set
// of forms stands where the English dictionary has one text, so the English
// one tells which objects are forms and which are groups of texts.
const texts = (node, prefix = '', found = new Map(), isText = () => false) => {
  for (const [name, value] of Object.entries(node)) {
    const key = prefix ? `${prefix}.${name}` : name;
    if (value && typeof value === 'object' && !Array.isArray(value) && !isText(key)) texts(value, key, found, isText);
    else found.set(key, value);
  }
  return found;
};

const placeholders = text => [...new Set([...text.matchAll(/\{(\w+)\}/g)].map(match => match[1]))].sort();
const same = (left, right) => left.length === right.length && left.every((item, index) => item === right[index]);

export const compareLanguage = (english, other, { ruledOut = {}, sameAsEnglish = [] } = {}) => {
  const problems = [];
  const source = texts(english);
  const translated = texts(other, '', new Map(), key => source.has(key));

  for (const key of translated.keys()) {
    if (!source.has(key)) problems.push(`${key}: no such English text`);
  }

  for (const [key, original] of source) {
    if (!translated.has(key)) {
      problems.push(`${key}: missing`);
      continue;
    }
    const value = translated.get(key);
    const expected = placeholders(original);
    let wordings;

    if (typeof value === 'string') {
      wordings = { text: value };
    } else if (isForms(value)) {
      const lacking = ['one', 'few', 'many'].filter(field => typeof value[field] !== 'string');
      if (lacking.length > 0) problems.push(`${key}: the forms lack ${lacking.join(', ')}`);
      const unknown = Object.keys(value).filter(field => !FORM_FIELDS.includes(field) && field !== 'by');
      if (unknown.length > 0) problems.push(`${key}: unknown field of the forms: ${unknown.join(', ')}`);
      const number = value.by || 'count';
      if (!expected.includes(number)) problems.push(`${key}: the forms follow {${number}}, which the English text does not have`);
      wordings = Object.fromEntries(FORM_FIELDS.filter(field => typeof value[field] === 'string').map(field => [field, value[field]]));
    } else {
      problems.push(`${key}: neither a text nor the forms of one`);
      continue;
    }

    for (const [form, text] of Object.entries(wordings)) {
      const where = form === 'text' ? key : `${key} (${form})`;
      if (text.trim() === '' && original.trim() !== '') problems.push(`${where}: empty`);
      const found = placeholders(text);
      if (!same(found, expected)) problems.push(`${where}: placeholders {${found.join('}, {')}} differ from the English {${expected.join('}, {')}}`);
      const lower = text.toLowerCase();
      for (const [stem, instead] of Object.entries(ruledOut)) {
        if (lower.includes(stem.toLowerCase())) problems.push(`${where}: "${stem}" is ruled out by the glossary: ${instead}`);
      }
      if (text === original && /[A-Za-z]{2,}/.test(text.replace(/\{\w+\}/g, '')) && !sameAsEnglish.includes(key)) {
        problems.push(`${where}: left in English ("${text.slice(0, 50)}")`);
      }
    }
  }

  for (const key of sameAsEnglish) {
    if (!source.has(key)) problems.push(`${key}: allowed to stay in English, but there is no such English text`);
  }
  return problems;
};
