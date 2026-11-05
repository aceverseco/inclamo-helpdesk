// The recorded store answers in custom/spec/fixtures/shopify come from a
// development store that holds only invented people. This check keeps it so:
// every email is @example.com, every phone is in the fictional +1 500 555
// range, and every person is called "... Example".
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = join(dirname(fileURLToPath(import.meta.url)), '..', 'custom', 'spec', 'fixtures', 'shopify');
const problems = [];

function walk(value, path, file) {
  if (Array.isArray(value)) return value.forEach((item, index) => walk(item, `${path}[${index}]`, file));
  if (value && typeof value === 'object') return Object.entries(value).forEach(([key, item]) => walk(item, `${path}.${key}`, file));
  if (typeof value !== 'string') return;
  const key = path.split('.').pop().replace(/\[\d+\]$/, '');
  const fail = why => problems.push(`${file} ${path}: ${why} (${value.slice(0, 40)})`);
  for (const email of value.match(/[\w.+-]+@[\w-]+(\.[\w-]+)+/g) || []) {
    if (!email.toLowerCase().endsWith('@example.com')) fail('an email outside example.com');
  }
  if (/phone/i.test(key) && !/^\+1500555\d{4}$/.test(value)) fail('a phone outside the fictional range');
  if (['displayName', 'firstName', 'lastName'].includes(key) && !/Example$/.test(value)) fail('a person not named "... Example"');
  const parent = path.split('.').slice(-2, -1)[0] || '';
  if (key === 'name' && /^(shippingAddress|billingAddress)$/.test(parent) && !/Example$/.test(value)) fail('a person not named "... Example"');
  if (/myshopify\.com/.test(value)) fail('a store domain');
}

const files = readdirSync(dir).filter(file => file.endsWith('.json')).sort();
for (const file of files) walk(JSON.parse(readFileSync(join(dir, file), 'utf8')), '$', file);
if (problems.length > 0) {
  console.error(problems.join('\n'));
  process.exit(1);
}
console.log(`${files.length} fixtures hold no real personal data`);
