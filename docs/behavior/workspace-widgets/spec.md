# workspace-widgets

Behavior contract for this source revision.

### Requirement: Catalog and supported placements

The workspace SHALL offer a catalog of available widgets with a name, description and supported placement. The supported placements SHALL be the conversation's right sidebar and the workspace header's icon bar. Users SHALL add and remove catalog widgets without installing code or configuring external endpoints. Removing a widget SHALL affect its placement, not its underlying data or integration.

#### Scenario: Add and remove a card

- **WHEN** an agent adds the order list to the right sidebar and later removes it
- **THEN** the card appears and disappears in that agent's layout without deleting orders or disconnecting the store
- **AND** it remains available to add again

#### Scenario: Unsupported placement

- **WHEN** an agent attempts to place an order-list card in the header icon bar
- **THEN** the placement is rejected without changing the saved layout

### Requirement: Initial widgets use existing data

The first release SHALL provide customer profile, purchase statistics and order-list widgets for the right sidebar, and a native-notifications widget for the header. Statistics SHALL show the matched customer's order count and total spent with currency when available. The order-list widget SHALL preserve existing customer matching, linked-order selection, pagination and permitted order actions.

#### Scenario: A customer has commerce data

- **WHEN** an agent opens an accessible conversation with a matched store customer
- **THEN** the enabled cards show that contact's profile, actual purchase statistics and orders
- **AND** the explicitly linked order is distinguished from an unlinked latest order

#### Scenario: Missing or ambiguous commerce data

- **WHEN** the store is unavailable, matching is ambiguous or no customer is found
- **THEN** affected widgets show the relevant existing state and available recovery or selection action
- **AND** they do not fabricate a zero purchase count, currency or successful connection

### Requirement: Personal layout persistence

Each account member SHALL be able to add, remove and reorder widgets and collapse sidebar cards in their own workspace. These preferences SHALL persist across reloads and sessions within that account. The member SHALL be able to restore the current account default, or the product default when the account has none.

#### Scenario: Personalization survives reload

- **WHEN** an agent changes card order, removes a widget, collapses another card and reloads
- **THEN** the saved choices are restored for that account without changing another member's layout

#### Scenario: Account switch and reset

- **WHEN** a user personalizes account A and switches to account B
- **THEN** account B uses its own effective layout
- **AND** resetting in account B does not modify account A's preferences

### Requirement: Administrator layout management

An account administrator SHALL be able to save an account default, configure a current member's layout, and explicitly apply a layout to all current members of that account. Saving a default SHALL preserve existing personal overrides. Applying to a member or all members SHALL identify the affected users and replacement of personal choices before confirmation. Affected members SHALL remain able to personalize their layout afterwards.

#### Scenario: Change the default

- **WHEN** an administrator saves an account default without choosing to replace member layouts
- **THEN** members without personal overrides and new members use that default
- **AND** existing personal overrides remain unchanged

#### Scenario: Apply to all members

- **WHEN** an administrator confirms applying a layout to all current account members
- **THEN** those members receive the layout, including replacement of prior overrides
- **AND** members can subsequently change their own layout
- **AND** other accounts remain unchanged

#### Scenario: Unauthorized or conflicting edit

- **WHEN** a non-administrator attempts to change another member's layout, or a save uses an outdated layout revision
- **THEN** the unauthorized request is rejected or the conflict is surfaced respectively
- **AND** the newer authorized layout is not silently overwritten

### Requirement: Permissions remain authoritative

Widget configuration SHALL NOT grant access to contacts, conversations, notifications or commerce actions. Data and actions SHALL retain their existing server-side authorization. Administrative layout operations SHALL be limited to the administrator's current account membership. Widget availability SHALL be reevaluated after account or permission changes.

#### Scenario: An administrator assigns a layout to a restricted agent

- **WHEN** the layout includes orders but the agent lacks permission to perform a refund
- **THEN** placing the order widget does not permit the refund through either the interface or its API

#### Scenario: Notification scope

- **WHEN** an agent views the notification widget
- **THEN** its count and entries include only that agent's authorized native notifications

### Requirement: Header indicators are informative and actionable

The header SHALL render enabled icon widgets in stable user-defined order between workspace navigation and user tools. Each icon SHALL have an accessible name, an informative tooltip and a visible focus state. The notifications widget SHALL show the native unread count and open the existing notification experience. Count changes SHALL NOT move the icon or mark notifications read by themselves. Color SHALL NOT be the sole means of conveying state.

#### Scenario: New notification arrives

- **WHEN** the native notification count changes while the agent is composing a reply
- **THEN** the header badge updates without changing focus, draft contents or icon order
- **AND** selecting the icon opens the corresponding native notification destination

#### Scenario: Header space is limited

- **WHEN** the available width cannot fit all enabled icons
- **THEN** remaining icons are reachable through an accessible overflow control without obscuring account navigation, the profile or message composition

### Requirement: Optional widgets preserve essential workflows

Hiding optional cards SHALL NOT make essential customer, conversation or commerce tools permanently unreachable. The existing Manage area or equivalent native route SHALL retain access to permitted contact details/actions, order access, labels, assignment, notes, attributes, files and history. Opening configuration or changing a layout SHALL preserve the conversation selection and unsent message draft.

#### Scenario: Agent hides all customer cards

- **WHEN** an agent removes the three initial sidebar cards
- **THEN** the sidebar presents an add-widget affordance and permitted underlying tools remain reachable through Manage
- **AND** sending a reply, managing the conversation and accessing an order still work

### Requirement: Context and failures stay isolated

Widgets SHALL display data for the currently selected account, conversation and contact only. A delayed response from a previous context SHALL NOT populate the new context. A widget's loading or failure state SHALL NOT prevent other widgets, navigation or the composer from functioning.

#### Scenario: Agent changes conversations during loading

- **WHEN** data for conversation A arrives after the agent selects conversation B
- **THEN** it is not displayed as conversation B's customer or order information

#### Scenario: One card fails

- **WHEN** order loading fails
- **THEN** that card shows its failure state while customer navigation, notifications and composing a reply remain usable

### Requirement: Catalog evolution preserves user choices

An upgrade adding a widget SHALL make it available in the catalog without automatically inserting it into existing personalized layouts. Saved entries for unavailable widgets SHALL NOT crash the workspace or prevent configuration. Other valid choices SHALL survive catalog changes.

#### Scenario: A later release adds a widget

- **WHEN** the catalog gains a new supported widget
- **THEN** an existing member can add it explicitly and their saved layout otherwise remains unchanged

#### Scenario: A widget becomes unavailable

- **WHEN** a saved layout references a widget absent from the installed release
- **THEN** the workspace safely omits that entry and configuration identifies it as unavailable while preserving valid entries

### Requirement: Existing appearance and input modes remain supported

Widget surfaces and configuration SHALL follow the current Inclamo appearance and remain usable with keyboard navigation, light/dark themes, RTL and narrow screens. Reordering SHALL have a keyboard-operable alternative to dragging.

#### Scenario: Configure without a pointer

- **WHEN** an agent opens configuration using the keyboard
- **THEN** the agent can add, remove, reorder and save widgets and return focus to the invoking control

#### Scenario: Narrow conversation view

- **WHEN** the workspace is opened on a narrow screen
- **THEN** cards remain accessible through the existing responsive panel behavior and the header does not obstruct the conversation
