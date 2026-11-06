# Connecting a Shopify store

The helpdesk reads and changes orders through a **custom app of your own**: an
app you create for your store, that only your store can install. Nothing is
installed from the Shopify App Store and no third party sits between your store
and your helpdesk.

The steps below were followed on a development store on 2026-11-05. Shopify
moves things around; where a label differs, look for the same idea.

## 1. Create the app

Since January 2026 custom apps are created in Shopify's **Dev Dashboard**, not
in the store's admin.

1. Open the Dev Dashboard (dev.shopify.com) and go to **Apps**.
2. **Create app**, then **Create app manually**.
3. **App name**: anything you will recognise, for example "Helpdesk".
4. **App URL**: the address of your helpdesk. Clear **Embed app in Shopify
   admin**: the helpdesk is not shown inside Shopify.
5. **Scopes**: paste this list.

   ```
   read_customers,read_orders,write_orders,write_draft_orders,read_products,read_locations
   ```

6. **Create app**, then **Release**.

What each scope is for:

| Scope | Needed for | Without it |
| --- | --- | --- |
| `read_customers` | finding the customer of a conversation by email or phone | the store cannot be connected |
| `read_orders` | showing orders | the store cannot be connected |
| `write_orders` | cancelling, refunding, changing the shipping address | those three actions are unavailable |
| `write_draft_orders` | sending a free replacement | the replacement is unavailable |
| `read_products` | sending a free replacement | the replacement is unavailable |
| `read_locations` | putting refunded items back in stock | a refund still works; the items stay out of stock |

When you approve `read_locations`, Shopify describes it as access to your
locations and to the store owner's phone number and physical address. The
helpdesk reads only the names of your locations.

You can leave out the last four and add them later: the panel shows orders
with the first two alone, and names the missing scope next to each action it
cannot offer.

## 2. Choose custom distribution

Open the app's **Distribution** and choose **Custom distribution**, then enter
your store's domain (`your-store.myshopify.com`) and generate the install link.

**Do not skip this step.** Until a distribution method is chosen, Shopify
refuses the app the store's orders, draft orders and customers. The helpdesk
then does not connect and tells you that the store refuses the app its orders.

Shopify refuses only what exists. On a store with no orders yet, an app
without a distribution method connects, and the panel starts saying that
Shopify refuses the app once the first customer or order appears. Choose
custom distribution, then press "Check again".

The choice cannot be undone, and the app can then be installed on that one
store only. That is what you want here.

## 3. Install the app on your store

Use the install link from the previous step, or the app's **Install** button,
and confirm the access the app asks for.

## 4. Copy the credentials

In the app's **Settings** you find the **Client ID** and the **Client secret**.
The secret is a password to your store's orders: do not send it by email or
chat.

## 5. Connect the store in the helpdesk

1. Sign in to the helpdesk as an administrator and open any conversation.
2. In the sidebar on the right, open **Orders** and press **Connect Shopify**.
3. Enter the store's domain, the Client ID and the Client secret, and press
   **Connect**.

The helpdesk checks the credentials against your store before saving anything,
and tells you what is wrong when it cannot connect:

| Message | What to do |
| --- | --- |
| The app must be installed on the store first. | Do step 3. |
| The store refused these credentials. | Copy the Client ID and secret again. |
| The app lacks required access: … | Add the named scope (see "Changing scopes"). |
| Enter the store's domain in the form your-store.myshopify.com. | Use the `myshopify.com` domain, not your shop's public address. |
| Encryption must be configured on this installation… | Set the three `ACTIVE_RECORD_ENCRYPTION_…` keys of the installation; the secret is never stored unencrypted. |

The secret is stored encrypted and is never shown again. The helpdesk asks
Shopify for a fresh access token every day by itself.

## 6. Decide who may act on orders

Every agent who can see a conversation sees the customer's orders.
Cancelling, refunding, changing an address and sending a replacement are for
administrators, and for the agents you allow: **Orders → Who can act on
orders**. A new agent is not allowed until you switch it on.

Every action asks for confirmation and leaves a private note in the
conversation with the agent's name. Every attempt, refused ones included, is
kept on record.

## Changing scopes

In the Dev Dashboard create a **new version** of the app with the new list of
scopes and release it. Then open the app from your store's admin (**Settings →
Apps**): Shopify asks you to approve the new access. Back in the helpdesk press
**Orders → Check again**.

## An older custom app with a permanent token

If your store still has a custom app created in the store's admin before 2026,
choose "Older custom app" in the connect dialog and enter its Admin API access
token. For such apps Shopify gives customers' names, emails, phones and
addresses only on some plans; where it does not, the helpdesk connects in a
*limited mode*: orders are found by order number only, names and addresses are
not shown, and the shipping address cannot be changed. Creating an app as in
steps 1 and 2 lifts that.

## Things to know

- **Sixty days.** Shopify lets an app see the orders of the last 60 days. Older
  orders are not listed; open them in Shopify.
- **Refunds and stock.** A refund puts back into stock only items that have not
  shipped. Returning shipped items to a location is done in Shopify.
- **Replacements.** A replacement is a new order with a total of zero: the
  items you keep, fully discounted, shipping free, to the address of the
  original order. Stock is taken when it is created.
- **Removing the connection** deletes the credentials from the helpdesk. Notes
  and the record of past actions stay.
