#!/usr/bin/env bash
# Installs one production instance on a machine with Docker, from the
# published image.
#
#   sudo NAME=value ... deploy/install.sh --domain <domain> --mail-to <address> [--test]
#
# --domain    the instance's domain; it must already point at this machine
# --mail-to   where the test message goes, to prove that mail leaves
#
# Everything else is given as environment variables named as in
# deploy/env.template (with sudo: `sudo NAME=value ... deploy/install.sh ...`,
# or `sudo --preserve-env=NAME,...`):
#   mail      SMTP_ADDRESS, MAILER_SENDER_EMAIL, and as the server needs
#             SMTP_PORT, SMTP_USERNAME, SMTP_PASSWORD, SMTP_AUTHENTICATION, ...
#   backups   BACKUP_S3_ENDPOINT, BACKUP_S3_REGION, BACKUP_S3_BUCKET,
#             BACKUP_S3_ACCESS_KEY_ID, BACKUP_S3_SECRET_ACCESS_KEY,
#             BACKUP_AGE_RECIPIENT (the public key; the private one stays
#             outside this machine), optionally BACKUP_S3_PREFIX
#   alarm     ALERT_WEBHOOK_URL
#   files     ACTIVE_STORAGE_SERVICE=s3_compatible with STORAGE_BUCKET_NAME,
#             STORAGE_ACCESS_KEY_ID, STORAGE_SECRET_ACCESS_KEY, STORAGE_REGION,
#             STORAGE_ENDPOINT; or ACTIVE_STORAGE_SERVICE=local
#   image     HELPDESK_IMAGE, when it is not the release of this checkout
# A secret that is not in the environment is asked for without echo when the
# install runs at a terminal.
#
# What it does, in this order: checks that the domain points here (before any
# certificate can be asked for); proves the backup target with a test upload;
# draws the secrets once into /etc/inclamo-helpdesk/helpdesk.env (root only,
# never printed); prepares the database once, before the helpdesk starts;
# sends the test message; starts the stack; installs the timers; writes the
# first backup and runs the first restore test; waits for the health page.
# It stops, naming what failed, when mail or backups would fail silently. It
# never overwrites an environment file: on an installed machine it refuses.
# A run that fails removes what it made itself, so it can be run again.
#
# --test changes only what a CI runner cannot have (deploy/test/): the web
# server's internal authority instead of a public certificate, the addresses
# of the domain check taken from INSTALL_TEST_DOMAIN_ADDRESS and
# INSTALL_TEST_PUBLIC_ADDRESS, and an S3 server (keys INSTALL_TEST_S3_ACCESS_KEY
# and INSTALL_TEST_S3_SECRET_KEY), a mail catcher and an alarm receiver started
# beside the stack. Never for an instance with real customers.
set -euo pipefail
# shellcheck source=deploy/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage='usage: deploy/install.sh --domain <domain> --mail-to <address> [--test]'
domain=''
mail_to=''
test_mode=0
while [ $# -gt 0 ]; do
  case $1 in
    --domain) domain=${2:-}; shift 2 || die "$usage" ;;
    --mail-to) mail_to=${2:-}; shift 2 || die "$usage" ;;
    --test) test_mode=1; shift ;;
    *) die "$usage" ;;
  esac
