// Every word an agent reads in the overlay's interface comes from its locale
// file. This check fails when a template of the overlay holds text of its own:
// a text node with letters, or a literal placeholder, title, label or
// aria-label. It also fails when a key used with t('...') is not in the file.
//
// The screens that stand where Chatwoot's own stood (patches/overlay-screens.txt)
// keep Chatwoot's words, so every translation Chatwoot ships still applies.
// Their keys are looked up in Chatwoot's English dictionary as well:
//   node scripts/check-ui-strings.mjs --chatwoot build/chatwoot
// Without the assembled tree those keys are left to that run.
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', 'shims', 'app', 'javascript', 'dashboard', 'inclamo');
const locale = JSON.parse(readFileSync(join(root, 'locale', 'en.json'), 'utf8'));
const problems = [];

const repository = join(dirname(fileURLToPath(import.meta.url)), '..');
const record = join(repository, 'patches', 'overlay-screens.txt');
const standIns = existsSync(record)
  ? readFileSync(record, 'utf8')
      .split('\n')
      .filter(line => line.trim() && !line.startsWith('#'))
      .map(line => join(repository, line.trim().split(/\s+/)[2]))
  : [];
const flag = process.argv.indexOf('--chatwoot');
const chatwootRoot = flag > -1 ? process.argv[flag + 1] : null;
const chatwootDictionary = dir => {
  const folder = join(dir, 'app', 'javascript', 'dashboard', 'i18n', 'locale', 'en');
  return Object.assign({}, ...readdirSync(folder).filter(name => name.endsWith('.json')).map(name => JSON.parse(readFileSync(join(folder, name), 'utf8'))));
};
const chatwoot = chatwootRoot ? chatwootDictionary(chatwootRoot) : null;
const inChatwoot = key => typeof key.split('.').reduce((node, part) => (node ? node[part] : undefined), chatwoot) === 'string';
let chatwootKeys = 0;

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
    if (known(match[1])) continue;
    if (!standIns.includes(file)) problems.push(`${shown}: unknown key ${match[1]}`);
    else if (chatwoot && !inChatwoot(match[1])) problems.push(`${shown}: key ${match[1]} is neither the overlay's nor Chatwoot's`);
    else chatwootKeys += 1;
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
if (chatwootKeys > 0) console.log(`${chatwootKeys} keys of the screens that stand in for Chatwoot's ${chatwoot ? "are in Chatwoot's dictionary" : 'were not looked up: no --chatwoot tree given'}`);
