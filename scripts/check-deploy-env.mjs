// deploy/env.template lists every variable a production instance is
// configured with. This check keeps it so, and keeps the stack pinned:
//
// - every variable read in deploy/ is in the template. Read means: named as
//   ${NAME} in deploy/docker-compose.yaml, handed to env_value, input,
//   input_secret or set_env_value in a script, or listed in a `for ... in`
//   or `case` list or in SECRET_NAMES;
// - every variable of the template has a comment above it, the secrets are
//   left empty, and the fixed settings have their values;
// - every image in deploy/ is pinned to an exact tag and a digest.
//
//   node scripts/check-deploy-env.mjs [deploy directory]
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const deploy = resolve(process.argv[2] || join(root, 'deploy'));
const problems = [];

// Not settings of an instance: the restore test names its throwaway network
// itself, the install hands the test recipient to its own mailer run, and the
// inputs of the install's test mode are described in deploy/install.sh.
const internal = name => name === 'HELPDESK_NETWORK' || name === 'INSTALL_MAIL_TO' || name.startsWith('INSTALL_TEST_');

const secrets = [
  'SECRET_KEY_BASE', 'ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY', 'ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY',
  'ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT', 'POSTGRES_PASSWORD', 'REDIS_PASSWORD', 'SMTP_PASSWORD',
  'STORAGE_SECRET_ACCESS_KEY', 'BACKUP_S3_SECRET_ACCESS_KEY', 'ALERT_WEBHOOK_URL',
];
const fixed = { FORCE_SSL: 'true', ENABLE_ACCOUNT_SIGNUP: 'false', DISABLE_TELEMETRY: 'true', ENABLE_PUSH_RELAY_SERVER: 'false' };

const walk = dir => readdirSync(dir).flatMap(name => {
  const path = join(dir, name);
  return statSync(path).isDirectory() ? walk(path) : [path];
});
const files = walk(deploy);
const show = path => relative(deploy, path);

// --- the template -----------------------------------------------------------

const variable = /^(# )?([A-Z][A-Z0-9_]*)=(.*)$/;
const template = new Map();
const lines = readFileSync(join(deploy, 'env.template'), 'utf8').split('\n');
lines.forEach((line, index) => {
  const match = line.match(variable);
  if (!match) return;
  const [, optional, name, value] = match;
  if (template.has(name)) problems.push(`env.template: ${name} is listed twice`);
  template.set(name, { optional: Boolean(optional), value });
  const above = lines[index - 1] || '';
  if (!above.startsWith('#') || variable.test(above)) problems.push(`env.template: ${name} has no comment above it`);
});
for (const name of secrets) {
  if (!template.has(name)) problems.push(`env.template: the secret ${name} is not listed`);
  else if (template.get(name).value !== '') problems.push(`env.template: the secret ${name} must be left empty`);
}
for (const [name, value] of Object.entries(fixed)) {
  const entry = template.get(name);
  if (!entry || entry.optional || entry.value !== value) problems.push(`env.template: the fixed setting ${name}=${value} is missing or changed`);
}

// --- what deploy/ reads -----------------------------------------------------

const read = new Map();
const note = (name, path) => {
  if (internal(name)) return;
  if (!read.has(name)) read.set(name, new Set());
  read.get(name).add(show(path));
};
const compose = join(deploy, 'docker-compose.yaml');
for (const match of readFileSync(compose, 'utf8').matchAll(/\$\{([A-Z][A-Z0-9_]*)/g)) note(match[1], compose);

const name = '[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+';
for (const path of files.filter(file => file.endsWith('.sh'))) {
  const source = readFileSync(path, 'utf8').split('\n').filter(line => !/^\s*#/.test(line)).join('\n');
  for (const match of source.matchAll(new RegExp(`\\b(?:env_value|input|input_secret|set_env_value)\\s+"?(${name})\\b`, 'g'))) note(match[1], path);
  const lists = [
    ...source.matchAll(/\bfor\s+\w+\s+in\s+([^;\n]+)/g),
    ...source.matchAll(/^\s*((?:[A-Z][A-Z0-9_]*\s*\|\s*)*[A-Z][A-Z0-9_]*)\)/gm),
    ...source.matchAll(/\bSECRET_NAMES='([^']*)'/g),
  ];
  for (const list of lists) {
    for (const word of list[1].split(/[\s|]+/)) if (new RegExp(`^${name}$`).test(word)) note(word, path);
  }
}
for (const [variableName, where] of [...read].sort()) {
  if (!template.has(variableName)) problems.push(`${variableName} is read in ${[...where].join(', ')} and is not in env.template`);
}

// --- every image is pinned --------------------------------------------------

const pinned = /^[a-z0-9.\/-]+:v?\d+\.\d+[A-Za-z0-9.-]*@sha256:[0-9a-f]{64}$/;
for (const path of files.filter(file => /\.(?:ya?ml|sh)$/.test(file))) {
  const source = readFileSync(path, 'utf8');
  const images = [
    ...[...source.matchAll(/^\s*image:\s*(\S+)/gm)].map(match => match[1]),
    ...[...source.matchAll(/^\s*(?:readonly\s+)?[A-Z_]*IMAGE=(\S+)/gm)].map(match => match[1]),
  ];
  for (const image of images) {
    // Named by the instance's environment file (the helpdesk image, which the
    // install pins by digest) or by the caller of the test mode.
    if (image.startsWith('${') || image.startsWith('$(')) continue;
    if (!pinned.test(image)) problems.push(`${show(path)}: the image ${image} is not pinned to an exact tag and a digest`);
  }
}

if (problems.length > 0) {
  console.error(problems.join('\n'));
  process.exit(1);
}
console.log(`${read.size} variables read in deploy/ are in env.template (${template.size} listed); every image is pinned`);