done
[ -n "$domain" ] && [ -n "$mail_to" ] || die "$usage"
[[ $domain =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] || die "not a domain: $domain (give it without a scheme)"

need_root

if [ -e "$ENV_FILE" ]; then
  die "$ENV_FILE exists: this machine already has an instance. The install never overwrites it; nothing was changed. Use deploy/upgrade.sh to change the image."
fi

# --- tools -------------------------------------------------------------------

missing=''
for tool in age curl; do
  command -v "$tool" > /dev/null 2>&1 || missing="$missing $tool"
done
if [ -n "$missing" ]; then
  command -v apt-get > /dev/null 2>&1 || die "needed on this machine and not found:$missing"
  say "installing$missing"
  # shellcheck disable=SC2086
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $missing > /dev/null
fi
need_tools docker age curl sha256sum md5sum flock getent awk

# --- inputs ------------------------------------------------------------------

# What the operator gave for NAME, or nothing.
input() { printf '%s' "${!1:-}"; }

# A secret input: from the environment, else asked for without echo.
input_secret() {
  local name=$1 value=${!1:-}
  if [ -z "$value" ] && [ -t 0 ]; then
    read -r -s -p "$name: " value
    printf '\n' >&2
    printf -v "$name" '%s' "$value"
    export "${name?}"
  fi
}

SMTP_ADDRESS=$(input SMTP_ADDRESS)
MAILER_SENDER_EMAIL=$(input MAILER_SENDER_EMAIL)
if [ -z "$SMTP_ADDRESS" ] || [ -z "$MAILER_SENDER_EMAIL" ]; then
  die 'the mail settings are missing: SMTP_ADDRESS and MAILER_SENDER_EMAIL are needed. Without an SMTP server the helpdesk would lose its mail without a word, so it was not started.'
fi
[ -z "$(input SMTP_USERNAME)" ] || input_secret SMTP_PASSWORD

for name in BACKUP_S3_ENDPOINT BACKUP_S3_BUCKET BACKUP_S3_ACCESS_KEY_ID BACKUP_AGE_RECIPIENT; do
  [ -n "$(input "$name")" ] || die "the backup settings are missing: $name is needed. Nothing was started."
done
input_secret BACKUP_S3_SECRET_ACCESS_KEY
[ -n "$(input BACKUP_S3_SECRET_ACCESS_KEY)" ] || die 'the backup settings are missing: BACKUP_S3_SECRET_ACCESS_KEY is needed. Nothing was started.'
[[ $(input BACKUP_AGE_RECIPIENT) =~ ^age1[a-z0-9]+$ ]] || die 'BACKUP_AGE_RECIPIENT is not a public age key (age1...). The private key must not be given to this machine.'
BACKUP_S3_PREFIX=${BACKUP_S3_PREFIX:-helpdesk}
export BACKUP_S3_PREFIX

[ -n "$(input ALERT_WEBHOOK_URL)" ] || die 'ALERT_WEBHOOK_URL is needed: without it a failed backup would reach nobody. Nothing was started.'

case $(input ACTIVE_STORAGE_SERVICE) in
  local) ;;
  s3_compatible)
    for name in STORAGE_BUCKET_NAME STORAGE_ACCESS_KEY_ID STORAGE_REGION STORAGE_ENDPOINT; do
      [ -n "$(input "$name")" ] || die "the attachment storage is incomplete: $name is needed with ACTIVE_STORAGE_SERVICE=s3_compatible. Nothing was started."
    done
    input_secret STORAGE_SECRET_ACCESS_KEY
    [ -n "$(input STORAGE_SECRET_ACCESS_KEY)" ] || die 'the attachment storage is incomplete: STORAGE_SECRET_ACCESS_KEY is needed. Nothing was started.'
    ;;
  *) die 'ACTIVE_STORAGE_SERVICE must be s3_compatible (object storage) or local (a volume on this machine, carried by the nightly backup). Nothing was started.' ;;
esac

image=$(input HELPDESK_IMAGE)
if [ -z "$image" ]; then
  # The release this checkout belongs to.
  overlay=$(cat "$DEPLOY_DIR/../custom/INCLAMO_VERSION" 2> /dev/null) || die 'HELPDESK_IMAGE is needed: this copy of deploy/ has no custom/INCLAMO_VERSION beside it'
  chatwoot=$(cat "$DEPLOY_DIR/../custom/CHATWOOT_VERSION" 2> /dev/null) || die 'HELPDESK_IMAGE is needed: this copy of deploy/ has no custom/CHATWOOT_VERSION beside it'
  image="ghcr.io/aceverseco/inclamo-helpdesk:$overlay-cw${chatwoot#v}"
fi

# --- an empty installation ---------------------------------------------------

existing=$(stack_volumes)
[ -z "$existing" ] || die "volumes of the stack exist on this machine ($(printf '%s' "$existing" | tr '\n' ' ')) without an environment file: their data cannot be read with new secrets. Restore with deploy/restore.sh, or remove them yourself. Nothing was changed."

# --- the domain points here ----------------------------------------------------

if [ "$test_mode" = 1 ]; then
  warn 'TEST MODE: internal certificate authority, given addresses, test services. Not for real customers.'
  resolved=$(input INSTALL_TEST_DOMAIN_ADDRESS)
  here=$(input INSTALL_TEST_PUBLIC_ADDRESS)
  [ -n "$resolved" ] && [ -n "$here" ] || die 'test mode needs INSTALL_TEST_DOMAIN_ADDRESS and INSTALL_TEST_PUBLIC_ADDRESS'
else
  need_tools ip
  resolved=$(getent ahosts "$domain" | awk '{ print $1 }' | sort -u) || true
  here=$(ip -o addr show scope global | awk '{ split($4, address, "/"); print address[1] }' | sort -u)
fi
[ -n "$resolved" ] || die "the domain $domain does not resolve to any address. No certificate was requested and nothing was started."
elsewhere=''
for address in $resolved; do
  printf '%s\n' "$here" | grep -q -x -F "$address" || elsewhere="$elsewhere $address"
done
if [ -n "$elsewhere" ]; then
  die "the domain $domain resolves to$elsewhere, which is not an address of this machine ($(printf '%s' "$here" | tr '\n' ' ')). No certificate was requested and nothing was started."
