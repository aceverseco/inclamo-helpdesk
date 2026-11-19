# app-provisioned-account

Behavior contract for this source revision.

The store app is the Shopify app run by the operator of a hosted helpdesk. On
its signed request the helpdesk creates a Shopify store's account and the
account's first administrator, keeps one account per store, suspends it when
the app is removed and restores it when the app returns. The calls themselves
are described in `docs/app-provisioning.md`.

### Requirement: The app's request creates an account for a store

On a valid request from the store app naming a Shopify store and a person, the helpdesk SHALL create an account named after the store and make that person its administrator, and SHALL answer with the account's identifier and the helpdesk's address. The account SHALL be usable at once: no operator action and no email SHALL be needed for it to exist. A request that lacks the store's domain, the person's email or the statement that Shopify verified that email SHALL be refused and SHALL create nothing.

#### Scenario: A store without an account

- **WHEN** the app sends a valid request for `example-store.myshopify.com` naming a staff member with a verified email
- **THEN** the answer says an account was created and gives its identifier and the helpdesk's address, the account carries the store's name, and the staff member is its administrator

#### Scenario: The email is not verified

- **WHEN** the app sends a request that names an email without stating that Shopify verified it
- **THEN** the request is refused with a reason, and no account and no user exist for that store or email

#### Scenario: The store's domain is not a Shopify domain

- **WHEN** the app sends a request whose store is not a `myshopify.com` domain
- **THEN** the request is refused with a reason and nothing is created

### Requirement: A store has one account

The helpdesk SHALL keep at most one account per Shopify store, recognised by the store's permanent `myshopify.com` domain whatever its letter case. A request for a store that already has an account SHALL answer with that account, SHALL say it already existed, and SHALL NOT create an account or change its name. Two requests for the same store arriving together SHALL end with one account.

#### Scenario: The request is repeated

- **WHEN** the app sends a second valid request for a store that already has an account
- **THEN** the answer gives the same account identifier and says the account already existed, and the installation has one account for that store

#### Scenario: Two requests at the same moment

- **WHEN** two valid requests for the same new store arrive together
- **THEN** both are answered with the same account identifier and the installation has one account for that store

#### Scenario: Another person asks for a store that has an account

- **WHEN** the app sends a valid request for a store that already has an account, naming a staff member who is not a user of that account
- **THEN** the answer gives the existing account, and that staff member is not made a user of it

### Requirement: The first administrator is the person the app names

The administrator SHALL be created with the name and the email the app gives, as a confirmed user whom no password signs in until they set one. When the installation already has a user with that email, that user SHALL be made administrator of the new account and SHALL keep their password, their other accounts and their roles in them. The helpdesk SHALL NOT send a confirmation or an invitation letter for an account created this way.

#### Scenario: A person new to the installation

- **WHEN** an account is created for a staff member whose email no user has
- **THEN** a confirmed user with that name and email exists as administrator of the new account, no password signs them in yet, and no letter was sent

#### Scenario: A person the installation already knows

- **WHEN** an account is created for a staff member whose email belongs to a user of another account
- **THEN** that user is administrator of the new account, is still a member of the other account with the same role, and signs in with the same password as before

### Requirement: A new administrator can set a password of their own

When a request creates a user, the answer SHALL carry a one-time link on which that person sets a password for the helpdesk, so they can sign in on the login page as well as from the Shopify admin. The link SHALL work once and only for a limited time, and SHALL set a password for that user only. No link SHALL be given for a user the installation already had, in an answer about an account that already existed, or in a repeated answer after the link's time has passed. The link SHALL NOT be written to any record or log.

#### Scenario: The new administrator sets a password

- **WHEN** an account is created for a person new to the installation and they open the link from the answer and enter a password
- **THEN** they sign in on the helpdesk's login page with their email and that password and see the new account

#### Scenario: The link is used twice

- **WHEN** the link from the answer is opened again after a password was set with it
- **THEN** it is refused and the password is unchanged

#### Scenario: A person the installation already knew gets no link

- **WHEN** an account is created for a staff member whose email belongs to an existing user
- **THEN** the answer carries no password link and that user's password is unchanged

#### Scenario: The link's time has passed

- **WHEN** the link from the answer is opened after its time has passed
- **THEN** it is refused, no password is set, and the person can still get in from the Shopify admin

### Requirement: Only the app can ask

