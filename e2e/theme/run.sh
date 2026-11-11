#!/bin/sh
# Uses an isolated Docker network, synthetic accounts and an offline Shopify fixture.
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
project=${THEME_PROJECT:-inclamo-theme}
output=${E2E_OUTPUT:-"$root/e2e/theme-output"}
export HELPDESK_IMAGE=${HELPDESK_IMAGE:?Set HELPDESK_IMAGE to the image under test}
mkdir -p "$output"
if [ ! -f "$root/e2e/theme/stack.env" ]; then
  umask 077
  cat > "$root/e2e/theme/stack.env" <<'ENV'
SECRET_KEY_BASE=synthetic-theme-only-00000000000000000000000000000000000000000000000000
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=theme-only-primary-key-0000000000
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=theme-only-deterministic-00000000
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=theme-only-salt-00000000000000000
ENV
fi
compose() { docker compose -p "$project" -f "$root/e2e/theme/compose.yaml" "$@"; }
finish() {
  status=$?
  if [ "${THEME_KEEP:-0}" != 1 ]; then compose down --volumes >/dev/null 2>&1 || true; fi
  exit "$status"
}
trap finish EXIT INT TERM
# Install browser dependencies before joining the internal network.
docker build -q -f "$root/e2e/theme/Dockerfile.playwright" -t "$project-browser" "$root" >/dev/null
compose up -d postgres redis
compose up -d --force-recreate shopify-fixture
compose run --rm -T rails bundle exec rails db:chatwoot_prepare > "$output/prepare.log" 2>&1
compose run --rm -T rails bundle exec rails runner - < "$root/e2e/theme/seed.rb" > "$output/seed.log" 2>&1
account=$(sed -n 's/^THEME_ACCOUNT_ID=//p' "$output/seed.log" | tail -1)
data=$(sed -n 's/^THEME_DATA=//p' "$output/seed.log" | tail -1)
test -n "$account"
test -n "$data"
compose up -d rails sidekiq
ready=0
for attempt in $(seq 1 60); do
  if compose exec -T rails ruby -rnet/http -e 'exit(Net::HTTP.get_response(URI("http://127.0.0.1:3000/api")).code == "200" ? 0 : 1)' >/dev/null 2>&1; then ready=1; break; fi
  sleep 2
done
test "$ready" = 1 || { compose logs --tail 40 rails; exit 1; }
# Exercise the server-rendered onboarding view without creating another account.
# Only the disposable stack's Redis is changed; always clear the flag afterwards.
if [ "${THEME_LEGACY:-0}" != 1 ]; then
  compose exec -T rails bundle exec rails runner 'Redis::Alfred.set(Redis::Alfred::CHATWOOT_INSTALLATION_ONBOARDING, true)' > "$output/onboarding-flag.log" 2>&1
  onboarding_status=0
  docker run --rm --ipc=host --network "${project}_default" \
    -e HELPDESK_URL=http://rails:3000 -e THEME_ONBOARDING=1 -e E2E_OUTPUT=/out/onboarding \
    -v "$output":/out -v "$root/e2e/theme/snapshots":/work/e2e/theme/snapshots \
    "$project-browser" npx playwright test --config playwright.theme.config.mjs "$@" || onboarding_status=$?
  compose exec -T rails bundle exec rails runner 'Redis::Alfred.delete(Redis::Alfred::CHATWOOT_INSTALLATION_ONBOARDING)' >> "$output/onboarding-flag.log" 2>&1
  test "$onboarding_status" = 0 || exit "$onboarding_status"
fi
docker run --rm --ipc=host --network "${project}_default" \
  -e HELPDESK_URL=http://rails:3000 -e E2E_ACCOUNT_ID="$account" \
  -e THEME_DATA="$data" \
  -e STAND_ADMIN_EMAIL=theme-admin@example.test -e STAND_AGENT_EMAIL=theme-agent@example.test \
  -e STAND_ADMIN_PASSWORD=Synthetic-theme-only-123! -e STAND_AGENT_PASSWORD=Synthetic-theme-only-123! \
  -e E2E_OUTPUT=/out -e THEME_LEGACY="${THEME_LEGACY:-0}" -e THEME_BASELINE="${THEME_BASELINE:-0}" \
  -v "$output":/out -v "$root/e2e/theme/snapshots":/work/e2e/theme/snapshots \
  "$project-browser" npx playwright test --config playwright.theme.config.mjs "$@"
