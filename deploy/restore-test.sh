#!/usr/bin/env bash
# Proves that the instance can be restored, without the restore key: makes a
# fresh dump with the command the backup uses, restores it into a throwaway
# stack on this machine (its own project, network and volumes, no published
# port, no workers), and checks that
#   - the users, conversations and attachments counts match the source,
#   - every store connection decrypts and a working one reads its store,
#   - the objects of the last backup are on the target with the checksums the
#     backup recorded.
# Success is written to the status file the health page reads; a failure posts
# to the alarm webhook. The throwaway stack is removed either way.
#
#   sudo deploy/restore-test.sh
#
# Run monthly by inclamo-helpdesk-restore-test.timer and by upgrade.sh. The
# full path (download, decrypt with the restore key, restore) is restore.sh.
set -euo pipefail
# shellcheck source=deploy/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ $# -eq 0 ] || die 'usage: deploy/restore-test.sh'
need_root
need_tools docker curl flock
need_env_file
prepare_directories
take_lock
load_target

work=$WORK_DIR/restore-test
err=$WORK_DIR/restore-test.err
database=$(env_value POSTGRES_DATABASE)
step='starting'

# The same compose file as the instance, as another project on another
# network: nothing of the running stack is touched, and `caddy` is never
# started, so nothing is published.
throwaway() {
  compose_in "$TEST_PROJECT" "$TEST_PROJECT" "$@"
}

remove_throwaway() {
  throwaway down --volumes --remove-orphans > /dev/null 2>&1 || true
  docker network rm "$TEST_PROJECT" > /dev/null 2>&1 || true
  rm -rf "$work"
}

finish() {
  local status=$?
  trap - EXIT
  if [ "$status" -ne 0 ]; then
    warn "restore test failed while $step: $(answer_of "$err")"
    alarm "Restore test failed on $(instance_name) while $step. Answer: $(answer_of "$err")"
  fi
  remove_throwaway
  rm -f "$err"
  exit "$status"
}
trap finish EXIT

counts() {
  "$@" exec -T postgres psql --no-align --tuples-only --field-separator ' ' --username=postgres --dbname="$database" \
    --command 'SELECT (SELECT count(*) FROM users), (SELECT count(*) FROM conversations), (SELECT count(*) FROM attachments)'
}

umask 077
remove_throwaway
mkdir -p "$work"
: > "$err"

# The source keeps serving while it is dumped, so a count may move meanwhile:
# the restored count must lie between the counts taken before and after.
step='dumping the database'
read -r -a before <<< "$(counts compose 2>> "$err")"
dump_database > "$work/database.dump" 2>> "$err"
read -r -a after <<< "$(counts compose 2>> "$err")"

step='starting the throwaway stack'
ensure_network "$TEST_PROJECT"
throwaway up -d --wait postgres redis >> "$err" 2>&1

step='restoring the dump into the throwaway stack'
throwaway exec -T postgres pg_restore --no-owner --exit-on-error --username=postgres --dbname="$database" < "$work/database.dump" >> "$err" 2>&1

step='comparing the counts with the source'
read -r -a restored <<< "$(counts throwaway 2>> "$err")"
names=(users conversations attachments)
for index in 0 1 2; do
  low=${before[$index]}; high=${after[$index]}; got=${restored[$index]:-missing}
  if [ "$low" -gt "$high" ]; then low=${after[$index]}; high=${before[$index]}; fi
  if ! [[ $got =~ ^[0-9]+$ ]] || [ "$got" -lt "$low" ] || [ "$got" -gt "$high" ]; then
    echo "the restored ${names[$index]} do not match the source" >> "$err"
    exit 1
  fi
done

step='reading the store connection from the restored database'
store=$(throwaway run --rm -T --no-deps rails 'exec bundle exec rails runner -' 2>> "$err" <<'RUBY'
begin
  Inclamo::ShopifyConnection.find_each do |connection|
    # Raises when the keys of the environment file cannot decrypt the record.
    connection.client_secret
    connection.access_token
    next if connection.broken?

    Inclamo::Shopify::StoreConnection.new(connection).recheck!
  end
  puts 'RESTORE_TEST_STORE_OK'
rescue StandardError => e
  # The class only: a message may carry an address or a credential.
  puts "RESTORE_TEST_STORE_FAILED #{e.class}"
  exit 1
end
RUBY
) || true
case $store in
  *RESTORE_TEST_STORE_OK*) ;;
  *)
    echo "the store connection could not be read after the restore: $(printf '%s' "$store" | sed -n 's/.*RESTORE_TEST_STORE_FAILED //p' | tail -n 1)" >> "$err"
    exit 1
    ;;
esac

step='checking the last backup on the backup target'
if [ ! -f "$STATE_DIR/last-backup.json" ]; then
  echo 'no backup has been recorded on this machine yet: run deploy/backup.sh first' >> "$err"
  exit 1
fi
last=$(sed -n 's/.*"name": "\([^"]*\)".*/\1/p' "$STATE_DIR/last-backup.json" | head -n 1)
s3 md5sum "$(remote "backups/$last")" > "$work/remote.md5" 2>> "$err"
sed -n 's/.*"key": "backups\/[^"\/]*\/\([^"]*\)".*"md5": "\([^"]*\)".*/\2 \1/p' "$STATE_DIR/last-backup.json" > "$work/recorded.md5"
[ -s "$work/recorded.md5" ] || { echo 'the status of the last backup names no object' >> "$err"; exit 1; }
while read -r md5 file; do
  if ! awk -v sum="$md5" -v name="$file" '$1 == sum && $2 == name { found = 1 } END { exit !found }' "$work/remote.md5"; then
    echo "$file of backup $last is missing on the target or its checksum differs" >> "$err"
    exit 1
  fi
done < "$work/recorded.md5"

step='writing the status file'
now_iso > "$STATE_DIR/last-restore-test-at"
chmod 644 "$STATE_DIR/last-restore-test-at"
write_status

say "restore test passed: counts match, the store connection reads, backup $last is on the target"
