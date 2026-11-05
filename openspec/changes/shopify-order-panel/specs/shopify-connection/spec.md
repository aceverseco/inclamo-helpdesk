## Purpose

How a merchant connects one Shopify store to a helpdesk account with the credentials of a custom app of their own, what is checked and kept, how the granted scopes and the store's plan decide what the panel can do, and how the connection is removed.

## ADDED Requirements

### Requirement: An administrator connects a store with a custom app's credentials
An administrator of the account SHALL be able to connect one Shopify store by entering the store's `myshopify.com` domain and the credentials of a custom app of the merchant's own: either the client ID and client secret of an app created in the merchant's Dev Dashboard and installed on the store, or the Admin API access token of a legacy custom app created in the store's admin. The connection SHALL be saved only after the credentials have been verified against that store. With a client ID and secret the helpdesk SHALL obtain and renew the store's short-lived access tokens by itself, without any action of the merchant. An agent who is not an administrator SHALL NOT be able to connect, change or remove the connection.

#### Scenario: Valid client ID and secret
- **WHEN** an administrator submits a valid domain with the client ID and secret of an app installed on that store
- **THEN** the connection is saved, and the administrator sees the store's name, its domain and the list of actions available with the granted scopes

#### Scenario: Valid legacy token
- **WHEN** an administrator submits a valid domain and a legacy custom app token that the store accepts
- **THEN** the connection is saved the same way

#### Scenario: Token renewal
- **WHEN** a connection made with a client ID and secret is used more than 24 hours after the last token was issued
- **THEN** the helpdesk has obtained a new token by itself, and the agent notices nothing

#### Scenario: App not installed on the store
- **WHEN** an administrator submits a client ID and secret of an app that is not installed on that store
- **THEN** nothing is saved, and the form says the app must be installed on the store first

#### Scenario: Token the store refuses
- **WHEN** an administrator submits a token that the store answers with an authentication error
- **THEN** nothing is saved, and the form says the store refused the token

#### Scenario: Domain that is not a Shopify store domain
- **WHEN** an administrator submits a domain that is not of the form `<name>.myshopify.com`
- **THEN** nothing is sent to Shopify, nothing is saved, and the form names the expected form of the domain

#### Scenario: An agent tries to connect
- **WHEN** a user with the agent role calls the connection endpoint
- **THEN** the request is refused as forbidden and nothing is saved

### Requirement: The read scopes are mandatory
The connection SHALL require the scopes `read_customers` and `read_orders`. A token without either SHALL NOT be saved, and the form SHALL name the missing scope.

#### Scenario: Token without read_orders
- **WHEN** an administrator submits a valid token whose scopes lack `read_orders`
- **THEN** nothing is saved, and the form names `read_orders` as missing

### Requirement: Write scopes decide which actions exist
Each order action SHALL be available only when the connection holds the scope it needs: `write_orders` for cancel, refund and address change, `write_orders` together with `write_draft_orders` and `read_products` for the replacement order. An action whose scope is missing SHALL be shown as unavailable with the name of the missing scope, and a request to perform it SHALL be refused without calling Shopify.

#### Scenario: Read-only token
- **WHEN** the connection holds only `read_customers` and `read_orders`
- **THEN** the panel shows orders, every action is shown as unavailable naming its missing scope, and a direct request to cancel an order is refused

#### Scenario: Scopes change at the store
- **WHEN** the merchant adds `write_orders` to the custom app and an administrator presses "check again"
- **THEN** the connection's scopes are read again from the store, and cancel, refund and address change become available

### Requirement: A store that hides customer data is connected in a limited mode
Shopify does not give a merchant's own custom app the personal data of customers (name, email, phone, addresses) on every plan. When the store refuses that data, the connection SHALL still be saved, marked as limited, and the administrator SHALL be told why and what the store's plan must allow for the full panel. In the limited mode the panel SHALL work by order number only, as the order-panel capability describes.

#### Scenario: Store whose plan hides customer data
- **WHEN** an administrator connects a store that refuses customer personal data to custom apps
- **THEN** the connection is saved as limited, and the administrator sees that customer matching, names and addresses are unavailable on this store and why

### Requirement: An app the store refuses its orders is not connected
Shopify gives a store's orders, draft orders and customers only to an app for which a distribution method has been chosen, and it refuses them only when the store has some to return. When the store refuses the app its orders, the connection SHALL NOT be saved and the form SHALL say that the store refuses the app its orders and that the app needs custom distribution. When a store that was connected begins to refuse, the panel SHALL show no orders, SHALL say that Shopify refuses the connected app, and SHALL tell an administrator what to change at the store and offer "check again". The connection SHALL stay saved.

#### Scenario: App with no distribution method
- **WHEN** an administrator submits the credentials of an app for which no distribution method was chosen, for a store that has orders
- **THEN** nothing is saved, and the form says that the store refuses the app its orders and names custom distribution

#### Scenario: Store starts refusing after it was connected
- **WHEN** a store that was connected while it had no orders or customers refuses the app a customer while the panel reads
- **THEN** the panel shows no orders and no lookup, says that Shopify refuses the connected app, tells the administrator to choose custom distribution, and after "check again" on a store that answers the panel works again

### Requirement: The credentials are a secret
The client secret and every access token SHALL be stored encrypted at rest and SHALL NOT be returned by any endpoint, shown in the interface after saving, or written to logs, notes or error messages. If the installation has no encryption keys configured, connecting SHALL be refused with a message that says so.

#### Scenario: Reading the connection
- **WHEN** an administrator opens the connection after saving it
- **THEN** the domain, store name, scopes and the time of the last check are shown, and neither the secret nor any token is

#### Scenario: Installation without encryption keys
- **WHEN** an administrator tries to connect a store on an installation that has no encryption keys configured
- **THEN** nothing is saved, and the form says encryption must be configured first

### Requirement: One store per account
An account SHALL hold at most one store connection. Connecting a second store SHALL be refused until the first is removed. A store SHALL be connectable to more than one account only if each connection is made with its own credentials.

#### Scenario: Second store
- **WHEN** an administrator of an account that already has a connection submits another domain
- **THEN** the request is refused, and the form says the existing connection must be removed first

### Requirement: A connection that stops working is reported, not hidden
When Shopify answers a request with an authentication error, the connection SHALL be marked as broken, the panel SHALL say the store connection needs attention, and administrators SHALL see how to reconnect. Order data SHALL NOT be served from an earlier answer once the connection is marked broken.

#### Scenario: Token revoked at the store
- **WHEN** the merchant uninstalls the custom app and an agent opens a conversation
- **THEN** the panel shows that the store connection is broken, no orders are shown, and an administrator sees the reconnect action

### Requirement: Removing the connection removes the secret
An administrator SHALL be able to remove the connection. Removal SHALL delete the stored credentials, tokens and scopes. The record of past order actions SHALL remain.

#### Scenario: Removal
- **WHEN** an administrator removes the connection and confirms
- **THEN** the credentials and tokens are deleted, the panel returns to its "not connected" state, and earlier action records and private notes are still there
