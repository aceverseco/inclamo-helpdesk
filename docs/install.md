# Installing and running an instance

For the operator of one production instance of the helpdesk on one machine:
how to install it from the published image, what the first visit does, where
mail, attachments and backups go, how to restore, upgrade and roll back, how
its health is watched, and what to check on every new machine.

Everything here is done by the scripts in `deploy/`. They are run as root, on
the machine, from a checkout of this repository at the release you install.
The behavior they keep is written down in
[the behavior contract](behavior/instance-installation/spec.md), and the
install tests (`e2e/install-run.sh`) run every scenario of it against a
throwaway instance.

| Script | What it does |
| --- | --- |
| `deploy/harden.sh` | closes the machine: ssh keys only, firewall, security updates, bounded logs |
| `deploy/install.sh` | installs the instance, once |
| `deploy/backup.sh` | backs up off the machine; run every night by a timer |
| `deploy/restore-test.sh` | proves a restore on a throwaway stack; run every month by a timer and after an upgrade |
| `deploy/restore.sh` | rebuilds the instance on an empty machine from a backup and the restore key |
| `deploy/upgrade.sh <tag>` | moves the instance to another release, and back when it fails |

## The machine

- Debian or Ubuntu with systemd, Docker Engine and the Compose plugin
  (`docker compose version` answers). `deploy/harden.sh` knows `apt-get` only.
- A public address, and a domain whose DNS record points at it **before** the
  install: the install compares them and asks for no certificate otherwise.
- Ports 80 and 443 free. Nothing else of the stack is published: the database
  and Redis are reachable from inside the stack only.
- A user that signs in with an ssh key and may use `sudo`.
- `age` and `curl`; the install installs them with `apt-get` when they are
  missing.
- Size: not recommended here yet. The smallest machine that runs the stack
  comfortably is measured on the first instance and will be written here. The
  restore test starts a second, throwaway database beside the running one, so
  leave room for the database twice. The health page fails when less than 15 %
  of the disk that holds Docker's data is free.

One machine is one point of failure: what protects the data is the nightly
backup (at most a day is lost) and the restore, not the machine.

## What you need before you start

