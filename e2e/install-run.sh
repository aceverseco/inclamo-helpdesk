#!/usr/bin/env bash
# Installs a throwaway instance with deploy/install.sh in its test mode and
# runs the install tests (e2e/tests/instance-installation.spec.mjs) against
# it: install and its refusals, first run, mail, attachments, backups,
# restore, upgrade and rollback, health. Everything it made is removed at the
# end.
#
#   sudo -E HELPDESK_IMAGE=inclamo-helpdesk:0.1.0-cw4.19.1 ACTIVE_STORAGE_SERVICE=local \
#     e2e/install-run.sh [playwright arguments]
#
# Needs root, Docker and `age` (installed with apt-get when missing), and in
# the environment:
#   HELPDESK_IMAGE           the image under test, built on this machine
#   ACTIVE_STORAGE_SERVICE   local (the default) or s3_compatible; the tests
#                            hold for both, one run each
#   SHOPIFY_BENCH_DOMAIN, SHOPIFY_BENCH_CLIENT_ID, SHOPIFY_BENCH_CLIENT_SECRET
#                            the test app on the development store: the store
#                            connection must survive a second install, a
#                            restore and an upgrade
# Optional:
#   INSTALL_PREVIOUS_IMAGE   the image of the previous release. With it the
#                            upgrade test installs that release and upgrades to
#                            the image under test; without it (no earlier
#                            release exists) it upgrades the image under test
#                            to a copy of itself with a newer overlay version
#                            and one more migration (e2e/install/images).
#   INSTALL_KEEP=1           leaves everything up afterwards, and starts from
#                            what an earlier run left
#   E2E_OUTPUT               where the report and the test keys go
#
# The test mode (deploy/install.sh --test, deploy/test/) changes only what a
# CI runner cannot have: the web server's internal authority, given addresses
# for the domain check, an S3 server, a mail catcher and an alarm receiver.
# The image is pulled as on a real instance, from a registry started here.
#
# On a machine that already serves something on ports 80 and 443, or that must
# not get /etc/inclamo-helpdesk and the timers, also set (deploy/lib.sh):
#   INSTALL_TEST_ROOT        an absolute directory for the environment file,
#                            the state and the work directory; no timers
#   INSTALL_TEST_PROJECT     the name of the Compose project and its network
#   INSTALL_TEST_HTTP_PORT, INSTALL_TEST_HTTPS_PORT, INSTALL_TEST_MAILPIT_PORT,
#   INSTALL_TEST_ALARM_PORT, INSTALL_TEST_S3_PORT, INSTALL_TEST_REGISTRY_PORT
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=deploy/lib.sh
. "$root/deploy/lib.sh"
need_root

: "${HELPDESK_IMAGE:?set HELPDESK_IMAGE to the image under test}"
storage=${ACTIVE_STORAGE_SERVICE:-local}
case $storage in
  local | s3_compatible) ;;
  *) die 'ACTIVE_STORAGE_SERVICE must be local or s3_compatible' ;;
esac
for name in SHOPIFY_BENCH_DOMAIN SHOPIFY_BENCH_CLIENT_ID SHOPIFY_BENCH_CLIENT_SECRET; do
  [ -n "${!name:-}" ] || die "$name is not set"
done
keep=${INSTALL_KEEP:-0}
output=${E2E_OUTPUT:-"$root/e2e/output/install-$storage"}
domain=helpdesk.install.test
registry_port=${INSTALL_TEST_REGISTRY_PORT:-5000}
repository=127.0.0.1:$registry_port/inclamo-helpdesk
registry=$PROJECT-test-registry
registry_image=registry:3.1.2@sha256:82f6ff4a7f982960c8aa51617fea3aabc485df6e55cce80d22deb1de36f1bc3c

command -v age-keygen > /dev/null 2>&1 || {
  command -v apt-get > /dev/null 2>&1 || die 'age is needed on this machine and was not found'
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends age > /dev/null
}
need_tools docker age age-keygen curl

if [ -e "$ENV_FILE" ] && [ "$keep" != 1 ]; then
  die "$ENV_FILE exists: this machine has an instance, and the install tests need an empty installation. Nothing was changed."
