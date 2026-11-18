// The install tests: one test per scenario of docs/behavior/instance-installation,
// in the order an operator meets them. They install a throwaway instance with
// deploy/install.sh in its test mode and drive it with the scripts of deploy/,
// run on the host itself, and with a browser. Started by e2e/install-run.sh,
// once for each place attachments can live (ACTIVE_STORAGE_SERVICE).
//
// The tests share one installation and follow one another: a failed test
// stops the ones after it.
import { test, expect } from '@playwright/test';
import { spawnSync } from 'node:child_process';
import { appendFileSync, existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

test.describe.configure({ mode: 'serial' });

const env = process.env;
const repo = env.INSTALL_REPO;
const domain = env.INSTALL_DOMAIN;
const storage = env.INSTALL_STORAGE;
const output = env.E2E_OUTPUT;
const image = env.INSTALL_IMAGE;
const httpPort = env.INSTALL_TEST_HTTP_PORT || '80';
const httpsPort = env.INSTALL_TEST_HTTPS_PORT || '443';
const mailpit = `http://127.0.0.1:${env.INSTALL_TEST_MAILPIT_PORT || '8025'}`;
const receiver = `http://127.0.0.1:${env.INSTALL_TEST_ALARM_PORT || '9099'}`;
const s3Port = env.INSTALL_TEST_S3_PORT || '9000';
const project = env.INSTALL_TEST_PROJECT || 'inclamo-helpdesk';
// The instance's address as a browser on this machine reaches it: the domain,
// and the port the web server publishes when it is not 443.
const origin = `https://${domain}${httpsPort === '443' ? '' : `:${httpsPort}`}`;
const here = url => url.replace(`https://${domain}/`, `${origin}/`);
const sender = 'helpdesk@install.test';
const backupBucket = 'helpdesk-backups';
const generated = ['SECRET_KEY_BASE', 'ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY', 'ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY',
  'ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT', 'POSTGRES_PASSWORD', 'REDIS_PASSWORD'];
const minutes = count => count * 60_000;
const sleep = milliseconds => new Promise(resolve => { setTimeout(resolve, milliseconds); });

// --- the host -----------------------------------------------------------------

const quote = value => `'${String(value).replace(/'/g, `'\\''`)}'`;
const deploy = name => quote(join(repo, 'deploy', name));
const call = quote(join(repo, 'e2e', 'install', 'call.sh'));
const transcript = join(output, 'transcript.log');

const hostEnv = {
  PATH: env.INSTALL_HOST_PATH,
  HOME: '/root',
  INSTALL_TEST_ROOT: env.INSTALL_TEST_ROOT,
  INSTALL_TEST_PROJECT: env.INSTALL_TEST_PROJECT,
  INSTALL_TEST_HTTP_PORT: env.INSTALL_TEST_HTTP_PORT,
  INSTALL_TEST_HTTPS_PORT: env.INSTALL_TEST_HTTPS_PORT,
  INSTALL_TEST_MAILPIT_PORT: env.INSTALL_TEST_MAILPIT_PORT,
  INSTALL_TEST_ALARM_PORT: env.INSTALL_TEST_ALARM_PORT,
  INSTALL_TEST_S3_PORT: env.INSTALL_TEST_S3_PORT,
  INSTALL_TEST_S3_ACCESS_KEY: env.INSTALL_S3_ACCESS_KEY,
  INSTALL_TEST_S3_SECRET_KEY: env.INSTALL_S3_SECRET_KEY,
};

// Runs a command on the host as root, as an operator's shell would: the tests
// themselves run in a container that shares the host's processes. What the
// command wrote is kept in the transcript, which the test "Secrets stay out
// of the output" reads; `record: false` is for a command that reads a secret
// on purpose.
function host(command, { env: extra = {}, input, record = true, timeout = minutes(30) } = {}) {
  const assignments = Object.entries({ ...hostEnv, ...extra })
    .filter(([, value]) => value !== undefined && value !== null && value !== '')
    .map(([name, value]) => `${name}=${value}`);
  const result = spawnSync(
    'nsenter', ['--target', '1', '--mount', '--uts', '--ipc', '--net', '--pid', '--', 'env', '-i', ...assignments, 'bash', '-c', command],
    { encoding: 'utf8', input, timeout, maxBuffer: 256 * 1024 * 1024 }
  );
  if (result.error) throw result.error;
  const text = `${result.stdout}${result.stderr}`;
  if (record) appendFileSync(transcript, `$ ${command}\n${text}\n`);
  return { status: result.status, output: text, stdout: result.stdout.trim() };
}

// A command that must succeed.
function run(command, options) {
  const result = host(command, options);
  expect(result.status, `${command}\n${options?.record === false ? '' : result.output}`).toBe(0);
  return result.stdout;
}

// A script of deploy/, with its output shown in the run's log as it is.
function script(command, options) {
  const result = host(command, options);
  console.log(`$ ${command}\n${result.output}`);
  return result;
}

const places = () => JSON.parse(run(`. ${deploy('lib.sh')} && printf '{"envFile":"%s","stateDir":"%s","workDir":"%s"}' "$ENV_FILE" "$STATE_DIR" "$WORK_DIR"`));
const envValue = name => run(`${call} env_value ${name}`);
const containerOf = service => run(`${call} compose ps --all --quiet ${service}`);
const inspect = ids => JSON.parse(run(`docker inspect ${ids.split(/\s+/).join(' ')}`, { record: false }));
const stack = () => inspect(run(`${call} compose ps --all --quiet`));
// The helpdesk and its workers run exactly the image the configuration pins.
function expectRuns(pinned) {
  const id = run(`docker image inspect --format '{{.Id}}' ${quote(pinned)}`);
  const containers = stack().filter(entry => ['rails', 'sidekiq'].includes(entry.Config.Labels['com.docker.compose.service']));
  expect(containers).toHaveLength(2);
  for (const container of containers) expect(container.Image, `${container.Name} runs ${pinned}`).toBe(id);
}
const serviceOf = container => container.Config.Labels['com.docker.compose.service'];
const psql = sql => run(`${call} compose exec -T postgres psql --no-align --tuples-only --username=postgres --dbname=chatwoot_production --command ${quote(sql)}`);

// Nothing of an instance is on the machine: no environment file, no container
// and no volume of the stack.
function expectEmptyInstallation() {
  expect(host(`test -e ${quote(places().envFile)}`).status, 'no environment file').not.toBe(0);
  expect(run(`docker ps --all --quiet --filter label=com.docker.compose.project=${project}`), 'no container of the stack').toBe('');
  expect(run(`docker volume ls --quiet --filter label=com.docker.compose.project=${project}`), 'no volume of the stack').toBe('');
}

// --- what the operator gives the install --------------------------------------

const target = {
  BACKUP_S3_ENDPOINT: `http://s3:${s3Port}`,
  BACKUP_S3_REGION: 'us-east-1',
  BACKUP_S3_BUCKET: backupBucket,
  BACKUP_S3_ACCESS_KEY_ID: env.INSTALL_S3_ACCESS_KEY,
  BACKUP_S3_SECRET_ACCESS_KEY: env.INSTALL_S3_SECRET_KEY,
  BACKUP_S3_FORCE_PATH_STYLE: 'true',
};
const inputs = () => ({
  SMTP_ADDRESS: 'mailpit',
  SMTP_PORT: '1025',
  MAILER_SENDER_EMAIL: `Inclamo Helpdesk <${sender}>`,
  ...target,
  BACKUP_AGE_RECIPIENT: env.INSTALL_RECIPIENT,
  ALERT_WEBHOOK_URL: `${receiver}/`,
  ACTIVE_STORAGE_SERVICE: storage,
  ...(storage === 's3_compatible' ? {
    STORAGE_BUCKET_NAME: 'helpdesk-attachments',
    STORAGE_ACCESS_KEY_ID: env.INSTALL_S3_ACCESS_KEY,
    STORAGE_SECRET_ACCESS_KEY: env.INSTALL_S3_SECRET_KEY,
    STORAGE_REGION: 'us-east-1',
    STORAGE_ENDPOINT: `http://s3:${s3Port}`,
    STORAGE_FORCE_PATH_STYLE: 'true',
  } : {}),
  HELPDESK_IMAGE: image,
  // The domain "resolves" to the machine's "public address".
  INSTALL_TEST_DOMAIN_ADDRESS: '203.0.113.10',
  INSTALL_TEST_PUBLIC_ADDRESS: '203.0.113.10',
});
const install = (changes = {}) =>
  script(`${deploy('install.sh')} --domain ${domain} --mail-to operator@install.test --test`, { env: { ...inputs(), ...changes } });

