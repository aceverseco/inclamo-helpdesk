#!/usr/bin/env bash
# Removes the instance the install tests made, so that the next test meets an
# empty installation: the stack and the throwaway stack of the restore test
# with their volumes, the environment file, the state and the work directory,
# and the timers. With --all also the test services (S3 server, mail catcher,
# alarm receiver) and the network.
#
#   e2e/install/remove-instance.sh [--all]
#
# It removes a test instance only: an environment file that was not written by
# `deploy/install.sh --test` stops it.
set -euo pipefail
# shellcheck source=deploy/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../../deploy/lib.sh"
need_root

if [ -f "$ENV_FILE" ] && [ "$(env_value HELPDESK_CADDY_FLAGS)" != '--internal-certs' ]; then
  die "$ENV_FILE was not written by the install's test mode: this is not a test instance, and nothing was removed"
fi

projects=("$PROJECT" "$TEST_PROJECT")
[ "${1:-}" != --all ] || projects+=("$PROJECT-test-services")
for project in "${projects[@]}"; do
  containers=$(docker ps --all --quiet --filter "label=com.docker.compose.project=$project")
  # shellcheck disable=SC2086
  [ -z "$containers" ] || docker rm --force --volumes $containers > /dev/null
  volumes=$(docker volume ls --quiet --filter "label=com.docker.compose.project=$project")
  # shellcheck disable=SC2086
  [ -z "$volumes" ] || docker volume rm $volumes > /dev/null
done
docker network rm "$TEST_PROJECT" > /dev/null 2>&1 || true
[ "${1:-}" != --all ] || docker network rm "$NETWORK" > /dev/null 2>&1 || true

if [ -z "${INSTALL_TEST_ROOT:-}" ] && command -v systemctl > /dev/null 2>&1; then
  systemctl disable --now inclamo-helpdesk-backup.timer inclamo-helpdesk-restore-test.timer > /dev/null 2>&1 || true
  rm -f /etc/systemd/system/inclamo-helpdesk-backup.service /etc/systemd/system/inclamo-helpdesk-backup.timer \
    /etc/systemd/system/inclamo-helpdesk-restore-test.service /etc/systemd/system/inclamo-helpdesk-restore-test.timer
  systemctl daemon-reload || true
fi

# The three places of deploy/lib.sh, each below a directory of its own.
rm -f "$ENV_FILE"
rm -rf "${STATE_DIR:?}" "${WORK_DIR:?}"
rmdir "$(dirname "$ENV_FILE")" 2> /dev/null || true
say 'the test instance is removed'
