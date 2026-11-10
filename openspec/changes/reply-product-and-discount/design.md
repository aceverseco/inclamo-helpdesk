## Context

See proposal.md. `new-order-with-invoice` builds the product search (endpoint and component) and confirms how Chatwoot's editor-insert event behaves from a sidebar component. The action runner handles role, scope, record and private note.

## Goals / Non-Goals

**Goals:** reuse the search and the runner; the reply stays the agent's text, nothing is sent by us.

**Non-Goals:** rich product cards; several products at once; editing or deleting codes later; reporting on codes used.

## Decisions

**D1. One inserted line per product.** Rich editor: "Title, price" with the title as a link. Plain-text channels: "Title, price: URL". The link is the product's `onlineStoreUrl`; when it is null the product is marked "not in the online store" in the results and inserted without a link.

**D2. The code is a basic discount** (`discountCodeBasicCreate`): percentage or fixed amount on all items, `usageLimit: 1`, `appliesOncePerCustomer: true`, the customer selection set to the matched customer or to all, `endsAt` from the chosen expiry, title "Helpdesk: conversation <id>". Task 1.1 confirms the input shape and the scope on the test store before any code.

**D3. The proposed code text** is a short random string with a fixed prefix (`THANKS-` and eight characters from an alphabet without look-alike characters). The agent may replace it; the store is the judge of duplicates and its reason is shown.

**D4. Where the controls live.** Two buttons at the top of the Orders section, present also when no customer is matched (the section already exists in that state). No new sidebar section and no patch to the reply box.

**D5. Runner and gating.** `write_discounts` joins the optional scopes with `can.discount_code`; the product control depends on `read_products` only and on no role. The action row stores the code, value, expiry and the discount's id.

## Risks / Trade-offs

- [No ceiling on the value] → role-gated and recorded; a ceiling set by the administrator is a small later change if merchants ask.
- [A code tied to a customer needs the customer to be signed in or to use the same email at checkout] → the dialog says the code works for this customer's email only.
- [The insert event changes in a Chatwoot release] → a component test and an end-to-end test catch it; the fallback is a copy button.
