## Purpose

Provide a consistent Inclamo staff interface that carries the approved operator design into the working helpdesk while preserving real customer-support workflows.

## ADDED Requirements

### Requirement: Consistent Inclamo identity

Staff surfaces SHALL use the supplied Inclamo logo, navy primary ink, sky-blue controls and selective orange accents. Light appearance SHALL use white main surfaces. Shared controls SHALL have consistent shape, hierarchy and interaction states.

#### Scenario: Brand across staff screens
- **WHEN** an operator opens conversations, contacts, reports, account settings or store settings
- **THEN** the same logo, palette, typography and control styles are applied
- **AND** visible content and available actions continue to reflect real account data and permissions

#### Scenario: Authentication and administration
- **WHEN** a user opens sign-in, password recovery, onboarding or installation administration
- **THEN** those surfaces use the same Inclamo visual identity
- **AND** their existing authentication, validation and authorization behavior is preserved

### Requirement: Operator layout follows the approved design

The workspace SHALL provide a clear branded navigation area, distinguishable selected conversation, readable message hierarchy, unified reply/note editor and cohesive customer/order information. It SHALL retain the native controls needed for supported channels and account capabilities.

#### Scenario: Work a real conversation
- **WHEN** an operator changes conversations, edits a draft, sends a reply or private note, or resolves a conversation
- **THEN** the native conversation state and actions operate normally within the new presentation
- **AND** no demo data, fake AI response or prototype-only action enters the working application

#### Scenario: Customer and order actions
- **WHEN** an operator opens customer details and an order action dialog
- **THEN** customer facts, order status, eligibility, validation and permitted actions remain accurate
- **AND** action pending, refused and failure states remain visible

### Requirement: Accessible and adaptable presentation

The staff design SHALL remain usable on desktop and narrow screens, with keyboard focus, meaningful state labels, right-to-left layout and the existing font-size preference. Text and actionable controls SHALL remain legible in supported appearances.

#### Scenario: Responsive operator workflow
- **WHEN** an operator uses the workspace at 1440px, 1024px or 390px width
- **THEN** navigation, conversation selection, the reply editor and customer details remain reachable
- **AND** the page does not require unintended horizontal scrolling

#### Scenario: Existing appearance and keyboard preferences
- **WHEN** an operator uses explicit dark or automatic appearance, an enlarged font, or keyboard navigation
- **THEN** the existing preference persists and visible controls retain usable contrast and focus
- **AND** dialogs preserve their existing focus and close behavior

### Requirement: Customer-facing brand boundaries

Merchant-facing widget, help-centre and survey experiences SHALL retain their configured merchant branding and SHALL NOT inherit staff navigation, pane geometry or staff-only layout rules.

#### Scenario: Leave the staff application
- **WHEN** a browser opens a widget, portal or satisfaction survey
- **THEN** customer-facing layout and merchant-configured colours remain effective
- **AND** staff-only styling is absent

### Requirement: Maintainable CE integration

The application SHALL continue to build from its pinned Community Edition source with owned overlays and documented presentation patches. The change SHALL preserve backend contracts and SHALL NOT require a second frontend runtime or remote design service.

#### Scenario: Build and exercise the product
- **WHEN** the pinned CE source is assembled and the production frontend is built
- **THEN** every presentation patch applies cleanly and native/overlay behavior checks pass
- **AND** real product screenshots demonstrate the approved visual direction across representative staff surfaces

#### Scenario: Performance and isolation
- **WHEN** the updated workspace is exercised against synthetic fixture data
- **THEN** it uses local fonts and brand assets without introducing a runtime dependency on the prototype or an external AI/design service
- **AND** asset size and representative interaction timings are recorded and compared with the previous build
