#!/usr/bin/env bash
# Backs the instance up off the machine: the database, the attachments when
# they are kept on the machine (ACTIVE_STORAGE_SERVICE=local) and the
# environment file, each encrypted with `age` to BACKUP_AGE_RECIPIENT, whose
# private key is not on this machine. Then the retention, then the status file
# the health page reads. A failure posts to the alarm webhook at once.
#
#   sudo deploy/backup.sh
#
# Run nightly by inclamo-helpdesk-backup.timer, and by upgrade.sh before an
# upgrade. On the target, under BACKUP_S3_PREFIX:
#   backups/<UTC time>/database.dump.age
#   backups/<UTC time>/storage.tar.age      (local attachments only)
#   backups/<UTC time>/helpdesk.env.age
#   backups/<UTC time>/manifest.txt         (checksums; uploaded last)
set -euo pipefail
# shellcheck source=deploy/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ $# -eq 0 ] || die 'usage: deploy/backup.sh'
need_root
need_tools docker age curl sha256sum md5sum flock
need_env_file
prepare_directories
take_lock
load_target
ensure_network "$NETWORK"

stamp=$(now_stamp)
stage=$WORK_DIR/staging/$stamp
err=$WORK_DIR/backup.err
step='starting'

finish() {
  local status=$?
  trap - EXIT
  if [ "$status" -ne 0 ]; then
    warn "backup failed while $step: $(answer_of "$err")"
    alarm "Backup failed on $(instance_name) while $step (target: $(target_name)). Answer: $(answer_of "$err")"
  fi
  rm -rf "$WORK_DIR/staging" "$err"
  exit "$status"
}
trap finish EXIT

umask 077
mkdir -p "$stage"
: > "$err"

recipient=$(env_value BACKUP_AGE_RECIPIENT)
if [ -z "$recipient" ]; then
  step='reading BACKUP_AGE_RECIPIENT'
  echo 'BACKUP_AGE_RECIPIENT is not set in the environment file' > "$err"
  exit 1
fi

step='dumping the database'
dump_database 2>> "$err" | age --recipient "$recipient" --output "$stage/database.dump.age" 2>> "$err"
files=(database.dump.age)

if [ "$(env_value ACTIVE_STORAGE_SERVICE)" = local ]; then
  step='archiving the attachments'
  compose run --rm -T --no-deps rails 'exec tar -C /app/storage -cf - .' 2>> "$err" |
    age --recipient "$recipient" --output "$stage/storage.tar.age" 2>> "$err"
  files+=(storage.tar.age)
fi

step='encrypting the environment file'
age --recipient "$recipient" --output "$stage/helpdesk.env.age" "$ENV_FILE" 2>> "$err"
files+=(helpdesk.env.age)

step='computing the checksums'
for file in "${files[@]}"; do
  printf '%s %s %s %s\n' \
    "$(sha256sum < "$stage/$file" | cut -d ' ' -f 1)" \
    "$(md5sum < "$stage/$file" | cut -d ' ' -f 1)" \
    "$(wc -c < "$stage/$file" | tr -d ' ')" \
    "$file"
done > "$stage/manifest.txt"

step="uploading to the backup target"
for file in "${files[@]}" manifest.txt; do
  s3 copyto "/work/staging/$stamp/$file" "$(remote "backups/$stamp/$file")" >> "$err" 2>&1
done

step='checking the upload on the backup target'
s3 md5sum "$(remote "backups/$stamp")" > "$stage/remote.md5" 2>> "$err"
while read -r _ md5 _ file; do
  if ! awk -v sum="$md5" -v name="$file" '$1 == sum && $2 == name { found = 1 } END { exit !found }' "$stage/remote.md5"; then
    echo "$file on the target does not have the checksum of what was uploaded" >> "$err"
    exit 1
  fi
done < "$stage/manifest.txt"

step='applying the retention'
list_backups > "$stage/all" 2>> "$err"
retention_expired "$RETENTION_DAILY" "$RETENTION_WEEKLY" < "$stage/all" | { grep -v -x "$stamp" || true; } > "$stage/expired"
while read -r old; do
  s3 purge "$(remote "backups/$old")" >> "$err" 2>&1
done < "$stage/expired"

step='writing the status file'
now_iso > "$STATE_DIR/last-backup-at"
{
  printf '{\n    "name": "%s",\n    "objects": [' "$stamp"
  separator=''
  while read -r sha256 md5 size file; do
    printf '%s\n      {"key": "backups/%s/%s", "size": %s, "sha256": "%s", "md5": "%s"}' "$separator" "$stamp" "$file" "$size" "$sha256" "$md5"
    separator=','
  done < "$stage/manifest.txt"
  printf '\n    ]\n  }'
} > "$STATE_DIR/last-backup.json"
chmod 644 "$STATE_DIR/last-backup-at" "$STATE_DIR/last-backup.json"
write_status

say "backup $stamp is on the target ($(wc -l < "$stage/expired" | tr -d ' ') older removed by the retention)"