fi

# --- from here on a failure removes what this run made -----------------------

prepare_directories
take_lock
ensure_network "$NETWORK"
log=$WORK_DIR/install.log
( umask 077; : > "$log" )
made=0
finished=0

test_services() {
  HELPDESK_NETWORK=$NETWORK docker compose --project-name "$PROJECT-test-services" -f "$DEPLOY_DIR/test/docker-compose.yaml" "$@"
}

finish() {
  local status=$?
  trap - EXIT
  if [ "$status" -ne 0 ] && [ "$finished" = 0 ]; then
    if [ "$made" = 1 ]; then
      warn 'the install did not finish: removing what this run made (containers, volumes, the environment file), so it can be run again'
      compose down --volumes --remove-orphans > /dev/null 2>&1 || true
      rm -f "$ENV_FILE"
    fi
    [ "$test_mode" = 0 ] || test_services down --volumes > /dev/null 2>&1 || true
  fi
  rm -f "$log"
  exit "$status"
}
trap finish EXIT

# What a failed step wrote, without secrets.
log_tail() { tail -n 12 "$log" | scrub >&2; }

if [ "$test_mode" = 1 ]; then
  say 'starting the test services (S3 server, mail catcher, alarm receiver)'
  # The keys the test S3 server is started with; a test of a refused upload
  # gives the install other keys than these.
  [ -n "$(input INSTALL_TEST_S3_ACCESS_KEY)" ] && [ -n "$(input INSTALL_TEST_S3_SECRET_KEY)" ] || die 'test mode needs INSTALL_TEST_S3_ACCESS_KEY and INSTALL_TEST_S3_SECRET_KEY'
  export INSTALL_TEST_S3_ACCESS_KEY INSTALL_TEST_S3_SECRET_KEY
  test_services up -d --wait >> "$log" 2>&1 || { log_tail; die 'the test services did not start'; }
fi

# --- the backup target takes an upload ---------------------------------------

load_target
if [ "$test_mode" = 1 ]; then
  # The test S3 server starts empty: make its buckets with the keys it was
  # started with (asking the server, which the client otherwise skips). The
  # server may still be starting, so the first tries may fail.
  made_buckets=0
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if ( T_ACCESS_KEY_ID=$INSTALL_TEST_S3_ACCESS_KEY && T_SECRET_ACCESS_KEY=$INSTALL_TEST_S3_SECRET_KEY && export S3_NO_CHECK_BUCKET=false &&
      s3 mkdir "target:$T_BUCKET" >> "$log" 2>&1 &&
      { [ -z "$(input STORAGE_BUCKET_NAME)" ] || s3 mkdir "target:$(input STORAGE_BUCKET_NAME)" >> "$log" 2>&1; } ); then
      made_buckets=1
      break
    fi
    sleep 3
  done
  [ "$made_buckets" = 1 ] || { log_tail; die 'the buckets of the test S3 server could not be made'; }
fi

say 'checking the backup target with a test upload'
check=install-check-$(now_stamp).age
( umask 077; mkdir -p "$WORK_DIR/staging" )
if ! printf 'Inclamo Helpdesk install check\n' | age --recipient "$(input BACKUP_AGE_RECIPIENT)" --output "$WORK_DIR/staging/$check" 2>> "$log"; then
  log_tail
  die 'BACKUP_AGE_RECIPIENT was refused by age: nothing could be encrypted to it. Nothing was started.'
fi
: > "$WORK_DIR/install-target.err"
if ! s3 copyto "/work/staging/$check" "$(remote "$check")" > "$WORK_DIR/install-target.err" 2>&1; then
  answer=$(answer_of "$WORK_DIR/install-target.err")
  rm -rf "$WORK_DIR/staging" "$WORK_DIR/install-target.err"
  die "the backup target ($(target_name)) refused the test upload. Its answer: $answer. Nothing was started."
fi
s3 deletefile "$(remote "$check")" >> "$log" 2>&1 || warn "the test object $check could not be removed from the backup target; remove it by hand"
rm -rf "$WORK_DIR/staging" "$WORK_DIR/install-target.err"

# --- the image, pinned by tag and digest -------------------------------------