Every provisioning request SHALL be signed with the secret the hosted helpdesk shares with the app, over the request's time and its exact body, and SHALL carry a key that is used once. The helpdesk SHALL refuse a request whose signature does not match, whose time is more than five minutes from its own, or whose key it has already seen with a different body, and SHALL create or change nothing for a refused request. A refusal SHALL NOT say which of the checks failed. The secret SHALL never appear in an answer or in a log.

#### Scenario: A request without a valid signature

- **WHEN** a request for a new store arrives with a signature made with another secret
- **THEN** it is refused as not authorised and no account exists for that store

#### Scenario: A stale request

- **WHEN** a correctly signed request arrives with a time ten minutes in the past
- **THEN** it is refused as not authorised and nothing is created

#### Scenario: The same request delivered twice

- **WHEN** the app delivers the same signed request, with the same key and body, a second time within five minutes
- **THEN** the second answer is the same as the first and nothing is created a second time

#### Scenario: A key reused for another store

- **WHEN** a correctly signed request reuses an earlier request's key with a different store
- **THEN** it is refused and no account exists for the second store

### Requirement: Requests are limited

The helpdesk SHALL limit how many provisioning requests it accepts in a period, for the installation as a whole and for one store, and SHALL answer a request over the limit by saying when to try again, without creating anything.

#### Scenario: Too many requests

- **WHEN** valid requests for new stores arrive faster than the installation's limit
- **THEN** the requests over the limit are answered with the time to try again and no account exists for their stores

### Requirement: Removing the app suspends the account

On the app's signed notice that a store removed the app, the helpdesk SHALL suspend that store's account: its users SHALL NOT be able to open it, and messages arriving for its inboxes SHALL NOT be accepted into it. Nothing of the account SHALL be deleted. A notice for a store without an account, or for an account already suspended, SHALL be answered as done.

#### Scenario: The app is removed

- **WHEN** the app sends a valid removal notice for a store whose account has conversations
- **THEN** the account is suspended, its administrator can no longer open it, and its conversations, contacts and settings are still stored

#### Scenario: The notice is repeated

- **WHEN** the app sends the removal notice for the same store again
- **THEN** it is answered as done and the account is still suspended with its data

#### Scenario: A user of two accounts

- **WHEN** the account of one store is suspended and its administrator is also a member of another store's account
- **THEN** they can still open the other account

### Requirement: Installing again restores the same account

A valid provisioning request for a store whose account is suspended SHALL make that account active again with everything it held, SHALL answer with the same account identifier, and SHALL say the account was restored. The person named in the request SHALL be its administrator afterwards, whether or not they were a user of it before.

#### Scenario: The store installs the app again

- **WHEN** the app sends a valid request for a store whose account was suspended with twelve conversations
- **THEN** the answer gives the earlier account identifier and says it was restored, and the administrator finds the twelve conversations

#### Scenario: Another person installs again

- **WHEN** the app sends a valid request for a store with a suspended account, naming a staff member who was never its user
- **THEN** the account is active again and that staff member is one of its administrators, next to the earlier ones

### Requirement: The app can ask what a store has

The app SHALL be able to ask, with a signed request, whether a store has an account, and SHALL be told the account's identifier, whether it is active or suspended, and when it was created, or that there is none. The answer SHALL NOT include users, conversations or any shopper's data.

#### Scenario: A store with an active account

- **WHEN** the app asks about a store whose account is active
- **THEN** the answer gives the account identifier, the state "active" and the creation time, and nothing about its users or conversations

#### Scenario: A store without an account

- **WHEN** the app asks about a store that never had an account
- **THEN** the answer says there is none

### Requirement: Provisioning exists only where the operator enabled it

An installation without the shared secret SHALL answer every provisioning address as an address that does not exist, and SHALL offer no other way to create an account without an operator. Public sign-up SHALL stay as the installation set it.

#### Scenario: A self-hosted installation

- **WHEN** a request arrives at a provisioning address of an installation that has no shared secret
- **THEN** it is answered as not found, whatever its signature, and nothing is created

### Requirement: Every provisioning attempt is recorded without personal data

The helpdesk SHALL record each provisioning request and removal notice with its time, the store's domain and its outcome (created, existed, restored, suspended, refused, limited). The record SHALL NOT hold the person's name or email, the signature or the secret.

#### Scenario: A refused request is recorded

- **WHEN** a request with a wrong signature arrives for a store
- **THEN** a record exists with the time, the store's domain and the outcome "refused", and without an email, a name or a signature
