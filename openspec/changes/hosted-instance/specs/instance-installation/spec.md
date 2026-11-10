## Purpose

How an operator installs, runs, backs up, restores and upgrades a production instance of the helpdesk on one machine from our published image, so that a merchant's conversations are kept safe and the instance can be brought back and kept current.

## ADDED Requirements

### Requirement: One command installs an instance from the published image
The operator SHALL install a production instance on a fresh machine with Docker by running `deploy/install.sh` with the instance's domain, the outgoing mail settings and the backup target. The instance SHALL run the image tag pinned in its configuration, pulled from the registry, with no source code mounted into its containers. The database and Redis SHALL NOT be published on any port; only the web server SHALL listen, on ports 80 and 443, and a plain HTTP request SHALL be redirected to HTTPS. Before asking for a certificate the install SHALL check that the domain points at the machine.

#### Scenario: Fresh install
- **WHEN** the operator runs the install on a machine the domain points at, with mail settings and a writable backup target
- **THEN** the helpdesk answers over HTTPS at the domain, `GET /api` names the pinned Chatwoot version and the health page names the pinned overlay version

#### Scenario: Domain points elsewhere
- **WHEN** the operator runs the install with a domain that resolves to another address than the machine's
- **THEN** the install stops before any certificate is requested and names the address the domain resolves to

#### Scenario: Only the web server listens
- **WHEN** the instance is running
- **THEN** no container but the web server publishes a port, the web server publishes only 80 and 443, and `http://` on the domain is redirected to `https://`

### Requirement: Secrets are made on the machine once and are never printed
The install SHALL generate the instance's secrets (the Rails secret, the three Active Record encryption keys, the database and Redis passwords) on the machine and write them to an environment file outside the repository checkout, readable by root only. It SHALL NOT print a secret, and SHALL NOT overwrite an environment file that exists.

#### Scenario: Running the install again keeps the secrets
- **WHEN** the install runs a second time on the same machine
- **THEN** the environment file is unchanged and a store connection made before the second run still reads the store

#### Scenario: Secrets stay out of the output
- **WHEN** the install runs
- **THEN** neither its output nor the logs of the containers contain any of the generated secrets

### Requirement: The install refuses what would fail silently
The install SHALL NOT finish when the outgoing mail settings are missing, when the mail server refuses the test message, or when the backup target cannot be written, and SHALL name what failed.

#### Scenario: No mail settings
- **WHEN** the operator runs the install without an SMTP server
- **THEN** the install stops before the helpdesk starts and says that the mail settings are missing

#### Scenario: Mail server refuses the credentials
- **WHEN** the SMTP server refuses the given credentials
- **THEN** the install stops and shows the mail server's answer

#### Scenario: Backup target not writable
- **WHEN** the backup target refuses the test upload
- **THEN** the install stops and names the backup target and its answer

### Requirement: The first visit creates the administrator and the account
After installation, the first visit SHALL open the onboarding page, which creates the first administrator, with access to the installation's super-admin console, and the first account. After onboarding the page SHALL NOT be reachable again, and nobody SHALL be able to create an account by signing up.

#### Scenario: First visit opens onboarding
- **WHEN** someone opens the instance's address right after installation
- **THEN** the onboarding page asks for the name, company, email and password of the first administrator

#### Scenario: Onboarding happens once
- **WHEN** onboarding has been completed and someone opens the onboarding page
- **THEN** they are sent to the sign-in page

#### Scenario: Sign-up is closed
- **WHEN** someone who has no user opens the sign-up page of the instance
- **THEN** no account can be created

### Requirement: Mail leaves the instance
The instance SHALL send its mail (invitations, password resets, notifications) through the configured SMTP server, from the configured sender address, with links to the instance's domain.

#### Scenario: An invitation reaches the agent
- **WHEN** an administrator invites an agent by email
- **THEN** the invitation arrives at that address from the configured sender, and its link opens the instance's domain

### Requirement: Attachments outlive the containers
Files attached to conversations SHALL be kept outside the containers, in the configured storage, so that recreating or upgrading the containers loses none of them.

#### Scenario: Attachment after the containers are recreated
- **WHEN** a contact sends a photo in a conversation and the containers are then recreated
- **THEN** the photo still opens in the conversation

### Requirement: The instance reports nothing about itself to third parties
The instance SHALL NOT send its host name, version, identifier, counts or owner details to Chatwoot's hub or to any other third party: no telemetry, no daily version check, no registration at onboarding, no push notifications relayed by the hub.

