// Command line for the store data of the end-to-end tests.
//
//   node e2e/seed.mjs clean <run>   delete every order and customer tagged with that run
//   node e2e/seed.mjs demo  <run>   create a small data set to look at by hand
//
// Credentials of the seeding app come from SHOPIFY_SEEDER_DOMAIN, _CLIENT_ID
// and _CLIENT_SECRET. The tests themselves create what they need (lib/store.mjs).
import { openStore } from './lib/store.mjs';

const [action = 'clean', run = 'manual'] = process.argv.slice(2);
const store = await openStore(run);

if (action === 'clean') {
  console.log(JSON.stringify(await store.clean(), null, 2));
} else {
  const maya = await store.customer('Maya');
  const open = await store.order(maya, { items: 3 });
  const shipped = await store.order(maya, { items: 2 });
  await store.ship(shipped, [0], { company: 'DHL Express', number: `E2E${run}A`, url: `https://example.com/track/E2E${run}A` });
  await store.ship(shipped, [1], { company: 'UPS', number: `E2E${run}B`, url: `https://example.com/track/E2E${run}B` });
  console.log(JSON.stringify({ run, customer: maya, orders: [open.number, shipped.number] }, null, 2));
}
