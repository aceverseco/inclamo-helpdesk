#!/usr/bin/env bash
# Upgrades the instance to another tag of the published image.
#
#   sudo deploy/upgrade.sh <tag>          e.g. deploy/upgrade.sh 0.2.0-cw4.19.1
#
# In this order: a backup off the machine (no backup, no upgrade); pull the
# image of the tag; stop the helpdesk and its workers (intake stops for the
# length of the upgrade); dump the database as it stands; run Chatwoot's and
# the overlay's migrations with the new image; start; poll the health page for
# five minutes; run a restore test.
#
# When the migrations fail or the helpdesk does not become healthy, the
# previous image and the dump taken after intake stopped are put back, the
# stack is started and the alarm names the failed tag. Migrations are not
# rolled back: Chatwoot's are not all reversible.
set -euo pipefail
# shellcheck source=deploy/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ $# -eq 1 ] || die 'usage: deploy/upgrade.sh <tag>'
tag=$1
[[ $tag =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] || die "not an image tag: $tag"

need_root
need_tools docker age curl sha256sum md5sum flock
need_env_file
prepare_directories
take_lock

previous=$(env_value HELPDESK_IMAGE)
[ -n "$previous" ] || die "HELPDESK_IMAGE is not set in $ENV_FILE"
# <registry>/<name>:<tag>@sha256:<digest> without the tag and the digest.
repository=${previous%%@*}
case ${repository##*/} in
  *:*) repository=${repository%:*} ;;
esac
database=$(env_value POSTGRES_DATABASE)
work=$WORK_DIR/pre-upgrade
log=$WORK_DIR/upgrade.log

say "backing up before the upgrade to $tag"
"$DEPLOY_DIR/backup.sh" || die "the backup failed, so the upgrade to $tag did not start; the instance keeps running $previous"

say "pulling $repository:$tag"
docker pull --quiet "$repository:$tag" > /dev/null || die "the image $repository:$tag could not be pulled; the instance keeps running $previous"
digest=$(docker image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$repository:$tag" | sed -n "s|^$repository@||p" | head -n 1)
[ -n "$digest" ] || die "the registry gave no digest for $repository:$tag; the instance keeps running $previous"
next="$repository:$tag@$digest"

umask 077
rm -rf "$work"
mkdir -p "$work"
: > "$log"

say 'stopping the helpdesk and its workers'
compose stop rails sidekiq >> "$log" 2>&1

# From here on a failure puts the previous image and this dump back.
roll_back() {
  local reason=$1 state='is running again'
  warn "the upgrade to $tag failed ($reason): returning to $previous and the pre-upgrade database"
  compose stop rails sidekiq >> "$log" 2>&1 || true
  set_env_value HELPDESK_IMAGE "$previous"
  if [ -s "$work/database.dump" ]; then
    {
      compose exec -T postgres dropdb --force --if-exists --username=postgres "$database" &&
        compose exec -T postgres createdb --username=postgres "$database" &&
        compose exec -T postgres pg_restore --no-owner --exit-on-error --username=postgres --dbname="$database" < "$work/database.dump"
    } >> "$log" 2>&1 || state='could NOT be restored: the pre-upgrade dump is kept on the machine, act by hand'
  fi
  compose up -d >> "$log" 2>&1 || true
  if [ "$state" = 'is running again' ]; then
    wait_healthy 300 || state='was put back but is not healthy'
    rm -rf "$work"
  fi
  alarm "Upgrade to $tag failed on $(instance_name) ($reason). The previous image ${previous%%@*} with the pre-upgrade database $state."
  die "upgrade to $tag failed ($reason); the previous image $state"
}

say 'dumping the database as it stands'
if ! dump_database > "$work/database.dump" 2>> "$log"; then
  rm -f "$work/database.dump"
  roll_back 'the pre-upgrade dump could not be made'
fi

set_env_value HELPDESK_IMAGE "$next"

say 'running the migrations with the new image'
prepare_database >> "$log" 2>&1 || roll_back 'the migrations failed'

say 'starting the stack and waiting for it to be healthy (up to five minutes)'
compose up -d >> "$log" 2>&1 || roll_back 'the stack did not start'
wait_healthy 300 || roll_back 'the helpdesk did not become healthy'

rm -rf "$work"
say "the instance runs $next"

say 'running the restore test'
"$DEPLOY_DIR/restore-test.sh" || die "the upgrade to $tag is in place and healthy, but the restore test failed (the alarm was sent)"

rm -f "$log"
say "upgrade to $tag finished"