#### Scenario: Daily jobs and onboarding send nothing to the hub
- **WHEN** the instance completes onboarding and runs its daily scheduled jobs
- **THEN** no request leaves the instance for Chatwoot's hub

### Requirement: Nightly backups leave the machine encrypted
Every night the instance SHALL back up its database, its attachments when they are kept on the machine, and its environment file to the backup target outside the machine, each encrypted so that only the holder of the restore key can read it, and SHALL delete backups older than the retention. A backup that fails SHALL raise the alarm.

#### Scenario: Nightly backup
- **WHEN** the nightly backup runs
- **THEN** the backup target holds a new database dump and a copy of the environment file, and neither can be read without the restore key

#### Scenario: Retention
- **WHEN** the backup target holds backups older than the retention
- **THEN** the nightly backup deletes them and keeps the newer ones

#### Scenario: Failed backup raises the alarm
- **WHEN** the backup target refuses the nightly upload
- **THEN** the alarm reaches the operator's chat naming the backup and the target's answer

### Requirement: A backup restores to a working instance
`deploy/restore.sh` SHALL rebuild an instance in an empty installation from a backup and the restore key, with its users, contacts, conversations, attachments and store connection. It SHALL refuse to run without the restore key before touching any data. A restore test SHALL run on a throwaway stack after every upgrade and at least once a month, and the age of the last successful one SHALL be part of the health.

#### Scenario: Restore into an empty installation
- **WHEN** the operator restores the latest backup with the restore key into an empty installation
- **THEN** users sign in with their passwords, conversations and their attachments are there, and the order panel reads the store

#### Scenario: Restore without the key
- **WHEN** the restore is run without the restore key
- **THEN** it stops before touching the database and says that the restore key is needed

### Requirement: Upgrades go by image tag and are rolled back when they fail
`deploy/upgrade.sh <tag>` SHALL take a backup first, pull the image of that tag, run the migrations of Chatwoot and of the overlay, start the stack and check its health. When the backup fails the upgrade SHALL NOT start. When the health check fails after the upgrade, the instance SHALL return to the previous tag and the pre-upgrade database, and the alarm SHALL name the failed tag.

#### Scenario: Upgrade to a newer tag
- **WHEN** the operator upgrades an instance running the previous release to the current one
- **THEN** the health page names the new versions, and the conversations, attachments and store connection made before are there

#### Scenario: Upgrade without a backup does not start
- **WHEN** the operator upgrades while the backup target refuses the upload
- **THEN** the upgrade stops before pulling the image and the instance keeps running the old tag

#### Scenario: Failed upgrade is rolled back
- **WHEN** the instance is upgraded to a tag whose helpdesk does not become healthy
- **THEN** the previous tag runs with the pre-upgrade database, and the alarm reaches the operator's chat naming the failed tag

### Requirement: Health is visible from outside and failures reach the operator
The instance SHALL answer `GET /inclamo/health` with the state of the database (a real query), Redis, the background workers, the age of the last successful backup and of the last successful restore test, and the free disk: 200 when every check is good, 503 otherwise, naming the failing checks, without secrets, counts or merchant data. A monitor outside the machine SHALL check it every minute and alarm the operator's chat after three failures in a row.

#### Scenario: Healthy instance
- **WHEN** the database, Redis and the workers run, the last backup is under 26 hours old and the last restore test under 35 days
- **THEN** the health page answers 200

#### Scenario: Workers stopped
- **WHEN** the background workers are stopped
- **THEN** the health page answers 503 naming the workers

#### Scenario: Stale backup
- **WHEN** the last successful backup is older than 26 hours
- **THEN** the health page answers 503 naming the backup

#### Scenario: Alarm after three failures
- **WHEN** the health page fails three checks of the outside monitor in a row
- **THEN** the operator's chat gets an alarm naming the instance and the failing checks

### Requirement: The machine is closed except for the web and ssh
The machine SHALL accept ssh with keys only and no root login, SHALL accept connections from outside on ports 22, 80 and 443 only, SHALL install security updates automatically, and SHALL keep each container's logs under a bounded size.

#### Scenario: Password login refused
- **WHEN** someone tries to sign in over ssh with a password
- **THEN** the machine refuses before asking for one

#### Scenario: Container logs stay bounded
- **WHEN** the instance has been installed
- **THEN** every container of the stack logs with a size limit and a number of rotated files