fi

random() { od -An -N"$1" -tx1 /dev/urandom | tr -d ' \n'; }

# What the tests need to hold: the restore key, a key that is not the restore
# key, and the keys of the test S3 server. Made once, removed at the end.
keys=$output/keys
( umask 077; mkdir -p "$output" "$keys" )
[ -s "$keys/restore-key.txt" ] || { rm -f "$keys/restore-key.txt"; age-keygen --output "$keys/restore-key.txt" 2> /dev/null; }
[ -s "$keys/other-key.txt" ] || { rm -f "$keys/other-key.txt"; age-keygen --output "$keys/other-key.txt" 2> /dev/null; }
[ -s "$keys/s3-access-key" ] || ( umask 077; printf 'test%s' "$(random 6)" > "$keys/s3-access-key"; random 20 > "$keys/s3-secret-key" )
recipient=$(age-keygen -y "$keys/restore-key.txt")
# A new run starts with nothing remembered from the last one.
[ "$keep" = 1 ] || rm -f "$output/state.json" "$output/transcript.log" "$output/install-run.log" "$output/results.json"

remove_images() {
  docker image ls --digests --format '{{.Repository}} {{.Tag}} {{.Digest}}' "$repository" 2> /dev/null |
    while read -r name tag digest; do
      [ "$tag" = '<none>' ] || docker image rm "$name:$tag" > /dev/null 2>&1 || true
      [ "$digest" = '<none>' ] || docker image rm "$name@$digest" > /dev/null 2>&1 || true
    done
}

finish() {
  local status=$?
  trap - EXIT INT TERM HUP
  if [ "$keep" != 1 ]; then
    say 'install tests: removing the test instance, its services, the registry and the test keys'
    "$root/e2e/install/remove-instance.sh" --all > /dev/null 2>&1 || warn 'install tests: the test instance could not be removed completely'
    docker rm --force --volumes "$registry" > /dev/null 2>&1 || true
    remove_images
    # The keys, and the password of the throwaway administrator.
    rm -f "$keys/restore-key.txt" "$keys/other-key.txt" "$keys/s3-access-key" "$keys/s3-secret-key" "$output/state.json"
  fi
  exit "$status"
}
trap finish EXIT
trap 'exit 130' INT TERM HUP

# --- the registry the instance pulls from -------------------------------------

