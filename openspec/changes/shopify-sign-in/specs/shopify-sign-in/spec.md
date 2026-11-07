## Purpose

Lets the merchant's team sign in to the helpdesk with their Shopify staff accounts, from the helpdesk's login page and from the Shopify admin, on a store connected through our Shopify app. Only people who already are users of the store's helpdesk account get in, nothing is created by trying, and nothing Shopify hands over is kept.

## ADDED Requirements

### Requirement: The login page offers Shopify sign-in for the connected store
The login page SHALL show "Sign in with Shopify" above the email and password form when exactly one account of the installation has its store connected through our Shopify app. The button SHALL NOT ask for a store. Without such a store, or with more than one, the login page SHALL show no Shopify button and no divider of its own. Signing in with email and password SHALL work as before in every case.

#### Scenario: Store connected through the app
- **WHEN** a person opens the login page of an installation whose one account has its store connected through the app
- **THEN** the page shows "Sign in with Shopify" above the email and password form, with no field for a store

#### Scenario: Store connected with the merchant's own app
- **WHEN** a person opens the login page of an installation whose account is connected with the merchant's own app credentials
- **THEN** the page shows the email and password form and no Shopify button

#### Scenario: Two accounts connected through the app
- **WHEN** a person opens the login page of an installation where two accounts have stores connected through the app
- **THEN** the page shows no Shopify button

#### Scenario: Password sign-in still works
- **WHEN** a user who has signed in through Shopify before signs in with their email and password
- **THEN** they are signed in as before

### Requirement: A staff member who is a user of the store's account signs in
When Shopify confirms a staff member of the connected store whose email Shopify has verified, and that email belongs to a user of the store's helpdesk account, the person SHALL be signed in to the helpdesk and SHALL land in that account. Emails SHALL match regardless of letter case. The helpdesk session SHALL be the helpdesk's own, with its usual lifetime; it SHALL NOT depend on Shopify's token, which the helpdesk SHALL NOT store, log or use.

#### Scenario: Agent signs in with Shopify
- **WHEN** a staff member whose verified email belongs to an agent of the store's account presses "Sign in with Shopify" and Shopify confirms them
- **THEN** they are signed in and see the store's account in the dashboard

#### Scenario: Email in other letter case
- **WHEN** Shopify confirms `Anna@Example.com` and the helpdesk user is `anna@example.com`
- **THEN** the person is signed in

#### Scenario: The session does not depend on Shopify
- **WHEN** a person has signed in through Shopify and Shopify then refuses every token it issued for that sign-in
- **THEN** the person stays signed in, the dashboard works, and Shopify received no request with that token

#### Scenario: Invited user accepts by signing in with Shopify
- **WHEN** an agent invited to the store's account who has not accepted yet signs in through Shopify with the same verified email
- **THEN** they are signed in, and the account lists them as confirmed

### Requirement: Nobody else gets in, and nothing is created
The helpdesk SHALL refuse the sign-in, with a message on the login page and without a session, when Shopify has not verified the email, when the staff member is a collaborator of the store, when no user of the store's account has the email, and when the user has turned on two-factor authentication in the helpdesk. An email of no user and an email of a user of another account SHALL get the same message. No user, account or invitation SHALL be created by a Shopify sign-in, whatever the installation's sign-up setting.

#### Scenario: Email not verified by Shopify
- **WHEN** Shopify confirms a staff member whose email it has not verified
- **THEN** the login page says Shopify has not verified the email of this account, and nobody is signed in

#### Scenario: Unknown email
- **WHEN** Shopify confirms a staff member whose email belongs to no user of the helpdesk
- **THEN** the login page says there is no helpdesk user with this email for this store and to ask an administrator for an invitation; no user and no account are created

#### Scenario: User of another account
- **WHEN** Shopify confirms a staff member whose email belongs only to a user of another account of the installation
- **THEN** the login page shows the same message as for an unknown email, and nobody is signed in