| What | Why | Given to the install as |
| --- | --- | --- |
| The domain | the address of the instance | `--domain` |
| An SMTP account and a sender address | invitations, password resets, notifications | `SMTP_ADDRESS`, `SMTP_PORT`, `MAILER_SENDER_EMAIL`, and as the server needs `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_AUTHENTICATION`, `SMTP_DOMAIN`, `SMTP_ENABLE_STARTTLS_AUTO`, `SMTP_OPENSSL_VERIFY_MODE`, `SMTP_SSL`, `SMTP_TLS` |
| A mailbox you can read | the install sends a test message there | `--mail-to` |
| A bucket for backups on S3-compatible storage, in another region than the machine | nightly backups | `BACKUP_S3_ENDPOINT`, `BACKUP_S3_REGION`, `BACKUP_S3_BUCKET`, `BACKUP_S3_ACCESS_KEY_ID`, `BACKUP_S3_SECRET_ACCESS_KEY`, optionally `BACKUP_S3_PREFIX` (default `helpdesk`) and `BACKUP_S3_FORCE_PATH_STYLE` |
| A restore key | only its holder can read a backup | `BACKUP_AGE_RECIPIENT` (the public half) |
| An incoming webhook of your chat | failed backups, restore tests and upgrades are posted there | `ALERT_WEBHOOK_URL` |
| Where attachments live | see [Attachments](#attachments) | `ACTIVE_STORAGE_SERVICE` and, for object storage, `STORAGE_BUCKET_NAME`, `STORAGE_ACCESS_KEY_ID`, `STORAGE_SECRET_ACCESS_KEY`, `STORAGE_REGION`, `STORAGE_ENDPOINT`, optionally `STORAGE_FORCE_PATH_STYLE` |

`deploy/env.template` lists every variable with a comment.

### The restore key

Backups are encrypted with [`age`](https://age-encryption.org) to a public
key. Make the pair on your own computer, never on the machine:

```sh
age-keygen -o helpdesk-restore-key.txt
```

It prints the public key (`age1...`): that is `BACKUP_AGE_RECIPIENT`. The file
is the restore key. Keep it and a second copy outside the machine. Without it
no backup can be read, the environment file with the instance's secrets
included: the store connection could be made again, the conversations could
not. The machine never needs it except during a restore.

## Close the machine

```sh
sudo deploy/harden.sh
```

Run it before the install, from the session of a user that signs in with an
ssh key and may use `sudo`; it refuses when there is no such user, because
afterwards root and passwords cannot sign in. It leaves the machine with:

- ssh by key only, no root login;
- a firewall that lets in ports 22, 80 and 443 and nothing else;
- security updates installed automatically;
- every container's log bounded (10 MB a file, 5 files). The stack sets the
  same limits itself.

Docker publishes ports past the firewall, which is why the stack publishes 80
and 443 only. The script can be run again; it changes nothing that is already
as it should be. [The checklist](#checklist-for-each-new-machine) shows what
it cannot show from inside.

## Install

Check out the release and run the install with what you collected above. Give
the settings as environment variables of the names in the table; a secret that
is not in the environment is asked for without echo.

```sh
git clone --branch v<version> https://github.com/aceverseco/inclamo-helpdesk.git /opt/inclamo-helpdesk
cd /opt/inclamo-helpdesk

sudo SMTP_ADDRESS=smtp.example.com SMTP_PORT=587 SMTP_USERNAME=helpdesk \
     MAILER_SENDER_EMAIL='Example Support <support@example.com>' \
     BACKUP_S3_ENDPOINT=https://s3.example.net BACKUP_S3_REGION=eu-west \
     BACKUP_S3_BUCKET=example-helpdesk-backups BACKUP_S3_ACCESS_KEY_ID=... \
     BACKUP_AGE_RECIPIENT=age1... \
     ALERT_WEBHOOK_URL=https://chat.example.com/hooks/... \
     ACTIVE_STORAGE_SERVICE=local \
     deploy/install.sh --domain support.example.com --mail-to you@example.com
```

Keep the checkout where it is: the timers run the scripts from it.

What the install does, in this order:

1. checks that the domain resolves to an address of this machine, and stops,
   naming the address it resolves to, when it does not; no certificate has
   been asked for at that point;
2. uploads a test object to the backup target, and stops with the target's
   answer when the target refuses it;
3. pulls the image of the release and pins it by tag and digest;
4. draws the instance's secrets (the Rails secret, the three Active Record
   encryption keys, the database and Redis passwords) and writes
   `/etc/inclamo-helpdesk/helpdesk.env`, readable by root only. No secret is
   printed, by the install or by the containers;
5. prepares the database once (Chatwoot's schema and migrations and the
   overlay's), before the helpdesk starts;
6. sends the test message through your SMTP server, and stops with the
   server's answer when it is refused;
7. starts the helpdesk, its workers and the web server, which obtains the
   certificate and redirects HTTP to HTTPS;
8. installs the two timers, writes a first backup, runs a first restore test,
   and waits until the health page answers 200.

It does not finish when mail or backups would fail silently: without an SMTP
server, with one that refuses the test message, or with a backup target that
cannot be written, it stops and names what failed. A run that stops removes
what it made, so you can run it again.

It installs once. On a machine that has `/etc/inclamo-helpdesk/helpdesk.env`
it stops and changes nothing: the secrets in that file are the only key to
what the database holds, and they are never drawn twice.

The instance runs the published image and nothing else: no source is mounted
into its containers, and nothing is built on the machine.

## First run

Open `https://<domain>`. The first visit shows the onboarding page, which asks
for the name, company, email and password of the first administrator and
creates that administrator, with access to the installation's super-admin
console, and the first account. Do it right after the install: until then,
whoever opens the address first becomes the administrator.

After that the onboarding page is gone (it leads to the sign-in page), and
nobody can create an account by signing up: further people are invited by an
administrator.

## Mail

The instance sends all its mail (invitations, password resets, notifications)
through the SMTP server you gave, from `MAILER_SENDER_EMAIL`, with links to
`https://<domain>`. There is no fallback: this is why the install insists on
a working server. The install's test message proves that the server accepts
the mail, not that it reaches an inbox; set up SPF and DKIM for the sender's
domain with your mail provider, and see the checklist.

## Attachments

Files attached to conversations are kept outside the containers, so
recreating or upgrading the containers loses none. Choose where at install:

- `ACTIVE_STORAGE_SERVICE=s3_compatible`: a bucket on S3-compatible object
  storage (`STORAGE_*`). Turn on versioning for the bucket, so a deleted file
  can be brought back. The nightly backup then carries the database and the
  environment file; the files themselves stay in the bucket.
- `ACTIVE_STORAGE_SERVICE=local`: a volume on the machine. The nightly backup
  carries it too.

## What the instance does not report

The instance sends nothing about itself to Chatwoot's hub or to any other
third party: no usage counts, no daily version check, no registration at
onboarding (whatever is ticked there), no push notifications relayed by the
hub. Two consequences: the super-admin console does not announce new Chatwoot
versions, so follow this repository's releases; and Chatwoot's mobile app gets
no push notifications from the instance.

## Backups

`inclamo-helpdesk-backup.timer` runs `deploy/backup.sh` every night (02:30
UTC, a run missed while the machine was off happens at boot). A backup is, on
the target under `<prefix>/backups/<UTC time>/`:

- `database.dump.age`, the database;
- `storage.tar.age`, the attachments, when they are kept on the machine;
- `helpdesk.env.age`, the environment file with the instance's secrets;
- `manifest.txt`, the checksums, uploaded last: a backup without it is not
  finished and is never restored.

Each file is encrypted to the restore key before it leaves the machine, and
the upload is checked against the checksums. Then the retention: the newest
backup of each of the last 14 days and of each of the last 8 weeks is kept,
older ones are deleted.

A backup that fails posts to the alarm webhook at once, naming the step and
the target's answer, and the health page fails when the last successful backup
is older than 26 hours. To back up now: `sudo deploy/backup.sh`.

`inclamo-helpdesk-restore-test.timer` runs `deploy/restore-test.sh` on the
first of every month, and every upgrade runs it: it restores a fresh dump into
a throwaway stack on the machine (no published port), compares the numbers of
users, conversations and attachments with the running instance, reads the
store connection with the restored data, and checks that the objects of the
last backup are on the target with the recorded checksums. It needs no restore
key. The health page fails when the last successful test is older than 35
days.

## Restore

On an empty machine (closed with `deploy/harden.sh`, the domain pointing at
it, a checkout of the release the instance ran), with the restore key brought
for the occasion:

```sh
sudo BACKUP_S3_ENDPOINT=... BACKUP_S3_REGION=... BACKUP_S3_BUCKET=... \
     BACKUP_S3_ACCESS_KEY_ID=... BACKUP_S3_SECRET_ACCESS_KEY=... \
     deploy/restore.sh --identity /root/helpdesk-restore-key.txt
```

It restores the newest finished backup (`--backup <UTC time>` names another):
the environment file with the instance's own secrets, the database, the
attachments when they were kept on the machine. Then it starts the stack,
installs the timers, writes a first backup from the new machine, runs a
restore test and waits for the health page. Users sign in with their
passwords; conversations, attachments and the store connection are there; no
onboarding is offered.

Without the restore key it stops before touching anything, and it never
restores over an existing installation. Take the key off the machine when it
has finished.

## Upgrade and rollback

Check out the new release, then give the upgrade the tag of its image
(`<overlay version>-cw<Chatwoot version>`):

```sh
cd /opt/inclamo-helpdesk && sudo git fetch --tags && sudo git checkout v<version>
sudo deploy/upgrade.sh <version>-cw<Chatwoot version>
```

In this order: a backup off the machine; pulling the image; stopping the
helpdesk and its workers; a dump of the database as it stands; the migrations
of Chatwoot and of the overlay with the new image; start; the health page
polled for up to five minutes; a restore test.

- When the backup fails, the upgrade does not start: nothing is pulled and the
  instance keeps running.
- When the migrations fail or the helpdesk does not become healthy, the
  previous image and the dump taken after the helpdesk stopped are put back,
  the stack is started, and the alarm names the failed tag.

The helpdesk does not take messages for the length of the upgrade (minutes).
A rollback returns to the database of that moment; migrations are not run
backwards.

## Health and alarm

`GET https://<domain>/inclamo/health` answers 200 when every check is good and
503 otherwise, with the names of the failing checks and the versions that run,
and nothing else (no counts, no settings, nothing of the merchant's):

| Check | Fails when |
| --- | --- |
| `database` | a query does not answer |
| `redis` | Redis does not answer |
| `workers` | no background worker has reported in the last minute |
| `backup` | the last successful backup is older than 26 hours |
| `restore_test` | the last successful restore test is older than 35 days |
| `disk` | less than 15 % of the disk is free |

Two things raise the alarm, and both are needed:

- **A monitor outside the machine** requests the health page every minute and
  posts to your chat after three failures in a row, naming the instance and
  the failing checks. Any uptime monitor that can do this will do; it is not
  part of this repository, and it must not run on the machine it watches.
- **The machine itself** posts to `ALERT_WEBHOOK_URL` when a backup, a restore
  test or an upgrade fails.

## Checklist for each new machine

After the install, before anybody is given access. The first two and the
monitor cannot be shown by the install tests; do them from another computer.

1. **Password login is refused.**
   `ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password <user>@<machine>`
   answers `Permission denied (publickey)` without asking for a password, and
   `ssh root@<machine>` is refused with your key as well.
2. **Only 22, 80 and 443 answer from the internet.** From another computer,
   `nc -zv -w 3 <machine> 5432`, `6379` and `3000` fail, and a port scan
   (`nmap -Pn <machine>`) shows 22, 80 and 443 only.
3. **Only the web server publishes ports.**
   `sudo docker ps --format '{{.Names}} {{.Ports}}'` shows `0.0.0.0:80` and
   `0.0.0.0:443` on the `caddy` container and no other published port.
4. **HTTP is redirected.** `curl -sI http://<domain>/` answers with a redirect
   to `https://<domain>/`.
5. **Security updates are automatic.**
   `systemctl is-enabled unattended-upgrades` answers `enabled`.
6. **Container logs are bounded.**
   `sudo docker inspect --format '{{.Name}} {{.HostConfig.LogConfig}}' $(sudo docker ps -q)`
   shows `json-file` with `max-size` and `max-file` for every container.
7. **The timers are set.** `systemctl list-timers 'inclamo-helpdesk-*'` shows
   the nightly backup and the monthly restore test.
8. **Health answers from outside.** `curl -s https://<domain>/inclamo/health`
   from another computer answers `"status":"ok"`.
9. **The monitor alarms.** Point the monitor at the health page, then stop the
   workers:
   `sudo docker compose -p inclamo-helpdesk --env-file /etc/inclamo-helpdesk/helpdesk.env -f deploy/docker-compose.yaml stop sidekiq`.
   After three failed checks the chat gets an alarm naming the instance and
   `workers`. Start them again (`start sidekiq` in place of `stop sidekiq`)
   and see the health page return to 200.
10. **The machine's own alarm reaches the chat.** The scripts post
    `{"text": "..."}` to `ALERT_WEBHOOK_URL`. Post one yourself, with the
    address you gave the install:
    `curl -H 'Content-Type: application/json' -d '{"text":"alarm test of <domain>"}' '<webhook>'`,
    and see it arrive.
11. **Mail arrives.** Invite yourself as an agent: the invitation arrives in
    the inbox, not in spam, from the sender you configured, and its link opens
    `https://<domain>`.
12. **The restore works with the real key.** Once per instance, on a second
    machine (or on this one before it holds anything): run `deploy/restore.sh`
    with the real restore key and sign in. Note how long it took: that is how
    long the instance is away when the machine is lost.
13. **The restore key is off the machine**, and its second copy is where you
    can find it.
