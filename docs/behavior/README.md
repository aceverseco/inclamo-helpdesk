# Behavior contracts

These contracts describe expected behavior for this source revision. They are
part of the public test interface and contain no development task state.
Update the corresponding contract and end-to-end tests together when behavior
changes. A contract describes an expectation; it is not a release certification.

Run `node scripts/check-e2e-coverage.mjs` from the repository root to check that
each scenario has a matching test and each mapped test names a scenario.
The checker fails if contracts are missing or empty. Explicit exceptions name
the alternative coverage in the checker. No private workspace is required.

- [conversation-order-panel](conversation-order-panel/spec.md)
- [helpdesk-visual-theme](helpdesk-visual-theme/spec.md)
- [in-product-support](in-product-support/spec.md)
- [inclamo-product-design](inclamo-product-design/spec.md)
- [reply-order-variables](reply-order-variables/spec.md)
- [shopify-connection](shopify-connection/spec.md)
- [store-data-rules](store-data-rules/spec.md)
- [website-widget-experience](website-widget-experience/spec.md)
- [website-widget-settings](website-widget-settings/spec.md)
- [workspace-brand-logo](workspace-brand-logo/spec.md)
- [workspace-widgets](workspace-widgets/spec.md)
