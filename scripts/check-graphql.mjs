// Validates every GraphQL document in custom/graphql/shopify against the
// schema Shopify publishes for the pinned Admin API version.
//
//   node scripts/check-graphql.mjs            validate the documents
//   node scripts/check-graphql.mjs --self-test  prove that a wrong document fails
import { readFileSync, readdirSync } from 'node:fs';
import { basename, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildClientSchema, getIntrospectionQuery, parse, validate } from 'graphql';

const dir = join(dirname(fileURLToPath(import.meta.url)), '..', 'custom', 'graphql', 'shopify');
const version = readFileSync(join(dir, 'API_VERSION'), 'utf8').trim();
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

const files = readdirSync(dir).filter(file => file.endsWith('.graphql')).sort();
if (files.length === 0) {
  console.error(`no documents found in ${dir}`);
  process.exit(1);
}
let failed = 0;
for (const file of files) {
  const problems = problemsOf(schema, basename(file, '.graphql'), readFileSync(join(dir, file), 'utf8'));
  if (problems.length === 0) {
    console.log(`ok    ${file}`);
  } else {
    failed += 1;
    console.error(`FAIL  ${file}`);
    for (const problem of problems) console.error(`      ${problem}`);
  }
}
console.log(`${files.length - failed} of ${files.length} documents valid against Admin API ${version}`);
process.exit(failed === 0 ? 0 : 1);
