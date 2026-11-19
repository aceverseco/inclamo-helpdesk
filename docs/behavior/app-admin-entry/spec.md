# app-admin-entry

Behavior contract for this source revision.

Lets a Shopify staff member open their store's helpdesk account from the store
app without a helpdesk password. The app says who the person is over its
signed provisioning channel; the helpdesk decides whether they get in, gives a
one-time address of its own that signs in that person and nobody else, and
keeps the password login as it is. The call is described in
`docs/app-admin-entry.md`; the installation's settings are in
[app provisioning setup](../../app-provisioning-setup.md#a-staff-members-entry-from-the-app).

### Requirement: The app's request gives a user a one-time way in
On a valid signed request from the store app naming a store and a staff member's email that Shopify verified, the helpdesk SHALL answer with a one-time address when that email belongs to a user of the store's account. The address SHALL be the helpdesk's own and SHALL carry nothing about the person. Opening the address in a browser SHALL sign that user in to the helpdesk without a password and show the store's account. A request that lacks the email or the statement that Shopify verified it SHALL be refused and SHALL give no address.

#### Scenario: An administrator opens the helpdesk from the app
- **WHEN** the app sends a valid request for a store naming the verified email of that account's administrator, and the browser opens the address from the answer
- **THEN** the browser is signed in as that administrator and shows the store's account, and no password was asked

#### Scenario: An agent opens the helpdesk from the app
- **WHEN** the app sends a valid request naming the verified email of a user with the agent role in the store's account, and the browser opens the address
- **THEN** the browser is signed in as that agent with the agent's rights

#### Scenario: The email is not verified
- **WHEN** the app sends a request naming an email without stating that Shopify verified it
- **THEN** the request is refused with a reason and no address is given

### Requirement: Only users of the store's account get in
The helpdesk SHALL refuse a request whose email belongs to no user, or to a user who is not a member of that store's account, with one reason for both cases, so the answer does not tell which emails the installation knows. It SHALL NOT create a user or add a user to an account on such a request. A request for a store that has no account SHALL be answered that there is none.

#### Scenario: A staff member who is not a helpdesk user
- **WHEN** the app sends a valid request naming a verified email that no user has
- **THEN** the request is refused as "not a user of this helpdesk account", no address is given, and no user exists with that email

#### Scenario: A user of another store's account
- **WHEN** the app sends a valid request for one store naming the email of a user who belongs only to another store's account
- **THEN** the request is refused with the same reason as for an unknown email, and that user is not a member of the first store's account

#### Scenario: A store without an account
- **WHEN** the app sends a valid request for a store that never had an account
- **THEN** the answer says the store has no account and no address is given

### Requirement: The person lands in this store's account
The address SHALL open the account of the store named in the request, also for a user who belongs to several accounts and last worked in another one.

#### Scenario: A user of two accounts
- **WHEN** a user who belongs to the accounts of two stores opens an address made for the second store, having last worked in the first
- **THEN** the dashboard shows the second store's account

### Requirement: The address works once and briefly
The address SHALL sign in only the user it was made for, SHALL stop working once it has signed that user in, and SHALL stop working 60 seconds after it was made whether or not it was used. An address that no longer works SHALL sign nobody in and SHALL lead to the login page, where the password form is available. The address is not a sign-in link of the login page: its secret part signs nobody in there, whatever email goes with it.

#### Scenario: The address is opened a second time
- **WHEN** an address that already signed its user in is opened in another browser
- **THEN** that browser is not signed in and shows the login page

#### Scenario: The address is opened too late
- **WHEN** an address is opened after its 60 seconds have passed
- **THEN** the browser is not signed in and shows the login page

#### Scenario: The address with another email
- **WHEN** the secret part of an address made for one user is put into the login page's own sign-in link with another user's email in place of its user
- **THEN** nobody is signed in

### Requirement: The session is the helpdesk's own
A person who got in this way SHALL have an ordinary helpdesk session: it SHALL appear in their list of sessions, count against the installation's limit of sessions per user, last as long as any other session, and end when they sign out. It SHALL NOT end because the person left the Shopify admin or because the app was closed.

#### Scenario: The session is listed
- **WHEN** a user who got in from the app opens their profile's list of sessions
- **THEN** the session is listed like one started with a password

#### Scenario: The session outlives the Shopify admin
- **WHEN** a user who got in from the app signs out of the Shopify admin and reloads the helpdesk
- **THEN** they are still signed in to the helpdesk

### Requirement: A suspended account lets nobody in
A request for a store whose account is suspended SHALL be refused with the reason that the account is suspended, and SHALL give no address.

#### Scenario: The app was removed and the request still comes
- **WHEN** the app sends a valid request for a store whose account is suspended
- **THEN** the request is refused as "account suspended" and no address is given

### Requirement: Two-factor users use their password and code
A request for a user who has two-factor authentication turned on in the helpdesk, or who must turn it on because an account they belong to requires it, SHALL be refused with a reason that says so, and SHALL give no address. That user's password sign-in with the code SHALL work as before.

#### Scenario: A user with two-factor authentication
- **WHEN** the app sends a valid request naming the email of a user who turned on two-factor authentication
- **THEN** the request is refused as "sign in with your password and code", and the same user signs in on the login page with password and code

### Requirement: A user with a pending invitation gets in
A request for a user of the store's account who has not yet confirmed their invitation SHALL be answered with an address, and opening it SHALL sign them in and leave them confirmed. No password SHALL be set for them by this.

#### Scenario: An invited agent who never opened the invitation
- **WHEN** the app sends a valid request naming the verified email of a user invited to the store's account who has not confirmed, and the browser opens the address
- **THEN** the browser is signed in as that user and the user is confirmed

### Requirement: A signed request is used once
An entry request SHALL be signed as every provisioning request is, and SHALL carry a request key the helpdesk has not seen. The helpdesk SHALL refuse a request whose signature does not match or whose time is more than five minutes from its own, without saying which of them failed. It SHALL refuse a correctly signed request whose key it has seen in the last ten minutes, even with the same body, as a reused key. It SHALL give no address for a refused request.

#### Scenario: A captured request is sent again
- **WHEN** a correctly signed entry request that was already answered is sent a second time unchanged
- **THEN** it is refused as a reused request and no second address is given

#### Scenario: A request signed with another secret
- **WHEN** an entry request arrives with a signature made with another secret
- **THEN** it is refused as not authorised and no address is given

### Requirement: Attempts are limited
The helpdesk SHALL limit how many entry requests it accepts in a period for one store and for one person, and SHALL answer a request over the limit by saying when to try again, without giving an address. It SHALL also limit how many addresses are opened from one network address in a period; an opening over that limit signs nobody in and leads to the login page.

#### Scenario: One person asks too often
- **WHEN** valid requests naming the same person arrive faster than the limit for one person
- **THEN** the requests over the limit are answered with the time to try again and give no address

### Requirement: Attempts are recorded without the email, and the address is recorded nowhere
The helpdesk SHALL record each entry request with its time, the store's domain, its outcome (address given, not a user, two-factor, suspended, no account, refused, limited) and, when a user was found, that user's identifier, and SHALL record when an address signed its user in. The record SHALL NOT hold an email or a name. The helpdesk SHALL NOT write the one-time address or its secret part to any record or to a log line of its own.

#### Scenario: A refusal is recorded
- **WHEN** a request names an email that no user has
- **THEN** a record exists with the time, the store's domain and the outcome "not a user", without an email

#### Scenario: A given address is not kept
- **WHEN** a request is answered with an address
- **THEN** the record of it holds the user's identifier and the outcome, and neither the record nor the request log holds the address

### Requirement: Entry exists only where provisioning is enabled
An installation without the shared secret SHALL answer the entry address as an address that does not exist. The password login page SHALL work the same on every installation, with or without this way in.

#### Scenario: A self-hosted installation
- **WHEN** an entry request arrives at an installation that has no shared secret
- **THEN** it is answered as not found and no address is given
