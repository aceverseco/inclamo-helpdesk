# shellcheck shell=bash
# Shared by the scripts of deploy/. Sourced, never run.
#
# Rules every script here keeps: tracing is never switched on, no secret is
# written to the output or passed as an argument of a command, and a value of
# the environment file is read by name, one at a time, never by sourcing it.

set -euo pipefail
case $- in *x*) set +x ;; esac

say() { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }
die() { warn "$*"; exit 1; }

DEPLOY_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly DEPLOY_DIR
# Where an instance lives. The install tests (e2e/install-run.sh) may move it,
# so that a run on a machine that already serves something else writes nothing
# to these places: INSTALL_TEST_ROOT (an absolute directory) takes the
# environment file, the state and the work directory, and no systemd timer is
# installed; INSTALL_TEST_PROJECT names the Compose project and its network;
# INSTALL_TEST_HTTP_PORT and INSTALL_TEST_HTTPS_PORT are the ports the web
# server publishes (deploy/docker-compose.yaml). Never set on a real instance.
if [ -n "${INSTALL_TEST_ROOT:-}" ]; then
  case $INSTALL_TEST_ROOT in
    /*) ;;
    *) die 'INSTALL_TEST_ROOT must be an absolute directory' ;;
  esac
  readonly ENV_FILE=$INSTALL_TEST_ROOT/etc/helpdesk.env
  readonly STATE_DIR=$INSTALL_TEST_ROOT/state
  # Root only: staging of encrypted backups, the dump of a restore test, the
  # pre-upgrade dump. Never mounted into the helpdesk.
  readonly WORK_DIR=$INSTALL_TEST_ROOT/work
else
  readonly ENV_FILE=/etc/inclamo-helpdesk/helpdesk.env
  readonly STATE_DIR=/var/lib/inclamo-helpdesk
  readonly WORK_DIR=/var/backups/inclamo-helpdesk
fi
readonly STATUS_FILE=$STATE_DIR/backup-status.json
readonly PROJECT=${INSTALL_TEST_PROJECT:-inclamo-helpdesk}
readonly NETWORK=$PROJECT
readonly TEST_PROJECT=$PROJECT-restore-test
# The S3 client the scripts run in a container.
readonly RCLONE_IMAGE=rclone/rclone:1.76.0@sha256:7cbeec24a44f206067597c0368be4de90ae19a64d5113c7d1938bd737a81e466
# Kept: the newest backup of each of the last DAILY days and WEEKLY weeks.
readonly RETENTION_DAILY=14
readonly RETENTION_WEEKLY=8
# Values that must never reach the output, a log or the alarm.
readonly SECRET_NAMES='SECRET_KEY_BASE ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT POSTGRES_PASSWORD REDIS_PASSWORD SMTP_PASSWORD STORAGE_SECRET_ACCESS_KEY BACKUP_S3_SECRET_ACCESS_KEY ALERT_WEBHOOK_URL'

need_root() {
  [ "$(id -u)" = 0 ] || die "run this as root (sudo): it reads $ENV_FILE and drives Docker"
}

need_tools() {
  local tool
  for tool in "$@"; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is needed on this machine and was not found"
  done
  docker compose version >/dev/null 2>&1 || die 'Docker Compose v2 (docker compose) is needed on this machine'
}

need_env_file() {
  [ -f "$ENV_FILE" ] || die "$ENV_FILE does not exist: this machine has no installed instance (deploy/install.sh or deploy/restore.sh)"
}

# The value of NAME in the environment file, or nothing. The file holds
# NAME=value lines; a value with characters a shell or Compose would read
# specially is kept between single quotes.
env_value() {
  local line=''
  line=$(grep -E "^$1=" "$ENV_FILE" 2>/dev/null | tail -n 1) || true
  line=${line#*=}
  case $line in
    \'*\') line=${line#\'}; line=${line%\'} ;;
  esac
  printf '%s' "$line"
}

# One line of the environment file for NAME and a value.
env_line() {
  local name=$1 value=$2
  case $value in
    *"'"* | *$'\n'*) die "$name holds a single quote or a line break, which the environment file cannot carry" ;;
  esac
  if [[ $value =~ ^[A-Za-z0-9_.:/@%+=,-]*$ ]]; then
    printf '%s=%s\n' "$name" "$value"
  else
    printf "%s='%s'\n" "$name" "$value"
  fi
}

# Replaces the line of NAME in the environment file, keeping the file root
# only. Used for HELPDESK_IMAGE alone, by the upgrade.
set_env_value() {
  local name=$1 value=$2 next
  next=$(mktemp "$ENV_FILE.XXXXXX")
  chmod 600 "$next"
  grep -v -E "^$name=" "$ENV_FILE" > "$next" || true
  env_line "$name" "$value" >> "$next"
  mv -f "$next" "$ENV_FILE"
}

# Standard input with every secret of this instance replaced by ***.
scrub() {
  local text name secret
  text=$(cat)
  for name in $SECRET_NAMES; do
    secret=$(env_value "$name")
    [ -n "$secret" ] && text=${text//"$secret"/***}
    secret=${!name:-}
    [ -n "$secret" ] && text=${text//"$secret"/***}
  done
  printf '%s\n' "$text"
}

# The stack's compose file as project $1 on network $2. The places of the
# environment file and of the state directory reach the file by name, so the
# install tests can move them.
compose_in() {
  local project=$1 network=$2
  shift 2
  INSTALL_TEST_ENV_FILE=$ENV_FILE INSTALL_TEST_STATE_DIR=$STATE_DIR HELPDESK_NETWORK=$network \
    docker compose --project-name "$project" --env-file "$ENV_FILE" -f "$DEPLOY_DIR/docker-compose.yaml" "$@"
}

compose() {
  compose_in "$PROJECT" "$NETWORK" "$@"
}

ensure_network() {
  docker network inspect "$1" >/dev/null 2>&1 || docker network create "$1" >/dev/null
}

prepare_directories() {
  ( umask 077; mkdir -p "$WORK_DIR" "$(dirname "$ENV_FILE")" )
  chmod 700 "$WORK_DIR" "$(dirname "$ENV_FILE")"
  mkdir -p "$STATE_DIR"
  chmod 755 "$STATE_DIR"
}

# One maintenance script at a time. A script started by another one (the
# upgrade runs the backup and the restore test) works under its lock.
take_lock() {
  [ "${INCLAMO_HELPDESK_LOCKED:-}" = 1 ] && return 0
  exec 9> "$WORK_DIR/.lock"
  flock -n 9 || die 'another maintenance script of the helpdesk is running on this machine'
  export INCLAMO_HELPDESK_LOCKED=1
}

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
now_stamp() { date -u +%Y%m%dT%H%M%SZ; }

# --- alarm -----------------------------------------------------------------

json_escape() {
  tr -d '\000-\010\013-\037' | awk 'BEGIN { ORS = "\\n" } { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, " "); print }' | sed 's/\\n$//'
}

# Posts one message to the operator's chat. The address is a secret: it goes
# to curl on standard input, not as an argument. Never fails the caller.
alarm() {
  local url text
  url=$(env_value ALERT_WEBHOOK_URL)
  [ -n "$url" ] || url=${ALERT_WEBHOOK_URL:-}
  if [ -z "$url" ]; then warn 'no alarm webhook is configured: the alarm was not sent'; return 0; fi
  text=$(printf '%s' "$1" | scrub | cut -c 1-1500 | json_escape)
  printf 'url = "%s"\n' "$url" |
    curl --silent --show-error --fail --max-time 20 --output /dev/null \
      --header 'Content-Type: application/json' --data "{\"text\":\"$text\"}" --config - 2>/dev/null ||
    warn 'the alarm could not be delivered to the webhook'
}

instance_name() {
  local name
  name=$(env_value HELPDESK_DOMAIN)
  printf '%s' "${name:-$(hostname)}"
}

# --- health ----------------------------------------------------------------

# Asks the helpdesk's own health page inside the stack. Prints the answer and
# succeeds on 200. Rails redirects plain HTTP, so the request says it came by
# HTTPS, as the web server does.
health_probe() {
  compose exec -T rails ruby -rnet/http -e '
    answer = Net::HTTP.start("127.0.0.1", 3000, open_timeout: 5, read_timeout: 20) do |http|
      http.get("/inclamo/health", "X-Forwarded-Proto" => "https")
    end
    puts answer.body
    exit(answer.code == "200" ? 0 : 1)' 2>/dev/null
}

# Polls the health page for $1 seconds. On failure the last answer (the names
# of the failing checks) goes to the error output.
wait_healthy() {
  local deadline=$((SECONDS + $1)) answer=''
  while :; do
    if answer=$(health_probe); then return 0; fi
    [ "$SECONDS" -lt "$deadline" ] || break
    sleep 5
  done
  warn "the helpdesk is not healthy: ${answer:-no answer from /inclamo/health}"
  return 1
}

# --- status file -----------------------------------------------------------

# The health page reads last_backup_at and last_restore_test_at; last_backup
# names the objects of the last backup with their checksums, which the restore
# test compares with the target. Replaced by a rename, so a reader never sees
# half a file.
write_status() {
  local backup_at='' test_at='' objects='null' next
  [ -f "$STATE_DIR/last-backup-at" ] && backup_at=$(cat "$STATE_DIR/last-backup-at")
  [ -f "$STATE_DIR/last-restore-test-at" ] && test_at=$(cat "$STATE_DIR/last-restore-test-at")
  [ -f "$STATE_DIR/last-backup.json" ] && objects=$(cat "$STATE_DIR/last-backup.json")
  next=$(mktemp "$STATUS_FILE.XXXXXX")
  {
    printf '{\n'
    if [ -n "$backup_at" ]; then printf '  "last_backup_at": "%s",\n' "$backup_at"; else printf '  "last_backup_at": null,\n'; fi
    if [ -n "$test_at" ]; then printf '  "last_restore_test_at": "%s",\n' "$test_at"; else printf '  "last_restore_test_at": null,\n'; fi
    printf '  "last_backup": %s\n}\n' "$objects"
  } > "$next"
  chmod 644 "$next"
  mv -f "$next" "$STATUS_FILE"
}

# --- backup target ---------------------------------------------------------

# The target's settings, from the environment file when the instance has one,
# else from the environment the script was started with (install, restore).
load_target() {
  local name value
  for name in BACKUP_S3_ENDPOINT BACKUP_S3_REGION BACKUP_S3_BUCKET BACKUP_S3_ACCESS_KEY_ID BACKUP_S3_SECRET_ACCESS_KEY BACKUP_S3_PREFIX BACKUP_S3_FORCE_PATH_STYLE; do
    value=''
    [ -f "$ENV_FILE" ] && value=$(env_value "$name")
    [ -n "$value" ] || value=${!name:-}
    printf -v "T_${name#BACKUP_S3_}" '%s' "$value"
  done
  for name in BACKUP_S3_ENDPOINT BACKUP_S3_BUCKET BACKUP_S3_ACCESS_KEY_ID BACKUP_S3_SECRET_ACCESS_KEY; do
    value="T_${name#BACKUP_S3_}"
    [ -n "${!value}" ] || die "the backup target is incomplete: $name is not set"
  done
}

target_name() { printf '%s, bucket %s' "$T_ENDPOINT" "$T_BUCKET"; }

# Where a path of the backup folder lives on the target.
remote() { printf 'target:%s/%s%s' "$T_BUCKET" "${T_PREFIX:+$T_PREFIX/}" "$1"; }

# The S3 client, in a container on the stack's network, with $WORK_DIR as
# /work. The credentials reach it through the environment, never as arguments.
s3() {
  RCLONE_CONFIG_TARGET_TYPE=s3 \
  RCLONE_CONFIG_TARGET_PROVIDER=Other \
  RCLONE_CONFIG_TARGET_ENDPOINT=$T_ENDPOINT \
  RCLONE_CONFIG_TARGET_REGION=${T_REGION:-} \
  RCLONE_CONFIG_TARGET_ACCESS_KEY_ID=$T_ACCESS_KEY_ID \
  RCLONE_CONFIG_TARGET_SECRET_ACCESS_KEY=$T_SECRET_ACCESS_KEY \
  RCLONE_CONFIG_TARGET_FORCE_PATH_STYLE=${T_FORCE_PATH_STYLE:-false} \
  RCLONE_S3_NO_CHECK_BUCKET=${S3_NO_CHECK_BUCKET:-true} \
  RCLONE_S3_UPLOAD_CUTOFF=5Gi \
    docker run --rm --network "$NETWORK" \
      -e RCLONE_CONFIG_TARGET_TYPE -e RCLONE_CONFIG_TARGET_PROVIDER -e RCLONE_CONFIG_TARGET_ENDPOINT \
      -e RCLONE_CONFIG_TARGET_REGION -e RCLONE_CONFIG_TARGET_ACCESS_KEY_ID -e RCLONE_CONFIG_TARGET_SECRET_ACCESS_KEY \
      -e RCLONE_CONFIG_TARGET_FORCE_PATH_STYLE -e RCLONE_S3_NO_CHECK_BUCKET -e RCLONE_S3_UPLOAD_CUTOFF \
      -v "$WORK_DIR:/work" "$RCLONE_IMAGE" --retries 3 --low-level-retries 3 "$@"
}

# The last lines a failed command wrote, on one line, without secrets and
# without the S3 client's note that it has no configuration file.
answer_of() {
  [ -s "$1" ] || { printf 'no answer'; return 0; }
  { grep -v 'Config file .* not found - using defaults' "$1" || true; } | tail -n 2 | scrub | tr '\n' ' ' | cut -c 1-600
}

# Names of the finished backups on the target, one per line. A backup is
# finished when its manifest, uploaded last, is there.
list_backups() {
  s3 lsf --files-only --recursive --include '/*/manifest.txt' "$(remote backups)" |
    sed -n 's|^\([0-9]\{8\}T[0-9]\{6\}Z\)/manifest\.txt$|\1|p' | sort
}

