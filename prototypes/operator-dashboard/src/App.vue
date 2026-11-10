<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from "vue";
import { useMediaQuery } from "@vueuse/core";
import {
  Check,
  ChevronRight,
  CircleHelp,
  ExternalLink,
  Menu,
  X,
  ShoppingBag,
  ArrowUpRight,
  BookOpen,
} from "lucide-vue-next";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from "@/components/ui/dialog";
import { TooltipProvider } from "@/components/ui/tooltip";
import WorkspaceNav from "@/components/WorkspaceNav.vue";
import ConversationList from "@/components/ConversationList.vue";
import ConversationPane from "@/components/ConversationPane.vue";
import CustomerPanel from "@/components/CustomerPanel.vue";
import PersonAvatar from "@/components/PersonAvatar.vue";
import IconButton from "@/components/IconButton.vue";
import {
  aiSuggestions,
  demoConversations,
  type Queue,
  type Status,
  type Message,
} from "@/lib/demo";

const conversations = ref(structuredClone(demoConversations));
const isMobile = useMediaQuery("(max-width: 699px)");
const selectedId = ref(1048);
const search = ref("");
const queue = ref<Queue>("all");
const status = ref<Status>("open");
const unreadOnly = ref(false);
const priorityOnly = ref(false);
const oldestFirst = ref(false);
const showCustomer = ref(window.innerWidth >= 1320);
const mobileConversation = ref(false);
const showNav = ref(false);
const customerTab = ref("details");
const addressUpdated = ref(false);
const dialog = ref("");
const dialogOpen = computed({
  get: () => Boolean(dialog.value),
  set: (value) => {
    if (!value) dialog.value = "";
  },
});
const tagInput = ref("");
const toast = ref("");
let toastTimeout: ReturnType<typeof setTimeout>;
const active = computed(
  () => conversations.value.find((c) => c.id === selectedId.value)!,
);
const queueTitle = computed(
  () =>
    ({
      all: "All conversations",
      mine: "Assigned to me",
      unassigned: "Unassigned",
      ai: "AI handling",
      Email: "Email",
      "Live chat": "Live chat",
      Instagram: "Instagram",
    })[queue.value],
);
const inQueue = computed(() =>
  conversations.value.filter(
    (c) =>
      queue.value === "all" ||
      (queue.value === "mine" && c.assignee === "You") ||
      (queue.value === "unassigned" && c.assignee === "Unassigned") ||
      (queue.value === "ai" && c.assignee === "Inclamo AI") ||
      c.channel === queue.value,
  ),
);
const counts = computed(() => ({
  open: inQueue.value.filter((c) => c.status === "open").length,
  snoozed: inQueue.value.filter((c) => c.status === "snoozed").length,
  done: inQueue.value.filter((c) => c.status === "done").length,
}));
const filtered = computed(() => {
  const result = inQueue.value.filter(
    (c) =>
      c.status === status.value &&
      (!unreadOnly.value || c.unread) &&
      (!priorityOnly.value || c.priority) &&
      `${c.name} ${c.email} ${c.subject} ${c.preview} ${c.id}`
        .toLowerCase()
        .includes(search.value.toLowerCase()),
  );
  return oldestFirst.value ? [...result].reverse() : result;
});
const dialogTitles: Record<string, string> = {
  help: "A workspace that feels like yours.",
  contacts: "Your customers",
  knowledge: "Knowledge for better conversations",
  order: "Sophie’s orders",
  address: "Update shipping address",
  tags: "Conversation tag",
};
const dialogDescriptions: Record<string, string> = {
  help: "An interactive Inclamo design preview, built with shadcn-vue.",
  contacts: "Select a customer to open their conversation.",
  knowledge: "Example store policies used in this preview.",
  order: "Northstar · 4 orders · $328.00 lifetime value",
  address: "Review the address Sophie sent before applying the change.",
  tags: "Keep the conversation easy to find and understand.",
};
function notify(message: string) {
  clearTimeout(toastTimeout);
  toast.value = message;
  toastTimeout = setTimeout(() => (toast.value = ""), 4500);
}
function resetFilters() {
  search.value = "";
  unreadOnly.value = false;
  priorityOnly.value = false;
  status.value = "open";
}
function select(id: number) {
  selectedId.value = id;
  active.value.unread = false;
  mobileConversation.value = true;
  dialog.value = "";
}
function selectQueue(value: Queue) {
  queue.value = value;
  resetFilters();
  showNav.value = false;
  mobileConversation.value = false;
}
function changeStatus(value: Status) {
  active.value.status = value;
  notify(
    value === "done"
      ? "Conversation resolved. You can reopen it anytime."
      : value === "snoozed"
        ? "Conversation moved to Snoozed in this preview."
        : "Conversation reopened.",
  );
}
function send(kind: Message["kind"], text: string) {
  active.value.messages.push({
    id: Date.now(),
    kind,
    text,
    time: new Intl.DateTimeFormat("en-US", {
      hour: "numeric",
      minute: "2-digit",
    }).format(new Date()),
  });
  if (kind === "note") active.value.noteDraft = "";
  else {
    active.value.draft = "";
    active.value.preview = `You: ${text}`;
    active.value.time = "Now";
  }
  notify(
    kind === "note"
      ? "Private note added to this preview."
      : "Reply added to this preview. No email was sent.",
  );
}
function suggest() {
  active.value.draft =
    active.value.id === 1048 && addressUpdated.value
      ? "Hi Sophie, all set! I’ve updated your shipping address to 24 Maple Street, Brooklyn, NY 11201. Your order will be on its way soon. Thanks for shopping with us!"
      : aiSuggestions[active.value.id] ||
        `Hi ${active.value.name.split(" ")[0]}, thanks for reaching out! I’m looking into this for you and will get back to you with an update shortly.`;
  notify("Example draft added. Review and edit before sending.");
  customerTab.value = "details";
}
function openTags() {
  tagInput.value = active.value.tag;
  dialog.value = "tags";
}
async function copy(value: string) {
  try {
    await navigator.clipboard.writeText(value);
    notify("Copied to clipboard.");
  } catch {
    notify(`Copy this: ${value}`);
  }
}
function keyboard(event: KeyboardEvent) {
  if (
    (event.target instanceof HTMLElement &&
      (event.target.matches("input, textarea") ||
        event.target.isContentEditable)) ||
    dialog.value
  )
    return;
  if (event.key === "/") {
    event.preventDefault();
    mobileConversation.value = false;
    document
      .querySelector<HTMLInputElement>('[aria-label="Search conversations"]')
      ?.focus();
  }
  if (event.key === "?") dialog.value = "help";
  if (event.key === "Escape") {
    showNav.value = false;
    if (window.innerWidth < 1320) showCustomer.value = false;
  }
}
onMounted(() => window.addEventListener("keydown", keyboard));
onUnmounted(() => {
  window.removeEventListener("keydown", keyboard);
  clearTimeout(toastTimeout);
});
</script>

