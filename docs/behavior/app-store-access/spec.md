# app-store-access

Behavior contract for this source revision.

An account the store app provisioned (`app-provisioned-account`) gets its
Shopify store without a Shopify app of the helpdesk's or the merchant's own:
the helpdesk asks the app for a short-lived key to the store, uses it for
everything a store connection does, renews it by itself, and tells the team
plainly when the app or the store stands in the way. The call itself is
described in `docs/app-store-access.md`; the operator's settings in
`docs/app-provisioning-setup.md`.

### Requirement: A provisioned account is connected to its store through the app

An account that the app provisioned SHALL have a connection to that store, made by the helpdesk without anyone entering a domain or credentials, when the account is created and when it is restored. The connection SHALL be saved only after a key from the app has been verified against that store: the store answers, it is the store the account was provisioned for, and the key holds `read_customers` and `read_orders`. When the connection cannot be made, the account SHALL exist without a connection, its panel SHALL say the store is not connected, and an administrator SHALL be able to ask again from the connection page. An account the app did not provision SHALL NOT be connectable this way.

#### Scenario: A new account

- **WHEN** the app provisions an account for a store and answers the helpdesk's request for a key with a key holding the read scopes
- **THEN** the account's connection page shows the store's name and domain as connected through the Inclamo app, and an agent who opens a conversation of a known customer sees their orders

#### Scenario: The app has no key at that moment

- **WHEN** the app provisions an account and does not answer the helpdesk's request for a key
- **THEN** the account exists, its panel says the store is not connected, and after an administrator presses "connect through the Inclamo app" while the app answers, the store is connected

#### Scenario: A key for another store

- **WHEN** the key the app hands out belongs to a store other than the one the account was provisioned for
- **THEN** nothing is saved and the connection page says the app answered for another store

#### Scenario: A key without a read scope

- **WHEN** the key the app hands out does not hold `read_orders`
- **THEN** nothing is saved and the connection page names `read_orders` as missing

#### Scenario: An account the app did not provision

- **WHEN** an administrator of an account made by an operator opens the connection page
- **THEN** connecting through the Inclamo app is not offered, and the credentials form is the way to connect

### Requirement: The helpdesk asks for no more than it can use

A request for a key SHALL name the scopes the helpdesk can use and no others. The helpdesk SHALL treat the scopes the app says it granted as the connection's scopes, and SHALL NOT assume a scope it asked for and was not granted.

#### Scenario: The app grants fewer scopes than asked

- **WHEN** the helpdesk asks for its scopes and the app grants only `read_customers`, `read_orders` and `write_orders`
- **THEN** the connection holds those three scopes, and the connection page lists cancel, refund, address change and the order's tags and note as available and every other action as unavailable with its missing scope

### Requirement: Granted scopes decide the actions as for any connection

For a connection through the app, each order action SHALL be available only when the connection's scopes include what that action needs, a missing scope SHALL be named, a request for an unavailable action SHALL be refused without calling Shopify, and a store that refuses customers' personal data SHALL be connected in the limited mode, all as the store connection already behaves. A missing scope SHALL be explained as a permission of the Inclamo app in Shopify, not as something to change in an app of the merchant's. When the store refuses the key a scope, the helpdesk SHALL ask the app for a new key and take the scopes it carries.

#### Scenario: A direct request for an action the key does not allow

- **WHEN** the connection through the app holds no `write_discounts` and a request is made to create a discount code
- **THEN** it is refused naming `write_discounts`, and Shopify receives no request

#### Scenario: The store hides customer data from the app

- **WHEN** the store refuses customers' personal data to a key from the app
- **THEN** the connection is saved as limited, and the panel works by order number only

#### Scenario: The app's permissions grow

- **WHEN** the Inclamo app is given `write_order_edits` at the store and an administrator presses "check again"
- **THEN** the helpdesk asks the app for a new key, and editing items becomes available

### Requirement: The key is renewed without anyone noticing

The helpdesk SHALL ask the app for a new key before the current one stops working, and SHALL NOT use a key past the time the app gave for it. Requests made at the same moment SHALL lead to one renewal. A key the store refuses SHALL be replaced by a new one from the app once, and the refused request repeated once, before the connection is marked broken.

#### Scenario: An agent works across the key's end

- **WHEN** an agent opens an order while the key has two minutes left and refunds it ten minutes later
- **THEN** both succeed, the helpdesk asked the app for a key in between, and the agent saw nothing of it

#### Scenario: Many agents at the moment of renewal

- **WHEN** ten panels read the store at the moment the key needs renewing
- **THEN** all ten are answered and the app received one request for a key

#### Scenario: The store refuses a key that should still work

