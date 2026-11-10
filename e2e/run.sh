#!/bin/sh
# Brings up a helpdesk of its own for the end-to-end tests, prepares it and
# runs the tests against it and the development store.
#
#   HELPDESK_IMAGE=inclamo-helpdesk:0.1.0-cw4.19.1 e2e/run.sh [playwright arguments]
#
# Needs Docker, and in the environment the credentials of the two test apps on
# the development store: SHOPIFY_BENCH_DOMAIN, _CLIENT_ID, _CLIENT_SECRET (the
# app the helpdesk connects with) and SHOPIFY_SEEDER_DOMAIN, _CLIENT_ID,
# _CLIENT_SECRET (the app that creates and removes the test data).
# E2E_OTHER_SHOP_DOMAIN names a store that exists and has neither app installed.
# The store may be empty: the tests create the products, customers and orders
# they need, and remove the customers and orders afterwards.
# Optional: SHOPIFY_LIMITED_DOMAIN, _CLIENT_ID, _CLIENT_SECRET, an app with no
# distribution method chosen; with it the limited-mode tests meet a real refusal.
# The AI agent's tests talk to a stand-in for the AI service that runs in the
# stack; E2E_AI_CODE and E2E_AI_REFUSED_CODE make them use codes the AI service
# issued instead (docs/ai-connector.md §8).
# E2E_KEEP=1 leaves the stack running afterwards; E2E_OUTPUT is where reports go.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
project=${E2E_PROJECT:-inclamo-e2e}
output=${E2E_OUTPUT:-"$root/e2e/output"}
stack_env="$root/e2e/.stack.env"
: "${HELPDESK_IMAGE:?set HELPDESK_IMAGE to the image under test}"
for name in E2E_OTHER_SHOP_DOMAIN SHOPIFY_BENCH_DOMAIN SHOPIFY_BENCH_CLIENT_ID SHOPIFY_BENCH_CLIENT_SECRET SHOPIFY_SEEDER_DOMAIN SHOPIFY_SEEDER_CLIENT_ID SHOPIFY_SEEDER_CLIENT_SECRET; do
  eval ": \"\${$name:?$name is not set}\""
done

random() { od -An -N"$1" -tx1 /dev/urandom | tr -d ' \n'; }

# Secrets of this stack only, made once and thrown away with it.
if [ ! -f "$stack_env" ]; then
  umask 077
  cat > "$stack_env" <<ENV
SECRET_KEY_BASE=$(random 64)
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=$(random 32)
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=$(random 32)
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=$(random 32)
FRONTEND_URL=http://rails:3000
POSTGRES_HOST=postgres
POSTGRES_USERNAME=postgres
POSTGRES_PASSWORD=$(random 16)
REDIS_PASSWORD=$(random 16)
REDIS_URL=redis://redis:6379
ENABLE_ACCOUNT_SIGNUP=false
HELPDESK_PORT=${E2E_PORT:-3190}
STAND_ADMIN_EMAIL=e2e-admin@example.test
STAND_ADMIN_PASSWORD=A$(random 14)!z
STAND_AGENT_EMAIL=e2e-agent@example.test
STAND_AGENT_PASSWORD=A$(random 14)!z
ENV
fi

export HELPDESK_IMAGE HELPDESK_ENV_FILE="$stack_env"
compose() {
  docker compose -p "$project" --env-file "$stack_env" -f "$root/dev/docker-compose.yaml" -f "$root/dev/docker-compose.e2e.yaml" "$@"
}
finish() {
  status=$?
  [ "${E2E_KEEP:-0}" = 1 ] || compose down --volumes --remove-orphans >/dev/null 2>&1 || true
  [ "${E2E_KEEP:-0}" = 1 ] || rm -f "$stack_env"
  exit $status
}
trap finish EXIT INT TERM

echo "e2e: starting $HELPDESK_IMAGE as project $project"
compose up -d postgres redis shopify-proxy stand-in-agent >/dev/null
compose run --rm -T rails bundle exec rails db:chatwoot_prepare >/dev/null
# The users' passwords reach the container from the stack's env file.
account=$(compose run --rm -T rails bundle exec rails runner - < "$root/e2e/setup.rb" | sed -n 's/^E2E_ACCOUNT_ID=//p' | tail -1)
[ -n "$account" ] || { echo "e2e: the helpdesk could not be prepared" >&2; exit 1; }
compose up -d rails sidekiq >/dev/null

echo "e2e: waiting for the helpdesk"
ready=0
for attempt in $(seq 1 60); do
  if compose exec -T rails ruby -rnet/http -e 'exit(Net::HTTP.get_response(URI("http://127.0.0.1:3000/api")).code == "200" ? 0 : 1)' >/dev/null 2>&1; then ready=1; break; fi
  sleep 3
done
[ "$ready" = 1 ] || { echo "e2e: the helpdesk did not come up" >&2; compose logs --tail 40 rails >&2; exit 1; }

mkdir -p "$output"
playwright=$(sed -n 's/.*"@playwright\/test": "\([0-9.]*\)".*/\1/p' "$root/e2e/package.json")
echo "e2e: running the tests (account $account, Playwright $playwright)"
docker run --rm --ipc=host --network "${project}_default" \
  --env-file "$stack_env" \
  -e SHOPIFY_BENCH_DOMAIN -e SHOPIFY_BENCH_CLIENT_ID -e SHOPIFY_BENCH_CLIENT_SECRET \
  -e SHOPIFY_SEEDER_DOMAIN -e SHOPIFY_SEEDER_CLIENT_ID -e SHOPIFY_SEEDER_CLIENT_SECRET \
  -e SHOPIFY_LIMITED_DOMAIN -e SHOPIFY_LIMITED_CLIENT_ID -e SHOPIFY_LIMITED_CLIENT_SECRET \
  -e HELPDESK_URL=http://rails:3000 -e E2E_PROXY_URL=http://shopify-proxy:8080 -e E2E_AGENT_URL=http://stand-in-agent:8090 -e E2E_ACCOUNT_ID="$account" \
  -e E2E_AI_CODE -e E2E_AI_REFUSED_CODE \
  -e E2E_OUTPUT=/out -e E2E_RUN="${E2E_RUN:-r$(date +%m%d%H%M%S)}" -e E2E_OTHER_SHOP_DOMAIN -e CI="${CI:-}" \
  -v "$root":/repo:ro -v "$output":/out -w /work \
  "mcr.microsoft.com/playwright:v$playwright-noble" sh -c '
    set -e
    mkdir -p /work/custom/graphql /work/openspec && cp -r /repo/e2e /repo/scripts /work/ && cp -r /repo/custom/graphql/shopify /work/custom/graphql/ && cp -r /repo/openspec/. /work/openspec/
    node /work/scripts/check-e2e-coverage.mjs
    cd /work/e2e && rm -rf node_modules && npm install --no-audit --no-fund >/dev/null 2>&1
    npx playwright test "$@"' sh "$@"