<template>
  <TooltipProvider :delay-duration="300">
    <div
      :class="[
        'app-shell',
        { 'nav-open': showNav, 'mobile-conversation': mobileConversation },
      ]"
    >
      <button
        v-if="showNav"
        class="nav-backdrop"
        aria-label="Close workspace navigation"
        @click="showNav = false"
      />
      <WorkspaceNav
        :queue="queue"
        :conversations="conversations"
        @queue="selectQueue"
        @contacts="dialog = 'contacts'"
        @knowledge="dialog = 'knowledge'"
        @help="dialog = 'help'"
        @close="showNav = false"
      />
      <main class="main-workspace">
        <header class="workspace-header">
          <div class="breadcrumbs">
            <IconButton
              label="Open navigation"
              class="menu-toggle"
              @click="showNav = true"
              ><Menu /></IconButton
            ><span class="breadcrumb-workspace">Workspace</span
            ><ChevronRight class="breadcrumb-workspace" /><strong>Inbox</strong
            ><ChevronRight /><span>{{ queueTitle }}</span>
          </div>
          <div class="workspace-header-right">
            <button class="preview-badge" @click="dialog = 'help'">
              <span />Interactive preview</button
            ><span class="header-divider" />
            <div class="team-avatars" aria-label="Alex and Mia are online">
              <PersonAvatar initials="AK" tone="sky" /><PersonAvatar
                initials="ML"
                tone="mist"
              />
            </div>
            <span class="team-online">2 online</span
            ><IconButton label="Help and shortcuts" @click="dialog = 'help'"
              ><CircleHelp
            /></IconButton>
          </div>
        </header>
        <div :class="['workbench', { 'with-customer': showCustomer }]">
          <ConversationList
            :conversations="filtered"
            :selected-id="selectedId"
            :search="search"
            :status="status"
            :counts="counts"
            :unread-only="unreadOnly"
            :priority-only="priorityOnly"
            :oldest-first="oldestFirst"
            @select="select"
            @search="search = $event"
            @status="status = $event"
            @unread="unreadOnly = $event"
            @priority="priorityOnly = $event"
            @sort="oldestFirst = !oldestFirst"
            @clear="resetFilters"
          />
          <ConversationPane
            v-if="!isMobile || mobileConversation"
            :conversation="active"
            :show-customer="showCustomer"
            @send="send"
            @draft="
              (kind, value) =>
                kind === 'reply'
                  ? (active.draft = value)
                  : (active.noteDraft = value)
            "
            @suggest="suggest"
            @status="changeStatus"
            @priority="active.priority = !active.priority"
            @assign="active.assignee = $event"
            @customer="showCustomer = !showCustomer"
            @back="mobileConversation = false"
            @copy="copy(`Inclamo conversation #${active.id}`)"
          />
          <button
            v-if="showCustomer"
            class="customer-backdrop"
            aria-label="Dismiss customer details"
            @click="showCustomer = false"
          />
          <CustomerPanel
            v-if="showCustomer"
            :conversation="active"
            :address-updated="addressUpdated"
            :tab="customerTab"
            @close="showCustomer = false"
            @tab="customerTab = $event"
            @order="dialog = 'order'"
            @address="dialog = 'address'"
            @tag="openTags"
            @suggest="suggest"
            @copy="copy"
            @knowledge="dialog = 'knowledge'"
          />
        </div>
      </main>
    </div>
    <Dialog v-model:open="dialogOpen"
      ><DialogContent class="prototype-dialog"
        ><DialogHeader
          ><DialogTitle>{{ dialogTitles[dialog] }}</DialogTitle
          ><DialogDescription>{{
            dialogDescriptions[dialog]
          }}</DialogDescription></DialogHeader
        >
        <template v-if="dialog === 'help'"
          ><div class="preview-intro">
            <img src="/inclamo-logo.svg" alt="" />
            <p>
              One place for your team, your customers, and a little AI
              assistance.
            </p>
          </div>
          <div class="preview-details">
            <p>
              Try switching conversations, writing a reply or private note,
              checking an order, and reviewing an example AI draft.
            </p>
            <p>
              All customers and orders are fictional. Changes last until you
              refresh; messages and store updates stay in this local preview.
            </p>
          </div>
          <div class="shortcut-list">
            <span>Find a conversation <kbd>/</kbd></span
            ><span>Send a reply <kbd>⌘ / Ctrl + Enter</kbd></span
            ><span>Show this guide <kbd>?</kbd></span>
          </div>
          <a
            class="component-credit"
            href="https://www.shadcn-vue.com"
            target="_blank"
            rel="noreferrer"
            >Built with shadcn-vue<ExternalLink /></a
        ></template>
        <template v-else-if="dialog === 'contacts'"
          ><div class="contact-directory">
            <button
              v-for="customer in conversations"
              :key="customer.id"
              @click="select(customer.id)"
            >
              <PersonAvatar
                :initials="customer.initials"
                :tone="customer.tone"
              /><span
                ><strong>{{ customer.name }}</strong
                ><small>{{ customer.email }}</small></span
              ><ArrowUpRight />
            </button></div
        ></template>
        <template v-else-if="dialog === 'knowledge'"
          ><div class="knowledge-articles">
            <article>
              <BookOpen />
              <div>
                <h4>Shipping & order changes</h4>
                <p>
                  Shipping addresses can be updated while an order is
                  unfulfilled. Confirm the new address with the customer before
                  saving.
                </p>
                <Badge variant="secondary">Order management</Badge>
              </div>
            </article>
            <article>
              <ShoppingBag />
              <div>
                <h4>Returns & exchanges</h4>
                <p>
                  Unworn items with their original tags can be returned within
                  30 days. Check the order and item condition before offering an
                  exchange.
                </p>
                <Badge variant="secondary">Customer care</Badge>
              </div>
            </article>
          </div></template
        >
        <template v-else-if="dialog === 'order'"
          ><div class="order-history">
            <div
              v-for="order in [
                {
                  id: '1048',
                  name: 'Everyday Tote',
                  date: 'Nov 10, 2026',
                  price: '$89.00',
                  state: 'Unfulfilled',
                },
                {
                  id: '0921',
                  name: 'Linen Cap + Cotton Socks',
                  date: 'Aug 12, 2026',
                  price: '$64.00',
                  state: 'Delivered',
                },
                {
                  id: '0742',
                  name: 'Weekend Overshirt',
                  date: 'May 4, 2026',
                  price: '$115.00',
                  state: 'Delivered',
                },
                {
                  id: '0315',
                  name: 'Everyday Tee × 2',
                  date: 'Mar 18, 2025',
                  price: '$60.00',
                  state: 'Delivered',
                },
              ]"
              :key="order.id"
            >
              <span class="order-history-icon"><ShoppingBag /></span
              ><span
                ><strong>#{{ order.id }} · {{ order.name }}</strong
                ><small>{{ order.date }} · {{ order.state }}</small></span
              ><b>{{ order.price }}</b>
            </div>
          </div>
          <div class="order-detail-note">
            <strong>Shipping address · #1048</strong>
            <p>
              {{
                addressUpdated
                  ? "24 Maple Street, Brooklyn, NY 11201"
                  : "112 Bedford Avenue, Brooklyn, NY 11211"
              }}
            </p>
          </div>
          <DialogFooter
            ><Button variant="outline" @click="dialog = 'address'"
              >Edit shipping address</Button
            ></DialogFooter
          ></template
        >
        <template v-else-if="dialog === 'address'"
          ><div class="address-review">
            <div>
              <span>CURRENT ADDRESS</span>
              <p>
                {{ addressUpdated ? "24 Maple Street" : "112 Bedford Avenue"
                }}<br />Brooklyn, NY {{ addressUpdated ? "11201" : "11211" }}
              </p>
            </div>
            <ChevronRight />
            <div>
              <span>REQUESTED ADDRESS</span>
              <p>24 Maple Street<br />Brooklyn, NY 11201</p>
            </div>
          </div>
          <p class="dialog-note">
            <Check />Order #1048 is unfulfilled and can be updated.
          </p>
          <DialogFooter
            ><Button variant="outline" @click="dialog = ''">Cancel</Button
            ><Button
              @click="
                addressUpdated = true;
                dialog = '';
                notify(
                  'Address updated in this preview. Shopify was not changed.',
                );
              "
              >Confirm address</Button
            ></DialogFooter
          ></template
        >
        <template v-else-if="dialog === 'tags'"
          ><form
            @submit.prevent="
              active.tag = tagInput.trim() || active.tag;
              dialog = '';
            "
          >
            <label for="tag-name" class="field-label">Tag name</label
            ><Input
              id="tag-name"
              v-model="tagInput"
              maxlength="32"
              required
            /><DialogFooter class="mt-5"
              ><Button type="button" variant="outline" @click="dialog = ''"
                >Cancel</Button
              ><Button type="submit">Save tag</Button></DialogFooter
            >
          </form></template
        >
      </DialogContent></Dialog
    >
    <Transition name="toast"
      ><div v-if="toast" class="notification" role="status">
        <span><Check /></span>
        <p>{{ toast }}</p>
        <button aria-label="Dismiss notification" @click="toast = ''">
          <X />
        </button></div
    ></Transition>
  </TooltipProvider>
</template>