// --- what the tests remember from one to the next -----------------------------

const stateFile = join(output, 'state.json');
const state = () => (existsSync(stateFile) ? JSON.parse(readFileSync(stateFile, 'utf8')) : {});
const remember = facts => writeFileSync(stateFile, JSON.stringify({ ...state(), ...facts }));

// --- the helpdesk over HTTPS --------------------------------------------------

let http;
test.beforeAll(async ({ playwright }) => {
  http = await playwright.request.newContext({ ignoreHTTPSErrors: true });
});
test.afterAll(async () => { await http.dispose(); });

const json = async response => {
  const text = await response.text();
  try { return JSON.parse(text); } catch { return text; }
};
async function health() {
  const response = await http.get(`${origin}/inclamo/health`, { failOnStatusCode: false, timeout: 30_000 }).catch(() => null);
  return response ? { status: response.status(), body: await json(response) } : { status: 0, body: null };
}
async function expectHealthy(timeout = minutes(5)) {
  await expect.poll(async () => (await health()).status, { timeout, intervals: [3_000] }).toBe(200);
}

async function signIn(user) {
  const response = await http.post(`${origin}/auth/sign_in`, { data: { email: user.email, password: user.password }, failOnStatusCode: false });
  if (!response.ok()) return { status: response.status() };
  const headers = Object.fromEntries(['access-token', 'client', 'uid', 'expiry', 'token-type'].map(name => [name, response.headers()[name]]));
  return { status: response.status(), headers, accountId: (await response.json()).data.account_id };
}
// The API as the administrator made at onboarding; one session for the run.
async function admin() {
  let { session } = state();
  if (!session || !(await http.get(`${origin}/api/v1/profile`, { headers: session.headers, failOnStatusCode: false })).ok()) {
    session = await signIn(state().admin);
    expect(session.status, 'the administrator signs in').toBe(200);
    remember({ session });
  }
  const base = `${origin}/api/v1/accounts/${session.accountId}`;
  const send = async (method, path, options = {}) => {
    const response = await http[method](`${base}${path}`, { headers: session.headers, failOnStatusCode: false, ...options });
    return { status: response.status(), body: await json(response) };
  };
  return {
    get: path => send('get', path),
    post: (path, data) => send('post', path, { data }),
    upload: (path, multipart) => send('post', path, { multipart }),
  };
}

