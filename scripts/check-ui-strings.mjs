// Every word an agent reads in the overlay's interface comes from its locale
// file. This check fails when a template of the overlay holds text of its own:
// a text node with letters, or a literal placeholder, title, label or
// aria-label. It also fails when a key used with t('...') is not in the file.
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', 'shims', 'app', 'javascript', 'dashboard', 'inclamo');
const locale = JSON.parse(readFileSync(join(root, 'locale', 'en.json'), 'utf8'));
const problems = [];

const files = dir =>
  readdirSync(dir).flatMap(name => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) return name === 'specs' ? [] : files(path);
    return /\.(vue|js)$/.test(name) ? [path] : [];
  });
const known = key => typeof key.split('.').reduce((node, part) => (node ? node[part] : undefined), locale) === 'string';
const prefixKnown = prefix => typeof prefix.split('.').filter(Boolean).reduce((node, part) => (node ? node[part] : undefined), locale) === 'object';

for (const file of files(root)) {
  const source = readFileSync(file, 'utf8');
  const shown = relative(join(root, '..', '..', '..', '..', '..'), file);

  for (const match of source.matchAll(/\bt\(\s*'([A-Za-z0-9_.]+)'/g)) {
    if (!known(match[1])) problems.push(`${shown}: unknown key ${match[1]}`);
  }
  for (const match of source.matchAll(/\bt\(\s*`([A-Za-z0-9_.]+)\.\$\{/g)) {
    if (!prefixKnown(match[1])) problems.push(`${shown}: unknown key group ${match[1]}`);
  }

  const template = source.match(/<template>([\s\S]*)<\/template>/)?.[1];
  if (!template) continue;
  const withoutBindings = template.replace(/\{\{[\s\S]*?\}\}/g, '');
  for (const match of withoutBindings.matchAll(/>([^<>]+)</g)) {
    const text = match[1].replace(/&[a-z]+;/g, '').trim();
    if (/[A-Za-z]{2,}/.test(text)) problems.push(`${shown}: text in the template: "${text.slice(0, 50)}"`);
  }
  for (const match of template.matchAll(/\s(placeholder|title|label|aria-label|confirm-button-label|cancel-button-label)="([^"]*[A-Za-z][^"]*)"/g)) {
    problems.push(`${shown}: literal ${match[1]}="${match[2]}"`);
  }
}

if (problems.length > 0) {
  console.error(problems.join('\n'));
  process.exit(1);
}
console.log('every interface string of the overlay comes from its locale file');
