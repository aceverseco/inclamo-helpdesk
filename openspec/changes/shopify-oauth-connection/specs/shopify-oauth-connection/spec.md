## Purpose

How an account's Shopify store is connected through a Shopify app the operator owns rather than an app of the merchant's: the consent flow started from the helpdesk or from Shopify, the checks on every redirect, expiring tokens and their renewal, the app's removal at the store, growing permissions, and how the operator configures the app. Every rule of the `shopify-connection` capability about scopes, limited mode, secrets, one store per account, broken connections and removal applies to a connection made this way.

## ADDED Requirements

### Requirement: The operator gives an account a Shopify app
The operator SHALL be able to give an account the client ID and client secret of a Shopify app the operator owns, together with the one store domain the app is meant for, by a command on the server. No endpoint and no page SHALL let a merchant's user set, read or change them. The store connection dialog SHALL offer "Connect with Shopify" to administrators only when the account has such an app, and SHALL keep the form for the merchant's own app credentials as a second way in. Without an operator app the dialog SHALL be the credentials form alone, as it is today.

#### Scenario: Account with an operator app
- **WHEN** an administrator of an account that has an operator app opens the store connection dialog
- **THEN** the dialog offers "Connect with Shopify" for the store the app is meant for, and the credentials form as the other way in

#### Scenario: Account without an operator app
- **WHEN** an administrator of an account without an operator app opens the store connection dialog
- **THEN** the dialog is the credentials form alone and no "Connect with Shopify" is shown

### Requirement: An administrator connects the store through Shopify's consent
"Connect with Shopify" SHALL send the administrator to Shopify's consent screen for the store the operator app is meant for, asking for the helpdesk's scope list. When the store's user approves, the helpdesk SHALL obtain the store's tokens, check them as a connection made with credentials is checked (the mandatory read scopes, the store's customer data, the store's answer to its orders), save the connection, and show the administrator the store's name, its domain and the actions its scopes allow. A write scope that Shopify returns without its read scope SHALL count as that read scope as well. When the store's user does not approve, nothing SHALL be saved. A user who is not an administrator SHALL NOT be able to start the flow.

#### Scenario: Consent approved
- **WHEN** an administrator presses "Connect with Shopify" and the store's user approves the access on Shopify's screen
- **THEN** the administrator comes back to the helpdesk, the connection is saved as made through the Shopify app, the store's name, domain and available actions are shown, and the panel shows the customer's orders

#### Scenario: Consent declined
- **WHEN** the store's user leaves Shopify's screen without approving and Shopify sends them back without an authorization code
- **THEN** nothing is saved, and the helpdesk says that the access was not approved and offers to start again

#### Scenario: Write scope returned without its read scope
- **WHEN** Shopify grants `write_orders` and lists it without `read_orders`
- **THEN** the connection is saved, `read_orders` counts as granted, and cancel, refund and address change are available

#### Scenario: An agent starts the flow
- **WHEN** a user with the agent role calls the endpoint that starts "Connect with Shopify"
- **THEN** the request is refused as forbidden and no consent screen is offered

### Requirement: Every redirect from Shopify is verified before anything is kept
Before exchanging an authorization code or acting on Shopify's request to the app address, the helpdesk SHALL verify Shopify's signature over the request's parameters with the app's client secret, and SHALL check that the store domain is a `<name>.myshopify.com` domain and the store the app is meant for. A callback SHALL carry a one-time state that the helpdesk issued to the same browser less than ten minutes before; a state that is unknown, used, expired or issued to another browser SHALL be refused. A refused redirect SHALL exchange no code, save nothing and say what to do next.

#### Scenario: Tampered signature
- **WHEN** a callback arrives whose signature does not match its parameters
- **THEN** no code is exchanged, nothing is saved, and the page says the request did not come from Shopify

#### Scenario: State from another browser
- **WHEN** a callback carries a state that the helpdesk issued to a different browser
- **THEN** no code is exchanged, nothing is saved, and the page asks to start the connection again from the helpdesk

#### Scenario: Expired state
- **WHEN** a callback arrives more than ten minutes after its state was issued
- **THEN** no code is exchanged, nothing is saved, and the page asks to start again

#### Scenario: Another store than the app is meant for
- **WHEN** a callback names a store that is not the one the account's operator app is meant for
- **THEN** no code is exchanged, nothing is saved, and the page names the store the app is meant for

### Requirement: Installing the app from Shopify connects the account assigned to that store
When Shopify brings a store's user to the helpdesk's app address, after the checks above, the helpdesk SHALL find the account whose operator app is meant for that store. If that account has no connection, the helpdesk SHALL take the user through the same consent and connect that account, with no sign-in to the helpdesk; at the end a page SHALL say the store is connected and link to the helpdesk. If the account is connected already, the helpdesk SHALL NOT ask for consent again and SHALL send the user on to the helpdesk. If no account is assigned to the store, nothing SHALL be connected and the page SHALL say so.

#### Scenario: Owner installs from the install link
- **WHEN** the owner of the store an account's operator app is meant for opens the app's install link and approves the access
- **THEN** that account's store is connected and the page says so and links to the helpdesk

#### Scenario: Store no account is assigned to
- **WHEN** Shopify brings the user of a store that no account's operator app is meant for to the app address
- **THEN** nothing is connected and the page says this helpdesk is not set up for that store

