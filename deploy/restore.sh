#!/usr/bin/env bash
# Rebuilds the instance on an empty installation from a backup and the restore
# key: the environment file, the database, the attachments when they were kept
# on the machine. Then it starts the stack, installs the timers, writes a
# first backup from the new machine and runs a restore test.
#
#   sudo BACKUP_S3_ENDPOINT=... BACKUP_S3_REGION=... BACKUP_S3_BUCKET=... \
#        BACKUP_S3_ACCESS_KEY_ID=... BACKUP_S3_SECRET_ACCESS_KEY=... [BACKUP_S3_PREFIX=helpdesk] \
#        [BACKUP_S3_FORCE_PATH_STYLE=true] \
#        deploy/restore.sh --identity <file with the restore key> [--backup <UTC time>]
#
# Without --backup the newest finished backup is restored. The restore key is
# an `age` identity file; bring it for the restore and take it away afterwards.
# Nothing is touched before the key is there, and nothing is restored over an
# existing installation.
set -euo pipefail
# shellcheck source=deploy/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

identity=''
backup=''
while [ $# -gt 0 ]; do
  case $1 in
    --identity) identity=${2:-}; shift 2 || die 'usage: deploy/restore.sh --identity <file> [--backup <UTC time>]' ;;
    --backup) backup=${2:-}; shift 2 || die 'usage: deploy/restore.sh --identity <file> [--backup <UTC time>]' ;;
    *) die 'usage: deploy/restore.sh --identity <file> [--backup <UTC time>]' ;;
  esac
done

# First of all, before any data is read or written.
if [ -z "$identity" ] || [ ! -r "$identity" ] || [ ! -s "$identity" ]; then
  die 'the restore key is needed: give the age identity file with --identity <file>. Nothing was touched.'
fi

need_root
need_tools docker age curl sha256sum flock
[ ! -e "$ENV_FILE" ] || die "$ENV_FILE exists: this machine already has an instance, and a restore goes into an empty installation only. Nothing was touched."
ensure_none=$(stack_volumes)
[ -z "$ensure_none" ] || die "volumes of the stack exist on this machine ($(printf '%s' "$ensure_none" | tr '\n' ' ')): a restore goes into an empty installation only. Nothing was touched."

# The folder the install writes backups to unless it was given another.
BACKUP_S3_PREFIX=${BACKUP_S3_PREFIX:-helpdesk}
export BACKUP_S3_PREFIX
prepare_directories
take_lock
load_target
ensure_network "$NETWORK"

work=$WORK_DIR/restore
err=$WORK_DIR/restore.err
step='starting'
made=0

finish() {
  local status=$?
  trap - EXIT
  if [ "$status" -ne 0 ]; then
    warn "restore failed while $step: $(answer_of "$err")"
    if [ "$made" = 1 ]; then
      # Only what this run made: the installation was empty when it started.
      warn 'removing what this run made, so the restore can be run again'
      compose down --volumes --remove-orphans > /dev/null 2>&1 || true
      rm -f "$ENV_FILE"
    fi
  fi
  rm -rf "$work" "$err"
  exit "$status"
}
trap finish EXIT

umask 077
rm -rf "$work"
mkdir -p "$work"
: > "$err"

step="listing the backups on the backup target ($(target_name))"
if [ -z "$backup" ]; then
  backup=$(list_backups 2>> "$err" | tail -n 1)
  [ -n "$backup" ] || { echo 'the target holds no finished backup' >> "$err"; exit 1; }
fi
[[ $backup =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || { echo "not the name of a backup: $backup" >> "$err"; exit 1; }

step="downloading backup $backup"
s3 copy "$(remote "backups/$backup")" "/work/restore" >> "$err" 2>&1
[ -s "$work/manifest.txt" ] || { echo "backup $backup has no manifest: it was not finished" >> "$err"; exit 1; }
while read -r sha256 _ _ file; do
  if [ "$(sha256sum < "$work/$file" | cut -d ' ' -f 1)" != "$sha256" ]; then
    echo "$file of backup $backup does not have the checksum of its manifest" >> "$err"
    exit 1
  fi
done < "$work/manifest.txt"

step='decrypting the environment file with the restore key'
made=1
age --decrypt --identity "$identity" --output "$ENV_FILE" "$work/helpdesk.env.age" 2>> "$err"
chmod 600 "$ENV_FILE"
database=$(env_value POSTGRES_DATABASE)

step='starting Postgres and Redis'
compose pull --quiet >> "$err" 2>&1
compose up -d --wait postgres redis >> "$err" 2>&1

# The schema comes back with the dump, so the preparation that follows finds
# an existing schema: it migrates and loads no seeds, and no onboarding flag
# is set.
step='restoring the database'
age --decrypt --identity "$identity" "$work/database.dump.age" 2>> "$err" |
  compose exec -T postgres pg_restore --no-owner --exit-on-error --username=postgres --dbname="$database" >> "$err" 2>&1

step='bringing the database up to date'
prepare_database >> "$err" 2>&1

if [ -f "$work/storage.tar.age" ]; then
  step='restoring the attachments'
  age --decrypt --identity "$identity" "$work/storage.tar.age" 2>> "$err" |
    compose run --rm -T --no-deps rails 'exec tar -C /app/storage -xf -' >> "$err" 2>&1
fi

step='starting the stack'
compose up -d >> "$err" 2>&1
rm -rf "$work"

step='finishing the first start (first backup, restore test, health)'
made=0
finish_first_start

say "backup $backup is restored and the helpdesk is healthy at https://$(env_value HELPDESK_DOMAIN)"
say 'take the restore key off this machine now'
