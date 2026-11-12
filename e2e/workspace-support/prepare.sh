#!/bin/sh
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
project=${SUPPORT_PROJECT:-inclamo-workspace-support}
export HELPDESK_IMAGE=${HELPDESK_IMAGE:?Set the image under test}
output=${E2E_OUTPUT:-"$root/workspace-support-output"}
mkdir -p "$output"
compose() { docker compose -p "$project" -f "$root/e2e/workspace-support/compose.yaml" "$@"; }
compose up -d postgres redis mail shopify-fixture support-proxy
for service in central client hosted; do
  compose run --rm -T "$service" bundle exec rails db:chatwoot_prepare > "$output/$service-prepare.log" 2>&1
  if [ "$service" != central ]; then
    compose run --rm -T "$service" bundle exec rails runner - < "$root/e2e/theme/seed.rb" > "$output/$service-theme-seed.log" 2>&1
  fi
  compose run --rm -T "$service" bundle exec rails runner - < "$root/e2e/workspace-support/seed.rb" > "$output/$service-seed.log" 2>&1
done
compose up -d central central-worker client client-worker hosted hosted-worker
# Readiness and hosted trust are part of reproducible setup, before test tickets.
for service in central client hosted; do
  compose exec -T "$service" ruby -rnet/http -e '60.times { begin; exit 0 if Net::HTTP.get_response(URI("http://127.0.0.1:3000/app/login")).code.to_i < 500; rescue StandardError; end; sleep 1 }; exit 1' ||
    { echo "prepare: $service did not answer on /app/login within a minute; its logs follow" >&2; compose logs --tail 80 "$service" >&2; exit 1; }
done
trust=$(compose exec -T hosted bundle exec rails runner - < "$root/e2e/workspace-support/enroll-hosted.rb" | tail -1)
compose exec -T central bundle exec rake "inclamo:support:trust_hosted[$trust]" > "$output/hosted-trust.log" 2>&1