- **WHEN** the store answers a request with an authentication error while the key's time has not passed, and the app hands out a new key that the store accepts
- **THEN** the request succeeds on its second attempt and the connection stays working

#### Scenario: The store refuses the new key too

- **WHEN** the store refuses a request, the app hands out a new key, and the store refuses that one as well
- **THEN** the connection is marked broken and the panel says the store connection needs attention

### Requirement: An app that does not answer is not a broken connection

While the helpdesk holds a key that still works, the store's data SHALL be served whether or not the app answers. When the key's time has passed and the app does not answer, or answers that it cannot serve now, the panel SHALL say the store's data is temporarily unavailable and SHALL show no orders from an earlier answer; the connection SHALL stay working, and the next request for store data SHALL ask the app again, no more often than once in a pause of 30 seconds per connection (or the longer wait the app asked for). A conversation that arrives meanwhile SHALL be handled as one whose store is silent.

#### Scenario: The app is down within the key's time

- **WHEN** the app stops answering while the helpdesk's key has thirty minutes left
- **THEN** the panel shows orders and order actions work

#### Scenario: The app is down after the key's time

- **WHEN** the app does not answer and the key's time has passed
- **THEN** the panel says the store's data is temporarily unavailable, shows no orders, and the connection page still shows the connection as working with the time of the last successful key

#### Scenario: The app comes back

- **WHEN** the app answers again and an agent opens a conversation
- **THEN** the panel shows the customer's orders without anyone pressing "check again"

### Requirement: The app's removal from the store breaks the connection and says why

When the app answers that the store does not have it installed, the connection SHALL be marked broken, the panel SHALL say the Inclamo app was removed from the store, and an administrator SHALL be told to install the Inclamo app again in Shopify; the credentials form SHALL NOT be offered as the remedy. When the app answers that the account is not the one it provisioned for that store, the connection SHALL be marked broken and the administrator SHALL be told to contact support. The record of past order actions SHALL remain in both cases.

#### Scenario: The store uninstalled the app

- **WHEN** the helpdesk asks for a key and the app answers that the store does not have the app
- **THEN** the panel shows no orders and says the Inclamo app was removed from the store, the connection page tells the administrator to install it again, and earlier action records are still listed

#### Scenario: The app is installed again

- **WHEN** the store installs the app again and an administrator presses "check again"
- **THEN** the connection works again with the scopes the new key holds

### Requirement: The connection through the app belongs to the app

In an account the app provisioned, an administrator SHALL be able to read the connection and to check it again, and SHALL NOT be able to remove it, to connect another store, or to replace it with credentials of an app of their own. An agent who is not an administrator SHALL be able to read what is connected and nothing more.

#### Scenario: An administrator tries to connect another store

- **WHEN** an administrator of an account connected through the app submits a domain and credentials to the connection endpoint
- **THEN** the request is refused, and the connection through the app is unchanged

#### Scenario: An agent presses nothing

- **WHEN** a user with the agent role opens the connection page of an account connected through the app
- **THEN** they see the store, its scopes and the time of the last check, and "check again" is refused to them

### Requirement: The key is a secret

A key from the app SHALL be stored encrypted at rest, SHALL NOT be returned by any endpoint or sent to a browser, and SHALL NOT be written to a log, a note, an error message or the record of an attempt. The request for a key SHALL be signed with the secret the helpdesk shares with the app and SHALL be sent only to the app's address for that store: the one the app gave when it provisioned the store, else the address the operator configured. When the account is suspended the stored key SHALL be deleted. On an installation without encryption keys, without the shared secret or without an address of the app, no connection through the app SHALL be made.

#### Scenario: Reading the connection

- **WHEN** an administrator opens the connection page of an account connected through the app
- **THEN** the domain, the store's name, the scopes, the time of the last check and the time the key was last renewed are shown, and no key is in the page or in the answer behind it

#### Scenario: The account is suspended

- **WHEN** the app's removal notice suspends an account connected through the app
- **THEN** no key is stored for it any more, and the record of past order actions remains

#### Scenario: An installation without the app's address

- **WHEN** an account is provisioned on an installation that has the shared secret and no address of the app
- **THEN** the account exists without a store connection, and no request for a key is sent anywhere

### Requirement: Requests for a key are recorded without the key

The helpdesk SHALL record each request for a key with its time, the account, the store's domain and its outcome (granted, refused with the app's reason, no answer), and SHALL NOT record the key or the signature. A refusal that says the two sides disagree on the shared secret SHALL also be reported to the operator.

#### Scenario: A refusal is recorded

- **WHEN** the app answers a request for a key that the store does not have the app
- **THEN** a record exists with the time, the account, the store's domain and that reason, and without a key or a signature