// Follows a link of the helpdesk to its bytes, the way a browser on this
// machine would.
async function download(url) {
  let next = here(url);
  for (let hop = 0; hop < 6; hop += 1) {
    const response = await http.get(next, { maxRedirects: 0, failOnStatusCode: false });
    if (response.status() >= 300 && response.status() < 400) {
      next = here(new URL(response.headers().location, next).href);
      continue;
    }
    return { status: response.status(), bytes: await response.body() };
  }
  throw new Error(`too many redirects from ${url}`);
}

// --- the first administrator, a conversation with a photo, the store ----------

// A 1x1 PNG.
const photo = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==', 'base64');

async function completeOnboarding(page) {
  const user = { name: 'Install Operator', company: 'Install Test Store', email: 'owner@install.test', password: `Aa1!${Math.random().toString(16).slice(2, 14)}Zz` };
  await page.locator('input[name="user[name]"]').fill(user.name);
  await page.locator('input[name="user[company]"]').fill(user.company);
  await page.locator('input[name="user[email]"]').fill(user.email);
  await page.locator('input[name="user[password]"]').fill(user.password);
  // Left ticked, as the page offers it: Chatwoot would register the company,
  // the name and the email with its hub.
  await expect(page.locator('input[name="subscribe_to_updates"]')).toBeChecked();
  await page.locator('form[action="/installation/onboarding"] [type="submit"]').click();
  await expect(page).toHaveURL(/\/app\/login/, { timeout: 60_000 });
  remember({ admin: user, session: null });
}

async function conversationWithPhoto() {
  const api = await admin();
  const inbox = await api.post('/inboxes', { name: `Install test ${Date.now()}`, channel: { type: 'api', webhook_url: '' } });
  expect(inbox.status, JSON.stringify(inbox.body)).toBe(200);
  const contact = await api.post('/contacts', { name: 'Install Customer', email: `customer-${Date.now()}@install.test`, inbox_id: inbox.body.id });
  expect(contact.status, JSON.stringify(contact.body)).toBe(200);
  const { contact: person } = contact.body.payload;
  const conversation = await api.post('/conversations', { inbox_id: inbox.body.id, contact_id: person.id, source_id: person.contact_inboxes[0].source_id });
  expect(conversation.status, JSON.stringify(conversation.body)).toBe(200);
  const message = await api.upload(`/conversations/${conversation.body.id}/messages`, {
    content: 'Here is a photo of the parcel',
    message_type: 'incoming',
    'attachments[]': { name: 'parcel.png', mimeType: 'image/png', buffer: photo },
  });
  expect(message.status, JSON.stringify(message.body)).toBe(200);
  expect(message.body.attachments).toHaveLength(1);
  remember({ conversation: conversation.body.id, message: message.body.id });
}

// The photo of the conversation, read through the helpdesk as an agent's
// browser reads it.
async function expectPhotoOpens() {
  const api = await admin();
  const messages = await api.get(`/conversations/${state().conversation}/messages`);
  expect(messages.status).toBe(200);
  const message = messages.body.payload.find(entry => entry.id === state().message);
  expect(message, 'the message with the photo is in the conversation').toBeTruthy();
  expect(message.attachments).toHaveLength(1);
  const file = await download(message.attachments[0].data_url);
  expect(file.status).toBe(200);
  expect(file.bytes.equals(photo), 'the photo comes back byte for byte').toBe(true);
}

const store = () => ({ shop_domain: env.SHOPIFY_BENCH_DOMAIN, client_id: env.SHOPIFY_BENCH_CLIENT_ID, client_secret: env.SHOPIFY_BENCH_CLIENT_SECRET });
async function connectStore() {
  const connected = await (await admin()).post('/inclamo/shopify/connection', store());
  expect([200, 201], JSON.stringify(connected.body)).toContain(connected.status);
}
// The stored credentials decrypt and the store answers: the connection checks
// itself against the store, and the order panel of the conversation reads it.
async function expectStoreReads() {
  const api = await admin();
  const checked = await api.post('/inclamo/shopify/connection/recheck');
  expect(checked.status, JSON.stringify(checked.body)).toBe(200);
  expect(checked.body.status).toBe('working');
  const panel = await api.get(`/inclamo/shopify/conversations/${state().conversation}/panel`);
  expect(panel.status, JSON.stringify(panel.body)).toBe(200);
}

// --- the alarm, the mail, the backups -----------------------------------------

const alarms = async () => (await (await http.get(`${receiver}/requests`)).json()).map(entry => entry.body.text);
const forgetAlarms = () => http.delete(`${receiver}/requests`);
const hubConnections = async () => (await (await http.get(`${receiver}/hub`)).json()).connections;

async function mailTo(address) {
  let found = null;
  await expect.poll(async () => {
    const list = await (await http.get(`${mailpit}/api/v1/search`, { params: { query: `to:${address}` } })).json();
    [found] = list.messages || [];
    return Boolean(found);
  }, { message: `a message to ${address} arrives`, timeout: minutes(2), intervals: [2_000] }).toBe(true);
  return (await http.get(`${mailpit}/api/v1/message/${found.ID}`)).json();
}

