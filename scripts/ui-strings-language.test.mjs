import { test } from 'node:test';
import assert from 'node:assert/strict';
import { compareLanguage } from './ui-strings-language.mjs';

const english = {
  ORDERS: { TITLE: 'Orders', EMPTY: 'No order with this number.', SCOPES: 'The connected app lacks access: {scopes}.' },
  QUEUE: { COUNT: '{count} conversations', OPEN: 'Open the conversation with {name}' },
  BRAND: { NAME: 'Inclamo' },
  WHY_NOT: { other: 'Another reason', few: 'Too few items' },
};
const ukrainian = () => ({
  ORDERS: { TITLE: 'Замовлення', EMPTY: 'Замовлення з таким номером немає.', SCOPES: 'Підключеному застосунку бракує доступу: {scopes}.' },
  QUEUE: {
    COUNT: { one: '{count} розмова', few: '{count} розмови', many: '{count} розмов', other: '{count} розмови' },
    OPEN: 'Відкрити розмову з {name}',
  },
  BRAND: { NAME: 'Inclamo' },
  WHY_NOT: { other: 'Інша причина', few: 'Замало позицій' },
});
const rules = { ruledOut: { бесід: 'a conversation is «розмова»', діалог: 'a conversation is «розмова»' }, sameAsEnglish: ['BRAND.NAME'] };

test('a complete translation has nothing wrong', () => {
  assert.deepEqual(compareLanguage(english, ukrainian(), rules), []);
});

test('a missing text is named', () => {
  const other = ukrainian();
  delete other.ORDERS.EMPTY;

  assert.deepEqual(compareLanguage(english, other, rules), ['ORDERS.EMPTY: missing']);
});

test('a text without an English counterpart is named', () => {
  const other = ukrainian();
  other.ORDERS.OLD = 'Старе';

  assert.deepEqual(compareLanguage(english, other, rules), ['ORDERS.OLD: no such English text']);
});

test('a lost or invented placeholder is named', () => {
  const other = ukrainian();
  other.ORDERS.SCOPES = 'Підключеному застосунку бракує доступу.';
  other.QUEUE.OPEN = 'Відкрити розмову з {name} у {inbox}';

  assert.deepEqual(compareLanguage(english, other, rules), [
    'ORDERS.SCOPES: placeholders {} differ from the English {scopes}',
    'QUEUE.OPEN: placeholders {inbox}, {name} differ from the English {name}',
  ]);
});

test('a placeholder lost in one form is named with the form', () => {
  const other = ukrainian();
  other.QUEUE.COUNT.one = 'одна розмова';

  assert.deepEqual(compareLanguage(english, other, rules), ['QUEUE.COUNT (one): placeholders {} differ from the English {count}']);
});

test('counted forms without one of the three are named', () => {
  const other = ukrainian();
  delete other.QUEUE.COUNT.few;

  assert.deepEqual(compareLanguage(english, other, rules), ['QUEUE.COUNT: the forms lack few']);
});

test('forms that follow a number the English text does not have are named', () => {
  const other = ukrainian();
  other.QUEUE.COUNT.by = 'total';

  assert.deepEqual(compareLanguage(english, other, rules), ['QUEUE.COUNT: the forms follow {total}, which the English text does not have']);
});

test('a word the glossary rules out is named, whatever its case', () => {
  const other = ukrainian();
  other.QUEUE.OPEN = 'Відкрити Діалог з {name}';
  other.QUEUE.COUNT.many = '{count} бесід';

  assert.deepEqual(compareLanguage(english, other, rules), [
    'QUEUE.COUNT (many): "бесід" is ruled out by the glossary: a conversation is «розмова»',
    'QUEUE.OPEN: "діалог" is ruled out by the glossary: a conversation is «розмова»',
  ]);
});

test('a text left in English is named unless it is allowed to stay', () => {
  const other = ukrainian();
  other.ORDERS.TITLE = 'Orders';

  assert.deepEqual(compareLanguage(english, other, rules), ['ORDERS.TITLE: left in English ("Orders")']);
});

test('an empty text and a group in place of a text are named', () => {
  const other = ukrainian();
  other.ORDERS.TITLE = ' ';
  other.ORDERS.EMPTY = ['Немає'];

  assert.deepEqual(compareLanguage(english, other, rules), ['ORDERS.TITLE: empty', 'ORDERS.EMPTY: neither a text nor the forms of one']);
});

test('an allowance for a text that does not exist is named', () => {
  assert.deepEqual(compareLanguage(english, ukrainian(), { ...rules, sameAsEnglish: ['BRAND.NAME', 'BRAND.GONE'] }), [
    'BRAND.GONE: allowed to stay in English, but there is no such English text',
  ]);
});

test('a group whose texts are named like forms is still a group', () => {
  const other = ukrainian();
  delete other.WHY_NOT.few;

  assert.deepEqual(compareLanguage(english, other, rules), ['WHY_NOT.few: missing']);
});