overlay=$(docker run --rm --entrypoint cat "$HELPDESK_IMAGE" custom/INCLAMO_VERSION)
chatwoot=$(docker run --rm --entrypoint cat "$HELPDESK_IMAGE" custom/CHATWOOT_VERSION)
chatwoot=${chatwoot#v}
tag=$overlay-cw$chatwoot
next_version=$overlay-next
next_tag=$next_version-cw$chatwoot
broken_tag=$overlay-broken-cw$chatwoot

if ! docker container inspect "$registry" > /dev/null 2>&1; then
  say "install tests: starting a registry on 127.0.0.1:$registry_port"
  docker run --detach --name "$registry" --publish "127.0.0.1:$registry_port:5000" "$registry_image" > /dev/null
fi
for _ in $(seq 1 30); do
  curl --silent --fail --output /dev/null "http://127.0.0.1:$registry_port/v2/" && break
  sleep 1
done

say "install tests: publishing $HELPDESK_IMAGE there as $tag, with a newer and a broken release"
docker tag "$HELPDESK_IMAGE" "$repository:$tag"
docker push --quiet "$repository:$tag" > /dev/null
docker build --quiet --tag "$repository:$next_tag" --build-arg "BASE=$repository:$tag" --build-arg "VERSION=$next_version" \
  --file "$root/e2e/install/images/next.Dockerfile" "$root/e2e/install/images" > /dev/null
docker push --quiet "$repository:$next_tag" > /dev/null
docker build --quiet --tag "$repository:$broken_tag" --build-arg "BASE=$repository:$next_tag" \
  --file "$root/e2e/install/images/broken.Dockerfile" "$root/e2e/install/images" > /dev/null
docker push --quiet "$repository:$broken_tag" > /dev/null
previous=''
if [ -n "${INSTALL_PREVIOUS_IMAGE:-}" ]; then
  say "install tests: publishing the previous release $INSTALL_PREVIOUS_IMAGE there as previous"
  docker pull --quiet "$INSTALL_PREVIOUS_IMAGE" > /dev/null
  docker tag "$INSTALL_PREVIOUS_IMAGE" "$repository:previous"
  docker push --quiet "$repository:previous" > /dev/null
  previous=$repository:previous
fi

# --- the tests ----------------------------------------------------------------

# The browser and the tests run in a container with the host's network (the
# domain and the test S3 server are given the host's own address there) and
# the host's processes: a test runs the scripts of deploy/ on the host itself,
# as an operator does, by entering the host's namespaces.
playwright=$(sed -n 's/.*"@playwright\/test": "\([0-9.]*\)".*/\1/p' "$root/e2e/package.json")
log=$output/install-run.log
say "install tests: running ($storage attachments, Playwright $playwright)"
status=0
docker run --rm --ipc=host --privileged --pid=host --network host \
  --add-host "$domain:127.0.0.1" --add-host s3:127.0.0.1 \
  -e INSTALL_REPO="$root" -e INSTALL_DOMAIN="$domain" -e INSTALL_STORAGE="$storage" -e INSTALL_HOST_PATH="$PATH" \
  -e INSTALL_IMAGE="$repository:$tag" -e INSTALL_TAG="$tag" -e INSTALL_OVERLAY_VERSION="$overlay" -e INSTALL_CHATWOOT_VERSION="$chatwoot" \
  -e INSTALL_NEXT_TAG="$next_tag" -e INSTALL_NEXT_VERSION="$next_version" -e INSTALL_BROKEN_TAG="$broken_tag" -e INSTALL_PREVIOUS="$previous" \
  -e INSTALL_IDENTITY="$keys/restore-key.txt" -e INSTALL_OTHER_IDENTITY="$keys/other-key.txt" -e INSTALL_RECIPIENT="$recipient" \
  -e INSTALL_S3_ACCESS_KEY="$(cat "$keys/s3-access-key")" -e INSTALL_S3_SECRET_KEY="$(cat "$keys/s3-secret-key")" \
  -e INSTALL_TEST_ROOT -e INSTALL_TEST_PROJECT -e INSTALL_TEST_HTTP_PORT -e INSTALL_TEST_HTTPS_PORT \
  -e INSTALL_TEST_MAILPIT_PORT -e INSTALL_TEST_ALARM_PORT -e INSTALL_TEST_S3_PORT \
  -e SHOPIFY_BENCH_DOMAIN -e SHOPIFY_BENCH_CLIENT_ID -e SHOPIFY_BENCH_CLIENT_SECRET \
  -e E2E_OUTPUT="$output" -e CI="${CI:-}" \
  -v "$root":/repo:ro -v "$output":"$output" -w /work \
  "mcr.microsoft.com/playwright:v$playwright-noble" sh -c '
    set -e
    mkdir -p /work/docs/behavior && cp -r /repo/e2e /repo/scripts /work/ && cp -r /repo/docs/behavior/. /work/docs/behavior/
    node /work/scripts/check-e2e-coverage.mjs
    cd /work/e2e && rm -rf node_modules output && npm install --no-audit --no-fund >/dev/null 2>&1
    npx playwright test --config playwright.install.config.mjs "$@"' sh "$@" 2>&1 | tee "$log" || status=$?

# --- the log holds no secret of the instance ----------------------------------

if [ -f "$ENV_FILE" ]; then
  # The secrets the install drew; the keys of the test services are the tests' own.
  for name in SECRET_KEY_BASE ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT POSTGRES_PASSWORD REDIS_PASSWORD; do
    secret=$(env_value "$name")
    [ -n "$secret" ] || continue
    if grep --quiet --fixed-strings --recursive -- "$secret" "$log" "$output/results.json" "$output/transcript.log" 2> /dev/null; then
      warn "install tests: the output of the run holds the value of $name"
      status=1
    fi
  done
fi
exit "$status"