# Reads backup names (YYYYMMDDTHHMMSSZ) and prints those the retention lets
# go: everything but the newest backup of each of the last $1 days and of each
# of the last $2 weeks (Monday to Sunday) that have a backup.
retention_expired() {
  sort -r | awk -v daily="$1" -v weekly="$2" '
    function days(y, m, d,    era, yoe, doy) {   # days since 1970-01-01
      if (m <= 2) y -= 1
      era = int((y >= 0 ? y : y - 399) / 400); yoe = y - era * 400
      doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
      return era * 146097 + yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy - 719468
    }
    length($0) == 16 && /^[0-9]+T[0-9]+Z$/ {
      day = substr($0, 1, 8)
      n = days(substr($0, 1, 4) + 0, substr($0, 5, 2) + 0, substr($0, 7, 2) + 0)
      week = int((n + 3) / 7)             # 1970-01-01 was a Thursday
      keep = 0
      if (!(day in seen_day) && day_count < daily) { seen_day[day] = 1; day_count++; keep = 1 }
      if (!(week in seen_week) && week_count < weekly) { seen_week[week] = 1; week_count++; keep = 1 }
      if (!keep) print
    }'
}

# --- database --------------------------------------------------------------

# The one dump command: the nightly backup, the restore test and the upgrade
# all use it.
dump_database() {
  compose exec -T postgres pg_dump --format=custom --username=postgres --dbname="$(env_value POSTGRES_DATABASE)"
}