const backups = () => run(`${call} list_backups`).split('\n').filter(Boolean);
const statusFile = () => join(places().stateDir, 'backup-status.json');
const readStatus = () => JSON.parse(run(`cat ${quote(statusFile())}`));
// Replaced by a rename, as the scripts do: the directory is mounted into the
// helpdesk, not the file.
const writeStatus = status =>
  run(`umask 022; printf '%s' "$CONTENT" > ${quote(`${statusFile()}.test`)} && mv -f ${quote(`${statusFile()}.test`)} ${quote(statusFile())}`, { env: { CONTENT: JSON.stringify(status) } });
// The backup target refuses every upload while `during` runs: the instance
// holds another secret key than the target knows.
async function withTargetRefusing(during) {
  run(`${call} set_env_value BACKUP_S3_SECRET_ACCESS_KEY not-the-key-of-the-target`);
  try {
    return await during();
  } finally {
    run(`${call} set_env_value BACKUP_S3_SECRET_ACCESS_KEY "$KEY"`, { env: { KEY: env.INSTALL_S3_SECRET_KEY } });
  }
}

// The retention of deploy/lib.sh, written again here: of the names, newest
// first, the newest of each of the last 14 days and of each of the last 8
// weeks (Monday to Sunday) that have a backup.
function retained(names) {
  const days = new Set();
  const weeks = new Set();
  return [...names].sort().reverse().filter(name => {
    const day = name.slice(0, 8);
    const week = Math.floor((Date.UTC(Number(name.slice(0, 4)), Number(name.slice(4, 6)) - 1, Number(name.slice(6, 8))) / 86_400_000 + 3) / 7);
    let keep = false;
    if (!days.has(day) && days.size < 14) { days.add(day); keep = true; }
    if (!weeks.has(week) && weeks.size < 8) { weeks.add(week); keep = true; }
    return keep;
  }).sort();
}

// --- secrets ------------------------------------------------------------------

// None of the secrets the install drew is in what the scripts wrote so far or
// in the logs of the containers.
function expectNoSecretAnywhere() {
  const secrets = generated.map(name => [name, host(`${call} env_value ${name}`, { record: false }).stdout]);
  for (const [name, secret] of secrets) expect(secret.length, `${name} is drawn`).toBeGreaterThan(20);
  const holds = (text, where) => {
    for (const [name, secret] of secrets) expect(text.includes(secret), `${where} holds no ${name}`).toBe(false);
  };
  holds(readFileSync(transcript, 'utf8'), 'the output of the scripts');
  const containers = stack();
  expect(containers).toHaveLength(5);
  for (const container of containers) {
    holds(host(`docker logs ${container.Id} 2>&1`, { record: false }).output, `the log of ${serviceOf(container)}`);
  }
}

// =============================================================================
// What the install refuses, on a machine with no instance
// =============================================================================

test('Domain points elsewhere', async () => {
  const attempt = install({ INSTALL_TEST_DOMAIN_ADDRESS: '203.0.113.99' });
  expect(attempt.status).not.toBe(0);
  expect(attempt.output).toContain(`the domain ${domain} resolves to 203.0.113.99`);
  expect(attempt.output).toContain('No certificate was requested');
  // The web server, which asks for the certificate, was never made.
  expectEmptyInstallation();
});

test('No mail settings', async () => {
  const attempt = install({ SMTP_ADDRESS: null });
  expect(attempt.status).not.toBe(0);
  expect(attempt.output).toContain('the mail settings are missing');
  expectEmptyInstallation();
});

test('Backup target not writable', async () => {
  test.setTimeout(minutes(10));
  const attempt = install({ BACKUP_S3_SECRET_ACCESS_KEY: 'not-the-key-of-the-target' });
  expect(attempt.status).not.toBe(0);
  expect(attempt.output).toContain('refused the test upload');
  expect(attempt.output).toContain(`http://s3:${s3Port}, bucket ${backupBucket}`);
  expect(attempt.output).toMatch(/Its answer: .*(403|Forbidden)/);
  expectEmptyInstallation();
});

test('Mail server refuses the credentials', async () => {
  test.setTimeout(minutes(20));
  const attempt = install({
    SMTP_USERNAME: 'helpdesk', SMTP_PASSWORD: 'not-the-password', SMTP_AUTHENTICATION: 'plain',
    INSTALL_TEST_SMTP_AUTH: 'helpdesk:the-password-of-the-mailbox', INSTALL_TEST_SMTP_ACCEPT_ANY: 'false',
  });
  expect(attempt.status).not.toBe(0);
  expect(attempt.output).toContain('the mail server mailpit refused the test message');
  expect(attempt.output).toMatch(/Its answer: .*(535|[Aa]uthenticat)/);
  expect(attempt.output).not.toContain('not-the-password');
  // The run removed what it had made, so the install can be run again.
  expectEmptyInstallation();
});

test('Restore without the key', async () => {
  for (const key of ['', ` --identity ${quote(join(output, 'no-such-key.txt'))}`]) {
    const attempt = script(`${deploy('restore.sh')}${key}`, { env: target });
    expect(attempt.status).not.toBe(0);
    expect(attempt.output).toContain('the restore key is needed');
    expect(attempt.output).toContain('Nothing was touched');
  }
  expectEmptyInstallation();
});

// =============================================================================
// The instance
// =============================================================================