#### Scenario: Sign-up open on the installation
- **WHEN** the installation allows sign-up and Shopify confirms a staff member with an unknown email
- **THEN** the sign-in is refused as for an unknown email, and no account is created

#### Scenario: Collaborator account
- **WHEN** Shopify confirms a collaborator of the store whose email belongs to an agent of the account
- **THEN** the login page says collaborator accounts sign in with their helpdesk password, and nobody is signed in

#### Scenario: User with two-factor authentication
- **WHEN** Shopify confirms a staff member whose helpdesk user has two-factor authentication on
- **THEN** the login page says to sign in with the password and the code, and nobody is signed in

### Requirement: Opening the app from the Shopify admin signs the person in
When a staff member opens our app from the Shopify admin of a store connected through the app, the helpdesk SHALL take them through the same sign-in and, when they get in, SHALL open the store's account. A launch whose shop is not connected through the app SHALL sign nobody in.

#### Scenario: Launch from the Shopify admin
- **WHEN** an agent of the store's account opens the app from the Shopify admin
- **THEN** a new tab opens on the helpdesk with that agent signed in and the store's account shown

#### Scenario: Launch for a store that is not connected
- **WHEN** the app is opened from the admin of a store that is not connected through the app
- **THEN** nobody is signed in and the page says the store is not connected to this helpdesk

### Requirement: Every exchange with Shopify is checked
A sign-in SHALL go on only when Shopify answers the request that this browser started, within ten minutes, once; when Shopify's signature of the answer is valid; when the answer is for the store the sign-in was started for; and when Shopify confirms one staff member. Otherwise the sign-in SHALL be refused with a message and nothing SHALL change. When Shopify refuses the staff member or cannot be reached, the login page SHALL say so.

#### Scenario: An answer this browser did not ask for
- **WHEN** the helpdesk receives Shopify's answer to a sign-in started in another browser
- **THEN** nobody is signed in and the helpdesk says the sign-in expired and to try again

#### Scenario: The same answer twice
- **WHEN** Shopify's answer to a sign-in that succeeded arrives again
- **THEN** the second one signs nobody in and the helpdesk says the sign-in expired

#### Scenario: A forged signature
- **WHEN** an answer arrives whose signature does not match the app's secret
- **THEN** nobody is signed in and the helpdesk says the sign-in could not be checked

#### Scenario: An answer for another store
- **WHEN** an answer arrives for a store other than the one the sign-in was started for
- **THEN** nobody is signed in and the helpdesk says the sign-in could not be checked

#### Scenario: Shopify refuses the staff member
- **WHEN** Shopify refuses to confirm the staff member, as it does for a person removed from the store
- **THEN** nobody is signed in and the login page says Shopify did not allow the sign-in

#### Scenario: Shopify does not answer
- **WHEN** Shopify does not answer the exchange of the code within ten seconds
- **THEN** nobody is signed in and the login page says Shopify could not be reached and to try again

### Requirement: Disconnecting the store ends this way in
When the store's connection through the app ends, the login page SHALL stop showing the Shopify button, and a sign-in started before SHALL be refused.

#### Scenario: Store disconnected during a sign-in
- **WHEN** the store is disconnected after a person pressed "Sign in with Shopify" and before Shopify answered
- **THEN** nobody is signed in, and the login page no longer shows the Shopify button

### Requirement: Attempts are recorded without personal data and rate limited
Every Shopify sign-in attempt SHALL leave one log line with its outcome, where it started, the account and the helpdesk user when one was found, and SHALL NOT log the email, names, Shopify's user id, Shopify's token or code. More than ten starts and answers from one address within five minutes SHALL be refused until the period ends.

#### Scenario: A sign-in leaves one line
- **WHEN** an agent signs in through Shopify
- **THEN** the log holds one line for the attempt with the outcome `signed_in`, the account and the user, and no email, name, token or code

#### Scenario: Too many attempts from one address
- **WHEN** one address starts a Shopify sign-in for the eleventh time within five minutes
- **THEN** the helpdesk refuses it and the login page says there were too many attempts