# Brings Chatwoot's and the overlay's tables up to date, from one container.
# On an empty database it loads the schema and the seeds first.
prepare_database() {
  compose run --rm -T --no-deps rails 'exec bundle exec rails db:chatwoot_prepare'
}

# --- timers ----------------------------------------------------------------

# Installs the nightly backup and the monthly restore test as systemd timers
# pointing at this checkout of deploy/.
install_timers() {
  local unit
  if [ -n "${INSTALL_TEST_ROOT:-}" ]; then
    warn 'TEST MODE: INSTALL_TEST_ROOT is set, so the backup and restore-test timers are not installed'
    return 0
  fi
  command -v systemctl >/dev/null 2>&1 || die 'systemd is needed for the nightly backup and the monthly restore test, and systemctl was not found'
  for unit in inclamo-helpdesk-backup.service inclamo-helpdesk-backup.timer inclamo-helpdesk-restore-test.service inclamo-helpdesk-restore-test.timer; do
    sed "s|@DEPLOY_DIR@|$DEPLOY_DIR|g" "$DEPLOY_DIR/systemd/$unit" > "/etc/systemd/system/$unit"
    chmod 644 "/etc/systemd/system/$unit"
  done
  systemctl daemon-reload
  systemctl enable --now inclamo-helpdesk-backup.timer inclamo-helpdesk-restore-test.timer >/dev/null 2>&1 ||
    die 'the backup and restore-test timers could not be enabled'
}

# --- first start -----------------------------------------------------------

# How an install and a restore end: the timers, a first real backup and a
# first restore test (the health page fails without a recent one of each),
# then the health page must answer 200.
finish_first_start() {
  install_timers
  say 'writing the first backup'
  "$DEPLOY_DIR/backup.sh"
  say 'running the first restore test'
  "$DEPLOY_DIR/restore-test.sh"
  say 'waiting for the helpdesk to be healthy'
  wait_healthy 300
}

# Volumes of the stack that exist on this machine, one per line.
stack_volumes() {
  docker volume ls --quiet --filter "label=com.docker.compose.project=$PROJECT"
}