say "pulling ${image%%@*}"
docker pull --quiet "$image" > /dev/null 2>> "$log" || { log_tail; die "the image $image could not be pulled. Nothing was started."; }
case $image in
  *@sha256:*) ;;
  *)
    repository=$image
    case ${repository##*/} in *:*) repository=${repository%:*} ;; esac
    digest=$(docker image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$image" | sed -n "s|^$repository@||p" | head -n 1)
    [ -n "$digest" ] || die "the registry gave no digest for $image, so it cannot be pinned. Nothing was started."
    image="$image@$digest"
    ;;
esac

# --- the environment file, once ----------------------------------------------

random() { od -An -N"$1" -tx1 /dev/urandom | tr -d ' \n'; }

# The value of one name of the template: a secret drawn here, a value this
# install derives, what the operator gave, or the template's own.
value_for() {
  case $1 in
    SECRET_KEY_BASE) random 64 ;;
    ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY | ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY | ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT) random 32 ;;
    POSTGRES_PASSWORD | REDIS_PASSWORD) random 24 ;;
    HELPDESK_DOMAIN) printf '%s' "$domain" ;;
    HELPDESK_IMAGE) printf '%s' "$image" ;;
    FRONTEND_URL) printf 'https://%s' "$domain" ;;
    HELPDESK_CADDY_FLAGS) [ "$test_mode" = 0 ] || printf '%s' '--internal-certs' ;;
    *) if [ -n "${!1:-}" ]; then printf '%s' "${!1}"; else printf '%s' "$2"; fi ;;
  esac
}

say "writing $ENV_FILE (root only; its secrets are drawn here and shown nowhere)"
made=1
(
  umask 077
  next=$(mktemp "$ENV_FILE.XXXXXX")
  # Every `NAME=value` and optional `# NAME=value` line of the template, in its order.
  sed -n -E 's/^(# )?([A-Z][A-Z0-9_]*)=(.*)$/\2|\1|\3/p' "$DEPLOY_DIR/env.template" |
    while IFS='|' read -r name optional default; do
      case $name in
        FORCE_SSL | ENABLE_ACCOUNT_SIGNUP | DISABLE_TELEMETRY | ENABLE_PUSH_RELAY_SERVER | RAILS_LOG_TO_STDOUT | POSTGRES_HOST | POSTGRES_USERNAME | POSTGRES_DATABASE | REDIS_URL)
          value=$default ;;
        *) value=$(value_for "$name" "$default") ;;
      esac
      # An optional line the operator left out is left out of the file.
      if [ -z "$value" ] && [ -n "$optional" ]; then continue; fi
      env_line "$name" "$value"
    done > "$next"
  mv -f "$next" "$ENV_FILE"
)
chmod 600 "$ENV_FILE"
for name in SECRET_KEY_BASE ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT POSTGRES_PASSWORD REDIS_PASSWORD HELPDESK_DOMAIN HELPDESK_IMAGE FRONTEND_URL; do
  [ -n "$(env_value "$name")" ] || die "the environment file could not be written: $name is empty"
done

# --- the database, once, before the helpdesk starts --------------------------

say 'starting Postgres and Redis'
compose pull --quiet postgres redis caddy >> "$log" 2>&1 || { log_tail; die 'the images of the stack could not be pulled'; }
compose up -d --wait postgres redis >> "$log" 2>&1 || { log_tail; die 'Postgres and Redis did not start'; }

say 'preparing the database (schema, seeds, migrations of Chatwoot and of the overlay)'
prepare_database >> "$log" 2>&1 || { log_tail; die 'the database could not be prepared'; }

# --- mail leaves -------------------------------------------------------------

say "sending the test message to $mail_to"
export INSTALL_MAIL_TO=$mail_to
mail=$(compose run --rm -T --no-deps -e INSTALL_MAIL_TO rails 'exec bundle exec rails runner -' 2>> "$log" <<'RUBY'
begin
  ActionMailer::Base.mail(
    from: ENV.fetch('MAILER_SENDER_EMAIL'),
    to: ENV.fetch('INSTALL_MAIL_TO'),
    subject: 'Inclamo Helpdesk: test message of the installation',
    body: "This message proves that the helpdesk at #{ENV.fetch('FRONTEND_URL')} can send mail."
  ).deliver_now
  puts 'INSTALL_MAIL_OK'
rescue StandardError => e
  puts "INSTALL_MAIL_FAILED #{e.class}: #{e.message}"
  exit 1
end
RUBY
) || true
case $mail in
  *INSTALL_MAIL_OK*) ;;
  *)
    answer=$(printf '%s\n' "$mail" | sed -n 's/.*INSTALL_MAIL_FAILED //p' | tail -n 1 | scrub)
    [ -n "$answer" ] || { log_tail; answer='the helpdesk could not run the mailer (see above)'; }
    die "the mail server $SMTP_ADDRESS refused the test message. Its answer: $answer"
    ;;
esac

# --- start, first backup, first restore test, health -------------------------

say 'starting the helpdesk, its workers and the web server'
compose up -d >> "$log" 2>&1 || { log_tail; die 'the stack did not start'; }

finish_first_start
finished=1

say "installed: https://$domain"
say 'open it now to create the first administrator and the account; sign-up stays closed'
