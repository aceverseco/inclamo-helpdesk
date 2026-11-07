## 1. Published image

- [ ] 1.1 Push the image to the registry on a `v*` tag from `.github/workflows/image.yml`, tagged `<overlay>-cw<chatwoot>`, keeping the overlay check; verify a test tag publishes it and a clean machine pulls it by tag and by digest
- [ ] 1.2 Pin Postgres (pgvector on Postgres 16) and Redis to exact tags chosen from their registries; verify `docker compose -f deploy/docker-compose.yaml config` names no floating tag

## 2. Install

- [ ] 2.1 Write `deploy/docker-compose.yaml` (`rails`, `sidekiq`, `postgres`, `redis` with append-only persistence, `caddy`), the environment file read from `/etc/inclamo-helpdesk/helpdesk.env`, ports published by `caddy` only; verify `docker compose ps` on a test install lists 80 and 443 only
- [ ] 2.2 Write `deploy/env.template` with every variable the stack and the scripts read, each with a comment (secrets left empty); add a check that fails when a variable read in `deploy/` is missing from the template; verify the check passes and fails on a removed line
- [ ] 2.3 Write `deploy/install.sh`: inputs, domain check, secrets made once with `umask 077` and never printed, refusal when the environment file exists, SMTP test message, backup target test upload, `db:chatwoot_prepare` once before the stack starts, wait for health; verify by the install tests of group 7
- [ ] 2.4 Set `FORCE_SSL=true`, `ENABLE_ACCOUNT_SIGNUP=false`, `DISABLE_TELEMETRY=true`, `ENABLE_PUSH_RELAY_SERVER=false` in the template's fixed part; verify by the install tests "Only the web server listens" and "Sign-up is closed"

## 3. Overlay

- [ ] 3.1 Prepend `ChatwootHub` so `sync_with_hub`, `register_instance` and `emit_event` make no request; verify by a backend spec with network access blocked that the daily job and onboarding with "subscribe to updates" ticked make no request
- [ ] 3.2 Add `GET /inclamo/health` (database query, Redis, Sidekiq process beat, backup and restore-test ages from the status file, free disk, versions) and update the comment of `custom/config/routes.rb`; verify by request specs that each failing check gives 503 with its name and that the body holds no secret, count or merchant data

## 4. Backups and restore

- [ ] 4.1 Write `deploy/backup.sh` and its systemd timer: dump, `storage` volume when used, environment file, each encrypted with `age` to `BACKUP_AGE_RECIPIENT`, upload, retention, checksums and last success in the status file, alarm on failure; verify by the install tests against MinIO
- [ ] 4.2 Write `deploy/restore.sh` (refuses without the identity, schema restored before `db:chatwoot_prepare`, no onboarding flag after it); verify by the test "Restore into an empty installation" with test keys
- [ ] 4.3 Write `deploy/restore-test.sh` and its monthly timer (fresh dump into a throwaway project, counts, store connection, checksums of the last backup, status file); verify that health answers 503 when the last restore test is older than 35 days

## 5. Upgrade

- [ ] 5.1 Write `deploy/upgrade.sh <tag>`: backup gate, pull, stop intake, `db:chatwoot_prepare` with the new image, health poll, automatic rollback to the previous tag and the pre-upgrade dump, alarm, restore test; verify by the upgrade tests from the previous release tag and to a deliberately broken image

## 6. Machine baseline

- [ ] 6.1 Write `deploy/harden.sh` (firewall 22/80/443, `sshd` keys only and no root login, unattended security upgrades, Docker log limits); verify the test "Container logs stay bounded" and, on each new machine, the checklist items of `docs/install.md`

## 7. Tests

- [ ] 7.1 Add `.github/workflows/install.yml` and `e2e/install-run.sh` with the test mode of design D15 (internal authority, fake address, MinIO, Mailpit, alarm receiver), on `main`, tags and by hand; verify a manual run brings the stack up and down cleanly
- [ ] 7.2 Write `e2e/tests/instance-installation.spec.mjs`, one test per scenario, for both `ACTIVE_STORAGE_SERVICE` values; map `instance-installation` in `scripts/check-e2e-coverage.mjs` and list "Password login refused" and "Alarm after three failures" as covered elsewhere; verify the coverage check and the install workflow pass, and the log holds no generated secret

## 8. Documents and the first instance

- [ ] 8.1 Write `docs/install.md`: machine requirements, inputs, install, first run, mail, attachments, backups and the restore key, restore, upgrade and rollback, health and alarm, the checklist for each new machine; verify every requirement of the spec has its section
- [ ] 8.2 Install the first instance by `docs/install.md` alone, run the restore with the real key once and the checklist, measure the smallest comfortable machine and write it in `docs/install.md`; verify every checklist item passes, and keep the machine's records outside this repository
