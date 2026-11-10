// Validates every GraphQL document in custom/graphql/shopify and e2e/graphql
// against the schema Shopify publishes for the pinned Admin API version.
//
//   node scripts/check-graphql.mjs            validate the documents
//   node scripts/check-graphql.mjs --self-test  prove that a wrong document fails
import { readFileSync, readdirSync } from 'node:fs';
import { basename, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildClientSchema, getIntrospectionQuery, parse, validate } from 'graphql';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const version = readFileSync(join(root, 'custom', 'graphql', 'shopify', 'API_VERSION'), 'utf8').trim();
// Checked directories: what the backend sends, and what the end-to-end tests send.
const dirs = [join(root, 'custom', 'graphql', 'shopify'), join(root, 'e2e', 'graphql')];
let dir = dirs[0];
const endpoint = `https://shopify.dev/admin-graphql-direct-proxy/${version}`;

async function publishedSchema() {
  const response = await fetch(endpoint, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: getIntrospectionQuery() }),
  });
  if (!response.ok) throw new Error(`could not fetch the schema of ${version}: HTTP ${response.status}`);
  const payload = await response.json();
  if (!payload.data) throw new Error(`no schema in the answer for ${version}: ${JSON.stringify(payload).slice(0, 200)}`);
  return buildClientSchema(payload.data);
}

// A document may spread fragments kept one per file in fragments/; they are
// appended here the same way the backend appends them before sending.
function withFragments(source) {
  const needed = [];
  const queue = [...source.matchAll(/\.\.\.\s*([A-Z]\w*)/g)].map(match => match[1]);
  while (queue.length > 0) {
    const name = queue.shift();
    if (needed.includes(name)) continue;
    needed.push(name);
    const fragment = readFileSync(join(dir, 'fragments', `${name}.graphql`), 'utf8');
    queue.push(...[...fragment.matchAll(/\.\.\.\s*([A-Z]\w*)/g)].map(match => match[1]));
  }
  return [source, ...needed.map(name => readFileSync(join(dir, 'fragments', `${name}.graphql`), 'utf8'))].join('\n\n');
}

// Returns the problems of one document as strings; empty when it is valid.
function problemsOf(schema, name, source) {
  let document;
  try {
    document = parse(source);
  } catch (error) {
    return [`does not parse: ${error.message}`];
  }
  const operations = document.definitions.filter(definition => definition.kind === 'OperationDefinition');
  const problems = [];
  if (operations.length !== 1) problems.push(`must hold exactly one operation, holds ${operations.length}`);
  else if (operations[0].name?.value !== name) problems.push(`the operation must be named ${name}, like its file`);
  for (const error of validate(schema, document)) problems.push(error.message);
  return problems;
}

const schema = await publishedSchema();

if (process.argv.includes('--self-test')) {
  const wrong = 'query self_test { shop { name noSuchFieldOnShop } }';
  const problems = problemsOf(schema, 'self_test', wrong);
  if (!problems.some(problem => problem.includes('noSuchFieldOnShop'))) {
    console.error('self-test failed: a document with an unknown field was accepted');
    process.exit(1);
  }
  console.log(`self-test passed: an unknown field is refused (${problems[0]})`);
  process.exit(0);
}

let failed = 0;
let total = 0;
for (dir of dirs) {
  const files = readdirSync(dir).filter(file => file.endsWith('.graphql')).sort();
  if (files.length === 0) {
    console.error(`no documents found in ${dir}`);
    process.exit(1);
  }
  for (const file of files) {
    total += 1;
    let problems;
    try {
      problems = problemsOf(schema, basename(file, '.graphql'), withFragments(readFileSync(join(dir, file), 'utf8')));
    } catch (error) {
      problems = [`could not be put together: ${error.message}`];
    }
    const shown = join(basename(dirname(dir)), basename(dir), file);
    if (problems.length === 0) {
      console.log(`ok    ${shown}`);
    } else {
      failed += 1;
      console.error(`FAIL  ${shown}`);
      for (const problem of problems) console.error(`      ${problem}`);
    }
  }
}
console.log(`${total - failed} of ${total} documents valid against Admin API ${version}`);
process.exit(failed === 0 ? 0 : 1);
