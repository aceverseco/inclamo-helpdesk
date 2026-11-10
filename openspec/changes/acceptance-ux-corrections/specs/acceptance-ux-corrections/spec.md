## Purpose
Resolve concrete privacy and confirmation defects found during helpdesk acceptance.
## ADDED Requirements
### Requirement: Unpublished articles require authorized preview
Unpublished article content SHALL be unavailable at anonymous public URLs. Account members authorized to read the article SHALL retain editor preview through a short-lived signed URL bound to that article and account. Invalid and expired preview URLs SHALL expose no draft content; successful previews SHALL prevent caching and referrer disclosure.
#### Scenario: Private draft with authorized editor preview
- **WHEN** an anonymous reader opens a draft URL and an authorized editor requests preview
- **THEN** the anonymous request returns 404 and the signed editor preview renders the draft
### Requirement: Cancellation confirmation states its refund effect
The direct cancellation dialog SHALL load the current refund amount and currency or an explicit no-payment state. Loading and unknown amounts SHALL prevent confirming a refund. A failed preview SHALL be visible and retryable; selecting no refund SHALL make that choice explicit. Existing server permissions SHALL apply to the preview too.
#### Scenario: Fresh cancellation amount and preview recovery
- **WHEN** a staff member opens cancellation and a preview request fails before succeeding on retry
- **THEN** the dialog blocks premature confirmation, explains the failure and displays the current refund amount after retry