test('Fresh install', async () => {
  test.setTimeout(minutes(30));
  const installed = install();
  expect(installed.status).toBe(0);
  expect(installed.output).toContain(`installed: https://${domain}`);

  // Over HTTPS at the domain, with a certificate of the web server's own
  // authority (the one thing the test mode changes here).
  const caddy = containerOf('caddy');
  const authority = join(output, 'authority.crt');
  run(`docker cp ${caddy}:/data/caddy/pki/authorities/local/root.crt ${quote(authority)}`);
  const answer = JSON.parse(run(`curl --silent --show-error --fail --cacert ${quote(authority)} --resolve ${domain}:${httpsPort}:127.0.0.1 ${origin}/api`));
  expect(answer.version).toBe(env.INSTALL_CHATWOOT_VERSION);
  const page = await health();
  expect(page.status, JSON.stringify(page.body)).toBe(200);
  expect(page.body.overlay_version).toBe(env.INSTALL_OVERLAY_VERSION);
  expect(page.body.chatwoot_version).toBe(env.INSTALL_CHATWOOT_VERSION);

  // The image the configuration pins, by tag and digest, pulled from the
  // registry, with no source mounted into it.
  const pinned = envValue('HELPDESK_IMAGE');
  expect(pinned.startsWith(`${image}@sha256:`), pinned).toBe(true);
  expect(pinned).toMatch(/@sha256:[0-9a-f]{64}$/);
  expectRuns(pinned);
  for (const container of stack().filter(entry => ['rails', 'sidekiq'].includes(serviceOf(entry)))) {
    for (const mount of container.Mounts) {
      if (mount.Type === 'volume') continue;
      expect(mount.Destination, 'the only directory of the host in the helpdesk is the backup status').toBe('/var/lib/inclamo-helpdesk');
      expect(mount.RW).toBe(false);
    }
  }
  // No floating tag anywhere in the stack.
  const images = run(`${call} compose config --images`).split('\n').filter(Boolean);
  expect(images.length).toBeGreaterThanOrEqual(4);
  for (const name of images) expect(name).toMatch(/:[^:@]*\d+\.\d+[^:@]*@sha256:[0-9a-f]{64}$/);

  // The environment file: outside the checkout, root only.
  const { envFile } = places();
  expect(envFile.startsWith(repo)).toBe(false);
  expect(run(`stat --format '%a %U' ${quote(envFile)}`)).toBe('600 root');

  // The test message left through the SMTP server, from the sender.
  const message = await mailTo('operator@install.test');
  expect(message.From.Address).toBe(sender);
});

test('Only the web server listens', async () => {
  const containers = stack();
  expect(containers.map(serviceOf).sort()).toEqual(['caddy', 'postgres', 'rails', 'redis', 'sidekiq']);
  for (const container of containers) {
    const published = Object.entries(container.HostConfig.PortBindings || {}).filter(([, bindings]) => bindings && bindings.length > 0);
    if (serviceOf(container) !== 'caddy') {
      expect(published, `${serviceOf(container)} publishes no port`).toEqual([]);
      continue;
    }
    expect(published.map(([port]) => port).sort()).toEqual(['443/tcp', '80/tcp']);
    const hostPorts = Object.fromEntries(published.map(([port, bindings]) => [port, bindings.map(binding => binding.HostPort)]));
    expect(hostPorts).toEqual({ '80/tcp': [httpPort], '443/tcp': [httpsPort] });
  }
  const plain = await http.get(`http://${domain}:${httpPort}/app/login`, { maxRedirects: 0, failOnStatusCode: false });
  expect([301, 302, 307, 308]).toContain(plain.status());
  expect(plain.headers().location).toBe(`https://${domain}/app/login`);
});

test('Container logs stay bounded', async () => {
  const containers = stack();
  expect(containers).toHaveLength(5);
  for (const container of containers) {
    const log = container.HostConfig.LogConfig;
    expect(log.Type, serviceOf(container)).toBe('json-file');
    expect(log.Config['max-size'], serviceOf(container)).toMatch(/^\d+[km]$/);
    expect(Number(log.Config['max-file']), serviceOf(container)).toBeGreaterThanOrEqual(1);
  }
});

test('First visit opens onboarding', async ({ page }) => {
  await page.goto(`${origin}/`);
  await expect(page).toHaveURL(/\/installation\/onboarding/);
  for (const field of ['name', 'company', 'email', 'password']) {
    await expect(page.locator(`input[name="user[${field}]"]`)).toBeVisible();
  }
  // The page does what it asks for: the first administrator and the account.
  await completeOnboarding(page);
  const session = await signIn(state().admin);
  expect(session.status).toBe(200);
  const profile = await (await http.get(`${origin}/api/v1/profile`, { headers: session.headers })).json();
  expect(profile.type).toBe('SuperAdmin');
  expect(profile.accounts.map(account => account.name)).toEqual(['Install Test Store']);
  remember({ session });
});

test('Onboarding happens once', async ({ page }) => {
  await page.goto(`${origin}/installation/onboarding`);
  await expect(page).toHaveURL(/\/app\/login/);
  await expect(page.locator('input[name="user[company]"]')).toHaveCount(0);
});

test('Sign-up is closed', async ({ page }) => {
  const stranger = { email: 'stranger@install.test', password: 'Aa1!stranger-Zz9' };
  const attempt = await http.post(`${origin}/api/v1/accounts`, {
    data: { account_name: 'Stranger Store', user_full_name: 'A Stranger', email: stranger.email, password: stranger.password },
    failOnStatusCode: false,
  });
  expect(attempt.status()).toBe(404);
  expect((await signIn(stranger)).status).toBe(401);
  expect(psql("SELECT count(*) FROM accounts")).toBe('1');
  // The sign-up page offers no form.
  await page.goto(`${origin}/app/auth/signup`);
  await expect(page).toHaveURL(/\/app\/login/);
});

