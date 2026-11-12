# workspace-brand-logo

Behavior contract for this source revision.

### Requirement: Supplied combined logo in the expanded workspace

The upper-left brand area of the expanded staff workspace SHALL display the complete user-supplied `inclamo_logo_text_500.jpg` image, including its original wordmark, proportions, colors and white background. It SHALL replace the previous symbol-plus-typed-text presentation without adding a second wordmark. The image SHALL have an accessible Inclamo name and be served as a local product asset.

#### Scenario: Administrator opens the workspace

- **WHEN** the expanded workspace is displayed
- **THEN** the supplied combined image appears at the upper left without cropping, stretching, recoloring or separately typed duplicate text

### Requirement: Responsive brand presentation preserves navigation

The combined image SHALL fit within the sidebar width and allow navigation, account switching and profile controls to remain reachable on short screens. The compact sidebar SHALL retain the existing legible symbol-only presentation. This change SHALL NOT replace favicons or merchant-configured website-widget images.

#### Scenario: Compact or short workspace

- **WHEN** the sidebar is collapsed or the available height is reduced
- **THEN** its branding remains legible and navigation/account/profile controls remain accessible without layout overlap

#### Scenario: Customer widget has its own branding

- **WHEN** the staff workspace logo is replaced
- **THEN** a configured customer widget retains its own logo, icon and colors

### Requirement: Consistent logo on the login page

The login page SHALL display the same complete supplied combined image above the native form, at 96 × 96 px, in light and dark themes. The expanded sidebar SHALL use a smaller 64 × 64 px presentation. This presentation change SHALL preserve native authentication and the compact sidebar symbol.

#### Scenario: User opens the login page

- **WHEN** a visitor opens the login page on a desktop or mobile screen
- **THEN** the complete logo appears once, retains its proportions and colors, and the login fields and submit action remain reachable

### Requirement: Consistent logo in SuperAdmin

The SuperAdmin navigation and standalone authentication page SHALL display the same complete supplied image. Navigation SHALL retain its native compact header, release link and update indicator without a duplicate typed product wordmark. The standalone page SHALL use a 96 × 96 px image.

#### Scenario: SuperAdmin signs in and opens the console

- **WHEN** the administrator opens the SuperAdmin sign-in page and authenticates
- **THEN** the supplied logo appears on the form and in the console navigation, in both themes and on narrow screens, while native authentication and release information remain available
