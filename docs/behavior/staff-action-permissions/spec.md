# staff-action-permissions

Behavior contract for this source revision.

### Requirement: Independent staff action rights

Only an account administrator SHALL manage the account's staff grants. Address changes, item editing, cancellation, refunds, new orders, replacements, discounts, order/customer tags and order/customer notes SHALL be independently grantable. Administrators SHALL retain these rights by their account role. New staff SHALL have no write grants. Existing broad grants SHALL retain the operations they already granted; discount-code grants SHALL remain separate. Unknown actions and malformed updates SHALL be rejected.

#### Scenario: Address-only staff member

- **WHEN** an administrator grants only address changes to a staff member
- **THEN** that member can change an eligible order address but cannot cancel, refund, edit items, create orders or issue discounts

#### Scenario: Another account and non-admin cannot grant

- **WHEN** a non-administrator changes grants or an administrator names a member of another account
- **THEN** the request is refused without changing any grant

#### Scenario: Preserve existing grants

- **WHEN** an existing broad order-actions grant is migrated
- **THEN** its existing order operations remain allowed and no new discount-code grant is silently added

### Requirement: Every execution path enforces current rights

The server SHALL enforce current action rights before previews and writes from dialogs, macros, retries and AI approvals. A cancellation with a refund SHALL require both cancellation and refund rights. A new order with a discount SHALL require new-order and discount rights. Item editing SHALL not itself refund money; its follow-up refund SHALL require refund rights. Revocation SHALL affect an already-open dialog and an unsettled retry. A settled retry SHALL return its existing outcome without another write.

#### Scenario: Refund through a cancellation

- **WHEN** staff with cancellation but no refund right request a cancellation with refund enabled
- **THEN** the request is refused before any Shopify mutation

#### Scenario: Permission revoked during a dialog

- **WHEN** an administrator revokes the action right after a staff member opened its dialog
- **THEN** submitting that dialog does not change Shopify

#### Scenario: Concurrent grant edits

- **WHEN** two administrators update different action grants for the same member
- **THEN** each acknowledged change is retained without overwriting the other

### Requirement: Controls reflect individual rights

Settings SHALL show each member's independent rights and identify administrator access. Conversation actions SHALL reflect their individual permissions, including separate tag and note controls. A failed grant save SHALL retain the last confirmed value, explain the failure and allow retry. The same controls SHALL be reusable during onboarding.

#### Scenario: Failed permission save

- **WHEN** saving an action grant fails
- **THEN** the checkbox returns to its confirmed state and a visible error remains until a successful retry
