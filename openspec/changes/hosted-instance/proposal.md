## Why

The helpdesk runs today only as a development stand: source mounted into the official image, an environment file kept by hand next to a synced tree (a sync with `--delete` removed it once, on 2026-11-06), the image built on the machine itself, a compose overlay that sends the store's token through a test proxy. A merchant's conversations cannot live there. The first hosted merchant needs a production instance: our image only, secrets that cannot be lost, mail that leaves, backups that restore, upgrades that can be undone. The same install is the first half of slice 9 of `docs/spec-plan.md` ("one compose file, our image"), so a self-hosting merchant gets it too.

## What Changes

- **A production stack in `deploy/`**, separate from `dev/`: the helpdesk, its background workers, Postgres with pgvector, Redis and a web server with automatic TLS, from our published image pinned by tag. No source is mounted; the database and Redis are published on no port.
- **A published image**: a release tag builds our image and pushes it to a public registry; an instance pulls it and never builds on the machine.
- **One install command**, `deploy/install.sh`: takes the domain, the mail settings and the backup target; checks that the domain points at the machine before asking for a certificate; generates the secrets on the machine once, readable by root only, never printed, never overwritten; sends a test message; writes a test backup; prepares the database (Chatwoot's and the overlay's migrations); starts the stack and waits until it is healthy. It refuses to finish when mail or backups would fail silently.
- **First run**: Chatwoot's own onboarding page creates the first administrator and the account; public sign-up stays closed. Our setup wizard (slice 7) replaces that screen later.
- **No reports to third parties**: the instance does not send its host name, version, counts or owner details to Chatwoot's hub (telemetry, the daily version check, the registration offered at onboarding, push relayed by the hub).
- **Nightly backups off the machine**: the database, the attachments when they are kept on the machine, and the environment file, each encrypted; a retention; an alarm when a backup fails.
- **A restore that is actually exercised**: `deploy/restore.sh` rebuilds an instance from a backup and a restore key held outside the machine; a restore test on a throwaway stack runs after every upgrade and every month, and its age is part of the health.
- **Upgrades by image tag**: `deploy/upgrade.sh <tag>` backs up first, runs the migrations, checks health, and returns to the previous tag and the pre-upgrade database when health fails.
- **Health and alarm**: our own health page (a real database query, Redis, the background workers, the age of the last backup and of the last restore test, free disk), checked from outside every minute, alarming the operator's chat.
- **A machine baseline**: ssh by key only, no root login, only ports 22, 80 and 443 open, security updates installed automatically, container logs bounded.
- **`docs/install.md`** for the operator. A merchant-facing guide is not part of this change.

Not in this change: the upstream-release routine (merging a Chatwoot tag, changelog, upgrade note: the rest of slice 9), our setup wizard and branding (slice 7), several machines or a managed database, Postgres major-version upgrades.

## Capabilities

### New Capabilities
- `instance-installation`: how an operator installs a production instance from the published image, what the install refuses, the first run, outgoing mail, where attachments live, what the instance does not report, nightly backups and restore, upgrades and rollback, health and alarm, the machine baseline.

### Modified Capabilities
- none

## Assumptions for the founder

> Founder, 2026-11-07: the changes are built in turn without further stops; the assumptions stand as written until the founder says otherwise. Assumption 3 (the mail provider) needs the founder's choice before the first instance is finished, since it is a cost.

1. **The image is published to the GitHub container registry** of this repository (public, like the code) on every release tag, named `<overlay version>-cw<Chatwoot version>`; an instance pins tag and digest. Building on the machine is not offered.
2. **Attachments live in S3-compatible object storage** of the same provider as the machine, in a versioned bucket in the EU. The alternative is a volume on the machine, included in the nightly backup.
3. **The outgoing mail provider is not chosen.** The install takes any SMTP server; choosing and paying for one is the founder's call. Without one the install does not finish.
4. **Recovery point 24 hours.** Backups nightly, kept 14 daily and 8 weekly, encrypted, in a bucket in another EU region than the machine; a restore test monthly and after every upgrade.
5. **The restore key is held by the founder outside the machine.** Without it no backup can be read, the environment file included.
6. **Nothing goes to Chatwoot's hub.** Telemetry, the daily version check, the onboarding registration and push notifications relayed by the hub are all off; the Chatwoot mobile app then gets no push notifications from this instance.
7. **A rollback restores the pre-upgrade database.** Intake stops during an upgrade (a few minutes); what arrived between the backup and a rollback is lost.
8. **Alarms go to the operator's chat** through an incoming webhook, from a monitor outside the machine that checks every minute and alarms after three failures in a row; which monitor is the founder's call.
9. **One instance per merchant for now**, while nothing in the install assumes a single account, as spec-plan §5 provides.

## Impact

- New: `deploy/` (compose file, environment template, install, backup, restore, restore test, upgrade and hardening scripts, a systemd timer), a release step in `.github/workflows/image.yml`, an install workflow, `docs/install.md`.
- Overlay: a health endpoint outside the account routes (the first one), and a prepend that silences Chatwoot's hub client. No core patch.
- Tests: an end-to-end file driving a throwaway installation in CI (internal certificate authority, an S3-compatible container, a mail catcher, a webhook receiver for the alarm); the few scenarios that need a real machine are named in the coverage check with the checklist that covers them.
- Depends on: a machine with Docker and a domain for the first instance, a bucket for backups (and attachments, by assumption 2), an SMTP account, an incoming webhook for alarms. Their provider, size, region and names are recorded outside this repository.