test('Daily jobs and onboarding send nothing to the hub', async () => {
  test.setTimeout(minutes(10));
  // Inside the stack the hub's name leads to a listener that counts what
  // connects. Onboarding was completed with "subscribe to updates" ticked.
  expect(await hubConnections(), 'nothing called the hub during the install and onboarding').toBe(0);
  const jobs = host(`${call} compose exec -T rails bundle exec rails runner -`, {
    input: 'Internal::TriggerDailyScheduledItemsJob.perform_now\nInternal::CheckNewVersionsJob.perform_now\nputs "DAILY_JOBS_RAN"\n',
  });
  expect(jobs.output).toContain('DAILY_JOBS_RAN');
  // What the daily job handed to the workers has run by now.
  await sleep(30_000);
  expect(await hubConnections(), 'nothing called the hub from the daily jobs').toBe(0);
  // The listener does count: a connection made on purpose is seen.
  run(`${call} compose exec -T rails ruby -rsocket -e 'TCPSocket.new("hub.2.chatwoot.com", 443).close'`);
  await expect.poll(hubConnections).toBe(1);
  await http.delete(`${receiver}/hub`);
});

test('An invitation reaches the agent', async ({ page }) => {
  const address = `agent-${Date.now()}@install.test`;
  const invited = await (await admin()).post('/agents', { name: 'Install Agent', email: address, role: 'agent' });
  expect(invited.status, JSON.stringify(invited.body)).toBe(200);
  const message = await mailTo(address);
  expect(message.From.Address).toBe(sender);
  // The link the agent follows to choose a password leads to the instance.
  const links = (`${message.HTML} ${message.Text}`.match(/https?:\/\/[^\s"'<>)]+/g) || []).map(entry => entry.replace(/&amp;/g, '&'));
  const link = links.find(entry => /reset_password_token|confirmation_token/.test(entry));
  expect(link, `the invitation holds its link (${links.map(entry => entry.split('?')[0]).join(' ')})`).toBeTruthy();
  expect(new URL(link).origin).toBe(`https://${domain}`);
  await page.goto(here(link));
  await expect.poll(() => new URL(page.url()).hostname).toBe(domain);
  // The agent is asked to choose a password.
  await expect(page.locator('input[type="password"]').first()).toBeVisible({ timeout: 60_000 });
});

test('Attachment after the containers are recreated', async () => {
  test.setTimeout(minutes(15));
  await conversationWithPhoto();
  await expectPhotoOpens();
  const before = stack().map(container => container.Id).sort();
  run(`${call} compose up --detach --force-recreate`);
  await expectHealthy();
  const after = stack().map(container => container.Id).sort();
  expect(after).toHaveLength(5);
  expect(after.filter(id => before.includes(id)), 'every container is a new one').toEqual([]);
  await expectPhotoOpens();
});

test('Running the install again keeps the secrets', async () => {
  test.setTimeout(minutes(10));
  await connectStore();
  await expectStoreReads();
  const { envFile } = places();
  const before = run(`sha256sum < ${quote(envFile)}`);
  const again = install();
  expect(again.status).not.toBe(0);
  expect(again.output).toContain('this machine already has an instance');
  expect(run(`sha256sum < ${quote(envFile)}`)).toBe(before);
  await expectStoreReads();
  await expectHealthy(30_000);
});

// =============================================================================
// Health
// =============================================================================

test('Healthy instance', async () => {
  const status = readStatus();
  expect(Date.now() - Date.parse(status.last_backup_at)).toBeLessThan(26 * 3_600_000);
  expect(Date.now() - Date.parse(status.last_restore_test_at)).toBeLessThan(35 * 86_400_000);
  const page = await health();
  expect(page.status).toBe(200);
  // The names of the failing checks and the versions, nothing else.
  expect(page.body).toEqual({ status: 'ok', failing: [], overlay_version: env.INSTALL_OVERLAY_VERSION, chatwoot_version: env.INSTALL_CHATWOOT_VERSION });
});

test('Workers stopped', async () => {
  test.setTimeout(minutes(10));
  run(`${call} compose stop sidekiq`);
  try {
    // The workers' last beat is forgotten a minute after they stop.
    await expect.poll(async () => (await health()).status, { timeout: minutes(4), intervals: [5_000] }).toBe(503);
    expect((await health()).body.failing).toEqual(['workers']);
  } finally {
    run(`${call} compose start sidekiq`);
  }
  await expectHealthy();
});

test('Stale backup', async () => {
  const status = readStatus();
  const ago = hours => new Date(Date.now() - hours * 3_600_000).toISOString().replace(/\.\d+Z$/, 'Z');
  try {
    writeStatus({ ...status, last_backup_at: ago(27) });
    let page = await health();
    expect(page.status).toBe(503);
    expect(page.body.failing).toEqual(['backup']);
    writeStatus({ ...status, last_backup_at: ago(25) });
    expect((await health()).status).toBe(200);
    // The same for the restore test, after 35 days.
    writeStatus({ ...status, last_restore_test_at: ago(36 * 24) });
    page = await health();
    expect(page.status).toBe(503);
    expect(page.body.failing).toEqual(['restore_test']);
    writeStatus({ ...status, last_restore_test_at: ago(34 * 24) });
    expect((await health()).status).toBe(200);
  } finally {
    writeStatus(status);
  }
  expect((await health()).status).toBe(200);
});

// =============================================================================
// Backups
// =============================================================================

test('Nightly backup', async () => {
  test.setTimeout(minutes(15));
  // What the nightly timer runs.
  if (!env.INSTALL_TEST_ROOT) {
    expect(run('systemctl is-enabled inclamo-helpdesk-backup.timer inclamo-helpdesk-restore-test.timer')).toBe('enabled\nenabled');
    expect(run('systemctl cat inclamo-helpdesk-backup.service')).toContain(`ExecStart=${join(repo, 'deploy', 'backup.sh')}`);
  }
  const known = backups();
  const backup = script(deploy('backup.sh'));
  expect(backup.status).toBe(0);
  const [name] = backups().filter(entry => !known.includes(entry));
  expect(name, 'the target holds a new backup').toBeTruthy();
  expect(readStatus().last_backup.name).toBe(name);

  const { workDir, envFile } = places();
  const copy = join(workDir, 'backup-check');
  run(`rm -rf ${quote(copy)} && ${call} s3 copy "$(${call} remote backups/${name})" /work/backup-check`);
  const files = run(`ls ${quote(copy)}`).split('\n').sort();
  expect(files).toEqual(['database.dump.age', 'helpdesk.env.age', 'manifest.txt', ...(storage === 'local' ? ['storage.tar.age'] : [])].sort());
  for (const file of files.filter(entry => entry.endsWith('.age'))) {
    // Encrypted, and closed to any key but the restore key.
    expect(run(`head -c 21 ${quote(join(copy, file))}`)).toBe('age-encryption.org/v1');
    expect(host(`age --decrypt --identity ${quote(env.INSTALL_OTHER_IDENTITY)} ${quote(join(copy, file))} > /dev/null`).status, `${file} does not open with another key`).not.toBe(0);
  }
  // With the restore key: a database dump, and the environment file as it is.
  expect(run(`age --decrypt --identity ${quote(env.INSTALL_IDENTITY)} ${quote(join(copy, 'database.dump.age'))} | head -c 5`)).toBe('PGDMP');
  run(`age --decrypt --identity ${quote(env.INSTALL_IDENTITY)} ${quote(join(copy, 'helpdesk.env.age'))} | cmp --silent - ${quote(envFile)}`, { record: false });
  if (storage === 'local') {
    expect(run(`age --decrypt --identity ${quote(env.INSTALL_IDENTITY)} ${quote(join(copy, 'storage.tar.age'))} | tar --list | wc -l`, { record: false }), 'the attachments are in the backup').not.toBe('0');
  }
  run(`rm -rf ${quote(copy)}`);
});

test('Retention', async () => {
  test.setTimeout(minutes(15));
  // A backup a night for the last hundred nights, as far as the listing of
  // the target goes: a backup is its manifest.
  const stamp = daysAgo => `${new Date(Date.now() - daysAgo * 86_400_000).toISOString().slice(0, 10).replace(/-/g, '')}T023000Z`;
  const nights = Array.from({ length: 100 }, (_, index) => stamp(index + 1));
  const seed = join(places().workDir, 'retention-seed');
  run(`rm -rf ${quote(seed)} && for night in ${nights.join(' ')}; do mkdir -p ${quote(seed)}/$night && echo 'a backup of the retention test' > ${quote(seed)}/$night/manifest.txt; done`);
  run(`${call} s3 copy /work/retention-seed "$(${call} remote backups)" && rm -rf ${quote(seed)}`);
  const before = backups();
  expect(before).toEqual(expect.arrayContaining(nights));

  const backup = script(deploy('backup.sh'));
  expect(backup.status).toBe(0);
  const after = backups();
  const [fresh] = after.filter(entry => !before.includes(entry));
  expect(fresh, 'the new backup is kept').toBeTruthy();
  expect(after).toEqual(retained([...before, fresh]));
  // Said plainly: today and the thirteen nights before it are there, the
  // hundredth night is gone, and so is everything past eight weeks.
  expect(after).toEqual(expect.arrayContaining(nights.slice(0, 13)));
  expect(after).not.toContain(nights[99]);
  expect(after.filter(entry => entry < stamp(70))).toEqual([]);
  expect(after.length).toBeLessThanOrEqual(14 + 8);
  expect(before.length - after.length).toBeGreaterThan(70);
});

test('Failed backup raises the alarm', async () => {
  test.setTimeout(minutes(10));
  await forgetAlarms();
  const before = backups();
  const failed = await withTargetRefusing(() => script(deploy('backup.sh')));
  expect(failed.status).not.toBe(0);
  const texts = await alarms();
  expect(texts).toHaveLength(1);
  expect(texts[0]).toContain(`Backup failed on ${domain}`);
  expect(texts[0]).toContain(`http://s3:${s3Port}, bucket ${backupBucket}`);
  expect(texts[0]).toMatch(/Answer: .*(403|Forbidden)/);
  expect(backups()).toEqual(before);
});

// =============================================================================
// Upgrade
// =============================================================================

test('Upgrade without a backup does not start', async () => {
  test.setTimeout(minutes(10));
  const pinned = envValue('HELPDESK_IMAGE');
  const started = inspect(containerOf('rails'))[0].State.StartedAt;
  const attempt = await withTargetRefusing(() => script(`${deploy('upgrade.sh')} ${env.INSTALL_NEXT_TAG}`));
  expect(attempt.status).not.toBe(0);
  expect(attempt.output).toContain(`the upgrade to ${env.INSTALL_NEXT_TAG} did not start`);
  expect(attempt.output).not.toContain('pulling');
  expect(envValue('HELPDESK_IMAGE')).toBe(pinned);
  expectRuns(pinned);
  const [rails] = inspect(containerOf('rails'));
  expect(rails.State.Running).toBe(true);
  expect(rails.State.StartedAt, 'the helpdesk was not stopped').toBe(started);
  await expectHealthy(30_000);
});

test('Failed upgrade is rolled back', async () => {
  test.setTimeout(minutes(40));
  await forgetAlarms();
  const pinned = envValue('HELPDESK_IMAGE');
  // The broken release runs its migrations (one more table) and then never
  // answers its health page.
  const attempt = script(`${deploy('upgrade.sh')} ${env.INSTALL_BROKEN_TAG}`);
  expect(attempt.status).not.toBe(0);
  expect(attempt.output).toContain('the helpdesk did not become healthy');
  expect(envValue('HELPDESK_IMAGE')).toBe(pinned);
  expectRuns(pinned);
  await expectHealthy();
  expect((await health()).body.overlay_version).toBe(env.INSTALL_OVERLAY_VERSION);
  // The database of before the upgrade: the broken release's table is gone,
  // the conversation, its photo and the store connection are there.
  expect(psql("SELECT to_regclass('public.install_test_markers') IS NULL")).toBe('t');
  await expectPhotoOpens();
  await expectStoreReads();
  const texts = await alarms();
  const alarm = texts.find(text => text.includes('Upgrade to'));
  expect(alarm, texts.join(' | ')).toBeTruthy();
  expect(alarm).toContain(`Upgrade to ${env.INSTALL_BROKEN_TAG} failed on ${domain}`);
  expect(alarm).toContain('is running again');
});

test('Upgrade to a newer tag', async ({ page }) => {
  test.setTimeout(minutes(60));
  let tag = env.INSTALL_NEXT_TAG;
  let version = env.INSTALL_NEXT_VERSION;
  if (env.INSTALL_PREVIOUS) {
    // A previous release exists: an instance of it, with a conversation, a
    // photo and a store connection, is upgraded to the image under test.
    expectNoSecretAnywhere();
    run(quote(join(repo, 'e2e', 'install', 'remove-instance.sh')));
    expect(install({ HELPDESK_IMAGE: env.INSTALL_PREVIOUS }).status).toBe(0);
    await page.goto(`${origin}/`);
    await completeOnboarding(page);
    await conversationWithPhoto();
    await connectStore();
    tag = env.INSTALL_TAG;
    version = env.INSTALL_OVERLAY_VERSION;
  }
  const upgrade = script(`${deploy('upgrade.sh')} ${tag}`);
  expect(upgrade.status).toBe(0);
  expect(upgrade.output).toContain(`upgrade to ${tag} finished`);
  const pinned = envValue('HELPDESK_IMAGE');
  expect(pinned).toMatch(new RegExp(`:${tag.replace(/[.]/g, '\\.')}@sha256:[0-9a-f]{64}$`));
  expectRuns(pinned);
  const answer = await health();
  expect(answer.status, JSON.stringify(answer.body)).toBe(200);
  expect(answer.body.overlay_version).toBe(version);
  expect(answer.body.chatwoot_version).toBe(env.INSTALL_CHATWOOT_VERSION);
  // The migrations of the new release ran (the newer copy of the image under
  // test carries one more).
  if (!env.INSTALL_PREVIOUS) expect(psql("SELECT to_regclass('public.install_test_markers') IS NULL")).toBe('f');
  // What was made before the upgrade is there.
  await expectPhotoOpens();
  await expectStoreReads();
});

// =============================================================================
// Restore
// =============================================================================

test('Restore into an empty installation', async ({ page }) => {
  test.setTimeout(minutes(40));
  const backup = script(deploy('backup.sh'));
  expect(backup.status).toBe(0);
  const pinned = envValue('HELPDESK_IMAGE');
  const latest = backups().at(-1);
  expectNoSecretAnywhere();

  // The machine is lost: nothing of the instance is left but the backup
  // target and the restore key.
  run(quote(join(repo, 'e2e', 'install', 'remove-instance.sh')));
  expectEmptyInstallation();
  remember({ session: null });

  const restore = script(`${deploy('restore.sh')} --identity ${quote(env.INSTALL_IDENTITY)}`, { env: target });
  expect(restore.status).toBe(0);
  expect(restore.output).toContain(`backup ${latest} is restored`);
  expect(envValue('HELPDESK_IMAGE')).toBe(pinned);
  expect(run(`stat --format '%a %U' ${quote(places().envFile)}`)).toBe('600 root');
  await expectHealthy();
  if (!env.INSTALL_TEST_ROOT) {
    expect(run('systemctl is-enabled inclamo-helpdesk-backup.timer inclamo-helpdesk-restore-test.timer')).toBe('enabled\nenabled');
  }

  // Users sign in with their passwords; the conversation, its photo and the
  // store connection are there; nobody is offered onboarding again.
  expect((await signIn(state().admin)).status).toBe(200);
  await expectPhotoOpens();
  await expectStoreReads();
  await page.goto(`${origin}/installation/onboarding`);
  await expect(page).toHaveURL(/\/app\/login/);
});

// =============================================================================
// Secrets, over everything the run did
// =============================================================================

test('Secrets stay out of the output', async () => {
  const text = readFileSync(transcript, 'utf8');
  expect(text).toContain('its secrets are drawn here and shown nowhere');
  expectNoSecretAnywhere();
});