#### Scenario: Connected store opens the app
- **WHEN** a user of a connected store opens the app from the Shopify admin
- **THEN** no consent is asked and the user is sent on to the helpdesk

### Requirement: Tokens expire and are renewed without anyone noticing
A connection made through the operator app SHALL hold an access token that expires and a refresh token, and SHALL renew the access token before it expires, one renewal at a time per connection, keeping the refresh token Shopify returns in place of the one used. Connections nobody uses SHALL be renewed in the background before their refresh token expires. When Shopify refuses a renewal, the connection SHALL be marked broken under the rules of `shopify-connection`, and an administrator SHALL see "Reconnect with Shopify", which goes through the consent again.

#### Scenario: Access token expired
- **WHEN** an agent opens a conversation after the connection's access token has expired
- **THEN** the panel shows the customer's orders, and the connection holds a new access token and a new refresh token

#### Scenario: Account nobody opens
- **WHEN** a connection's refresh token has less than a week left and no one has used the connection
- **THEN** the background renewal obtains new tokens and the refresh token's expiry moves forward

#### Scenario: Renewal refused
- **WHEN** Shopify refuses the connection's refresh token
- **THEN** the connection is marked broken, the panel says the store connection needs attention, and an administrator sees "Reconnect with Shopify"

### Requirement: The app's removal at the store is noticed
The helpdesk SHALL receive Shopify's notice that the app was uninstalled from the store, verified by Shopify's signature over the notice's body with the app's client secret. On a verified notice the connection's tokens SHALL be deleted and the connection SHALL be shown as removed from the store: the panel shows no orders and says the Shopify app was removed from the store, and an administrator sees "Connect with Shopify". Records of earlier order actions SHALL stay. A notice whose signature does not verify SHALL be refused as unauthorised and SHALL change nothing; a notice received twice SHALL change nothing the second time.

#### Scenario: Merchant uninstalls the app
- **WHEN** the store's owner uninstalls the operator app and Shopify sends the notice
- **THEN** the connection holds no tokens, the panel says the Shopify app was removed from the store, an administrator sees "Connect with Shopify", and earlier order action records are still there

#### Scenario: Notice with a wrong signature
- **WHEN** a notice of uninstallation arrives whose signature does not match its body
- **THEN** the helpdesk answers unauthorised and the connection is unchanged

### Requirement: Permissions that grow are asked for again
When the helpdesk's scope list holds scopes a connection made through the operator app has not been granted, the actions needing them SHALL stay unavailable under the rules of `shopify-connection`, and an administrator SHALL see "Update permissions", which goes through Shopify's consent again with the full scope list and then reads the granted scopes. When Shopify notifies the helpdesk that the app's scopes changed at the store, the helpdesk SHALL read the connection's scopes again.

#### Scenario: A release needs a new scope
- **WHEN** the helpdesk's scope list gains a scope the connection lacks
- **THEN** the actions needing it are shown as unavailable naming the scope, an administrator sees "Update permissions", and after approving on Shopify's screen the actions become available

#### Scenario: Scopes changed at Shopify
- **WHEN** Shopify notifies the helpdesk that the app's scopes changed at the store
- **THEN** the connection's scopes are read again and the panel's available actions follow them

### Requirement: The operator's secret and the tokens stay secret
The operator app's client secret, every access token and every refresh token SHALL be stored encrypted at rest and SHALL NOT be returned by any endpoint, shown in any page, or written to logs, notes or error messages. On an installation without encryption keys, the server command SHALL refuse to set an operator app, and no "Connect with Shopify" SHALL be offered.

#### Scenario: Reading a connection made through the app
- **WHEN** an administrator opens a connection made through the operator app
- **THEN** the domain, the store's name, the scopes, the way it was made and the time of the last check are shown, and neither the app's secret nor any token is

#### Scenario: Installation without encryption keys
- **WHEN** the operator runs the command that sets an operator app on an installation without encryption keys
- **THEN** nothing is saved and the command says encryption must be configured first

### Requirement: Shopify's compliance requests are verified and recorded
The helpdesk SHALL receive Shopify's three compliance requests (a customer's data request, a customer's erasure, the store's erasure), SHALL refuse one whose signature does not verify as unauthorised, and SHALL record a verified one for the operator, without its personal data, and answer that it was received. This change SHALL NOT erase data on these requests.

#### Scenario: Compliance request arrives
- **WHEN** Shopify sends a verified request to erase a customer's data
- **THEN** the helpdesk answers that it was received and the operator can see that the request came, for which store and when

### Requirement: One store connection, two ways into it
A connection made through the operator app SHALL be the account's one store connection, the same as a connection made with credentials. An administrator SHALL be able to replace a connection made with credentials by "Connect with Shopify" for the same store; the earlier credentials SHALL then be deleted. Connecting a different store through the app SHALL be refused until the existing connection is removed.

#### Scenario: From credentials to the Shopify app
- **WHEN** an administrator of an account connected with its own app's credentials connects the same store through the operator app
- **THEN** the connection is made through the Shopify app, the earlier credentials are deleted, and the panel works as before

#### Scenario: A different store
- **WHEN** an administrator of an account connected to one store tries to connect another store through the operator app
- **THEN** nothing changes and the dialog says the existing connection must be removed first
