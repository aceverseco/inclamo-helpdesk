<script setup>
// The "Orders" section of the conversation sidebar.
import { ref, computed, watch } from 'vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import InclamoAPI from '../api';
import OrderCard from './OrderCard.vue';
import AiProposalReview from './AiProposalReview.vue';
import ConnectDialog from './ConnectDialog.vue';
import MarksBlock from './MarksBlock.vue';
import NewOrderDialog from './NewOrderDialog.vue';
import ReplyInserts from './ReplyInserts.vue';
import { canPerform } from '../permissions';
import { insertIntoReply } from '../reply';
import { ORDER_ROLES_ROUTE } from '../routes';
import { useCommerce, acceptPanel } from '../widgets/commerce';
import { t, has } from '../i18n';
import { money, date, dateTime } from '../format';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  contactId: { type: [Number, String], default: undefined },
  accountId: { type: [Number, String], default: undefined },
  showStatistics: { type: Boolean, default: true },
});

// The panel lives in the shared commerce store (widgets/commerce.js): the
// sidebar section and the workspace widgets read one answer per conversation,
// and an answer for a conversation or account the agent has left is kept
// apart from the one on screen.
const { entry, panel, load: refreshPanel } = useCommerce(() => props);
const loading = computed(() => entry.value.loading);
const failed = computed(() => entry.value.failed);
const orders = computed(() => panel.value?.orders || []);
const loadingMore = ref(false);
const lookupNumber = ref('');
const lookupBusy = ref(false);
const lookupResult = ref(null);
const connectDialog = ref(null);
const newOrderDialog = ref(null);
const confirmingRemoval = ref(false);
const connectingThroughApp = ref(false);
const appError = ref('');

const state = computed(() => panel.value?.state);
const viewer = computed(() => panel.value?.viewer || { administrator: false, can_act_on_orders: false });
const connection = computed(() => panel.value?.connection || { connected: false });
const markedId = computed(() => panel.value?.marked_order?.id);
const can = computed(() => panel.value?.can || {});
const lookupStates = ['none', 'no_identifier', 'limited'];
// An account the store app provisioned: its connection is the app's, made
// through it, never replaced with credentials or removed here.
const managedByApp = computed(() => connection.value.managed_by_app === true || connection.value.auth_kind === 'app_key');
const throughApp = computed(() => connection.value.auth_kind === 'app_key');
const brokenText = computed(() => {
  const reason = connection.value.broken_reason;
  return throughApp.value && reason && has(`ORDERS.APP.BROKEN.${reason}`) ? t(`ORDERS.APP.BROKEN.${reason}`) : t('ORDERS.BROKEN.TEXT');
});
const brokenAdminHint = computed(() => {
  const reason = connection.value.broken_reason;
  return reason && has(`ORDERS.APP.ADMIN_HINT.${reason}`) ? t(`ORDERS.APP.ADMIN_HINT.${reason}`) : t('ORDERS.APP.ADMIN_HINT.other');
});
const storeDataUnavailable = computed(() => state.value === 'unavailable' && panel.value?.reason === 'store_data_unavailable');
// What each action needs that the Inclamo app was not given at the store.
const appActions = computed(() => (connection.value.actions || []).map(action => ({
  ...action,
  text: action.available
    ? t('ORDERS.APP.AVAILABLE')
    : action.reason === 'missing_scope'
      ? t('ORDERS.APP.MISSING_SCOPE', { scopes: (action.missing_scopes || []).join(', ') })
      : t(`ORDER.WHY_NOT.${action.reason}`),
})));
const openActionFor = order => (panel.value?.open_actions || []).find(action => action.order_id === order.id) || null;

// A new order is offered to whoever may act on orders; when the connected app
// lacks a scope for it, a line names the scope instead.
const newOrderScope = computed(() => (connection.value.actions || []).find(item => item.name === 'new_order'));
const canCreateOrder = computed(() => canPerform(viewer.value, 'new_order') && Boolean(newOrderScope.value?.available));
const newOrderUnavailable = computed(() => {
  const scope = newOrderScope.value;
  if (!canPerform(viewer.value, 'new_order') || !scope || scope.available) return '';
  return t(`ORDER.WHY_NOT.${scope.reason}`, { scopes: (scope.missing_scopes || []).join(', ') });
});
const awaitingPayment = computed(() => panel.value?.awaiting_payment || []);
const unconfirmedOrders = computed(() => (panel.value?.open_actions || []).filter(action => action.action === 'new_order'));
const startNewOrder = order => newOrderDialog.value.open(order || null);

// The spinner shows on the first read only; a refresh after an action keeps
// what is on screen, so an expanded order stays expanded. The store reads as
// many orders as were shown and replaces them at once.
const load = async () => {
  lookupResult.value = null;
  await refreshPanel();
};

const loadMore = async () => {
  const current = entry.value;
  const generation = current.generation;
  loadingMore.value = true;
  try {
    const { data } = await InclamoAPI.getPanel(current.conversationId, current.panel.page.cursor, current.account);
    if (generation !== current.generation) return;
    acceptPanel(current, { ...current.panel, orders: [...(current.panel.orders || []), ...(data.orders || [])], page: data.page });
  } catch {
    // A failed further page leaves the orders already shown, and the summary
    // other widgets read from this entry, as they were. "Load more" stays on
    // screen and asks for the same page again.
  } finally {
    if (entry.value === current) loadingMore.value = false;
  }
};

// Every answer that replaces the panel is numbered when it is asked for, and
// only the latest one asked is shown: an answer that arrives late, for an
// earlier read or change, is dropped. An answer for a conversation the agent
// has left lands in that conversation's entry, not on screen.
const mutate = async operation => {
  const current = entry.value;
  const generation = ++current.generation;
  try {
    const { data } = await operation(current.conversationId);
    if (generation === current.generation) acceptPanel(current, data);
  } finally {
    // A read this change overtook is dropped; it no longer holds the entry.
    if (generation === current.generation) {
      current.pending = null;
      current.loading = false;
    }
  }
};

const findOrder = async () => {
  if (!lookupNumber.value.trim()) return;
  lookupBusy.value = true;
  const current = entry.value;
  try {
    const { data } = await InclamoAPI.lookup(current.conversationId, lookupNumber.value.trim());
    if (entry.value === current) lookupResult.value = data;
  } catch (error) {
    if (entry.value === current) lookupResult.value = { found: false };
  } finally {
    if (entry.value === current) lookupBusy.value = false;
  }
};

const choose = customerId => mutate(id => InclamoAPI.chooseCustomer(id, customerId));
const forget = () => mutate(id => InclamoAPI.forgetCustomer(id));
const mark = order => mutate(id => InclamoAPI.markOrder(id, order.id));
const unmark = () => mutate(id => InclamoAPI.clearOrder(id));
// A refused check is not an error of the section: the panel read after it
// shows what the store or the store app said (broken, with its reason).
const recheck = async () => {
  try {
    await InclamoAPI.recheck();
  } catch {
    // shown by the read below
  } finally {
    await load();
  }
};
const remove = async () => {
  await InclamoAPI.disconnect();
  confirmingRemoval.value = false;
  await load();
};
const connectThroughApp = async () => {
  connectingThroughApp.value = true;
  appError.value = '';
  try {
    await InclamoAPI.connectThroughApp();
    await load();
  } catch (failure) {
    const data = failure.response?.data || {};
    const key = `ORDERS.APP.ERRORS.${data.error}`;
    appError.value = has(key) ? t(key, { scopes: (data.missing_scopes || []).join(', ') }) : t('ORDERS.APP.ERRORS.other');
  } finally {
    connectingThroughApp.value = false;
  }
};

watch(entry, () => {
  lookupNumber.value = '';
  lookupResult.value = null;
  lookupBusy.value = false;
  loadingMore.value = false;
  confirmingRemoval.value = false;
  appError.value = '';
});
</script>

<template>
  <div
    class="inclamo-ref reference-orders text-n-slate-12"
    data-testid="inclamo-orders-section"
    :data-state="loading ? 'loading' : failed ? 'failed' : state"
  >
    <div
      v-if="loading"
      class="flex items-center justify-center gap-2 p-4"
      data-testid="inclamo-orders-loading"
    >
      <Spinner :size="24" class="text-n-brand" />
      <span class="sr-only">{{ t("ORDERS.LOADING") }}</span>
    </div>

    <div
      v-else-if="failed || state === 'unavailable'"
      class="flex flex-col items-start gap-2"
      data-testid="inclamo-orders-unavailable"
      :data-reason="storeDataUnavailable ? 'store_data_unavailable' : undefined"
    >
      <p v-if="storeDataUnavailable" data-testid="inclamo-orders-store-data-unavailable">{{ t("ORDERS.APP.UNAVAILABLE") }}</p>
      <p v-else>{{ t("ORDERS.UNAVAILABLE") }}</p>
      <button
        type="button"
        class="text-n-blue-text"
        data-testid="inclamo-orders-retry"
        @click="load"
      >
        {{ t("ORDERS.RETRY") }}
      </button>
    </div>

    <div
      v-else-if="state === 'not_connected'"
      class="flex flex-col items-start gap-2"
      data-testid="inclamo-orders-not-connected"
    >
      <template v-if="viewer.administrator && managedByApp">
        <p>{{ connection.through_app ? t("ORDERS.APP.NOT_CONNECTED") : t("ORDERS.APP.NOT_SET_UP") }}</p>
        <button
          v-if="connection.through_app"
          type="button"
          class="rounded-md bg-n-brand px-3 py-1.5 text-white disabled:opacity-50"
          :disabled="connectingThroughApp"
          data-testid="inclamo-connect-app"
          @click="connectThroughApp"
        >
          {{ t("ORDERS.APP.CONNECT") }}
        </button>
        <p v-if="appError" role="alert" class="text-n-ruby-11" data-testid="inclamo-connect-app-error">{{ appError }}</p>
      </template>
      <template v-else-if="viewer.administrator">
        <p>
          {{
            connection.encryption_configured === false
              ? t("ORDERS.NOT_CONNECTED.NO_ENCRYPTION")
              : t("ORDERS.NOT_CONNECTED.ADMIN")
          }}
        </p>
        <button
          v-if="connection.encryption_configured !== false"
          type="button"
          class="rounded-md bg-n-brand px-3 py-1.5 text-white"
          data-testid="inclamo-connect-open"
          @click="connectDialog.open()"
        >
          {{ t("ORDERS.NOT_CONNECTED.CONNECT") }}
        </button>
      </template>
      <p v-else>{{ t("ORDERS.NOT_CONNECTED.AGENT") }}</p>
    </div>

    <div
      v-else-if="state === 'broken'"
      class="flex flex-col items-start gap-2"
      data-testid="inclamo-orders-broken"
    >
      <p class="text-n-ruby-11" data-testid="inclamo-orders-broken-text" :data-reason="throughApp ? connection.broken_reason || 'other' : undefined">{{ brokenText }}</p>
      <template v-if="viewer.administrator && throughApp">
        <p class="text-xs" data-testid="inclamo-orders-broken-hint">{{ brokenAdminHint }}</p>
        <button type="button" class="text-n-blue-text" data-testid="inclamo-broken-recheck" @click="recheck">
          {{ t("ORDERS.MANAGE.CHECK_AGAIN") }}
        </button>
      </template>
      <template v-else-if="viewer.administrator">
        <div class="flex gap-3">
          <button
            type="button"
            class="text-n-blue-text"
            data-testid="inclamo-reconnect"
            @click="connectDialog.open(connection.shop_domain)"
          >
            {{ t("ORDERS.BROKEN.RECONNECT") }}
          </button>
          <button type="button" class="text-n-blue-text" @click="recheck">
            {{ t("ORDERS.MANAGE.CHECK_AGAIN") }}
          </button>
        </div>
      </template>
      <p v-else class="text-n-slate-11">{{ t("ORDERS.BROKEN.AGENT_HINT") }}</p>
    </div>

    <div
      v-else-if="state === 'refused'"
      class="flex flex-col items-start gap-2"
      data-testid="inclamo-orders-refused"
    >
      <p class="text-n-ruby-11">{{ t("ORDERS.REFUSED.TEXT") }}</p>
      <template v-if="viewer.administrator">
        <p class="text-xs">{{ throughApp ? t("ORDERS.APP.REFUSED_HINT") : t("ORDERS.REFUSED.ADMIN_HINT") }}</p>
        <button
          type="button"
          class="text-n-blue-text"
          data-testid="inclamo-refused-recheck"
          @click="recheck"
        >
          {{ t("ORDERS.MANAGE.CHECK_AGAIN") }}
        </button>
      </template>
      <p v-else class="text-n-slate-11">{{ t("ORDERS.REFUSED.AGENT_HINT") }}</p>
    </div>

    <template v-else>
      <AiProposalReview
        v-if="panel?.ai_proposals_enabled"
        :conversation-id="conversationId"
        :administrator="viewer.administrator"
        @changed="load"
      />
      <ReplyInserts
        :conversation-id="conversationId"
        :viewer="viewer"
        :connection="connection"
        :customer-matched="state === 'matched'"
        @changed="load"
      />
      <div
        v-if="state === 'limited'"
        class="mb-2 p-2 rounded-md bg-n-amber-3 text-n-amber-11"
        data-testid="inclamo-orders-limited"
      >
        <p>{{ t("ORDERS.LIMITED.TEXT") }}</p>
        <p v-if="viewer.administrator" class="text-xs">
          {{ throughApp ? t("ORDERS.APP.LIMITED_WHY") : t("ORDERS.LIMITED.WHY") }}
        </p>
      </div>
      <p
        v-if="state === 'no_identifier'"
        class="mb-2"
        data-testid="inclamo-orders-no-identifier"
      >
        {{ t("ORDERS.NO_IDENTIFIER") }}
      </p>
      <p v-if="state === 'none'" class="mb-2" data-testid="inclamo-orders-none">
        {{ panel.stale_choice ? t("ORDERS.STALE_CHOICE") : t("ORDERS.NONE") }}
      </p>

      <div
        v-if="state === 'ambiguous'"
        class="flex flex-col gap-2"
        data-testid="inclamo-orders-ambiguous"
      >
        <p>{{ t("ORDERS.AMBIGUOUS") }}</p>
        <div
          v-for="candidate in panel.candidates"
          :key="candidate.id"
          class="flex items-center justify-between gap-2 rounded-md outline outline-1 outline-n-weak p-2"
          data-testid="inclamo-candidate"
        >
          <span class="flex flex-col">
            <span class="font-medium">{{ candidate.name }}</span>
            <span class="text-xs text-n-slate-11"
              >{{ candidate.email || candidate.phone }} ·
              {{
                t("ORDERS.CUSTOMER.ORDERS_COUNT", {
                  count: candidate.orders_count,
                })
              }}</span
            >
          </span>
          <button
            type="button"
            class="text-n-blue-text text-xs"
            data-testid="inclamo-candidate-choose"
            @click="choose(candidate.id)"
          >
            {{ t("ORDERS.CHOOSE") }}
          </button>
        </div>
      </div>

      <div
        v-if="state === 'matched'"
        class="flex flex-col gap-2"
        data-testid="inclamo-orders-matched"
      >
        <div v-if="showStatistics" class="customer-stats" data-testid="inclamo-customer-summary">
          <div>
            <strong>{{ panel.customer.orders_count }}</strong
            ><span>{{ t("WORKSPACE.ORDER_COUNT") }}</span>
          </div>
          <div v-if="panel.customer.total_spent">
            <strong>{{
              money(
                panel.customer.total_spent.amount,
                panel.customer.total_spent.currency,
              )
            }}</strong
            ><span>{{ t("WORKSPACE.SPENT") }}</span>
          </div>
        </div>
        <slot name="labels" />
        <MarksBlock
          subject="customer"
          :subject-id="panel.customer.id"
          :conversation-id="conversationId"
          :tags="panel.customer.tags || []"
          :note="panel.customer.note || null"
          :editable="!!can.customer_marks"
          :tags-editable="!!can.customer_marks && canPerform(viewer, 'customer_tags')"
          :note-editable="!!can.customer_marks && canPerform(viewer, 'customer_note')"
          :connection="connection"
        />
        <button
          v-if="canCreateOrder"
          type="button"
          class="self-start rounded-[var(--inclamo-control-radius,0.375rem)] border border-n-weak px-3 py-1 text-xs"
          data-testid="inclamo-new-order-open"
          @click="startNewOrder()"
        >
          {{ t('NEW_ORDER.OPEN') }}
        </button>
        <p v-else-if="newOrderUnavailable" class="text-xs text-n-slate-11" data-testid="inclamo-new-order-unavailable">
          {{ t('NEW_ORDER.UNAVAILABLE', { reason: newOrderUnavailable }) }}
        </p>
        <p v-for="action in unconfirmedOrders" :key="action.action_id" class="p-2 rounded-md bg-n-amber-3 text-xs text-n-amber-11" data-testid="inclamo-new-order-unconfirmed">
          {{ t('AWAITING.UNCONFIRMED') }}
        </p>
        <section v-if="awaitingPayment.length" class="flex flex-col gap-2" data-testid="inclamo-awaiting-payment">
          <h4 class="text-xs uppercase text-n-slate-10">{{ t('AWAITING.TITLE') }}</h4>
          <div
            v-for="draft in awaitingPayment"
            :key="draft.id"
            class="flex flex-col gap-1 rounded-lg outline outline-1 outline-n-weak bg-n-solid-1 px-3 py-2"
            :data-testid="`inclamo-awaiting-${draft.number}`"
          >
            <span class="flex items-start justify-between gap-2">
              <span class="flex flex-col">
                <span class="font-medium">{{ draft.number }}</span>
                <span class="text-xs text-n-slate-11">{{ t('AWAITING.CREATED', { date: date(draft.created_at) }) }} · {{ draft.invoice_sent ? t('AWAITING.INVOICE_SENT') : t('AWAITING.NOT_SENT') }}</span>
              </span>
              <span class="font-medium" data-testid="inclamo-awaiting-total">{{ money(draft.total.amount, draft.total.currency) }}</span>
            </span>
            <ul class="text-xs">
              <li v-for="(item, index) in draft.items" :key="index">{{ item.title }} <span class="text-n-slate-11">{{ t('ORDER.QUANTITY', { count: item.quantity }) }}</span></li>
            </ul>
            <span class="flex flex-wrap items-center gap-3 text-xs">
              <a :href="draft.invoice_url" target="_blank" rel="noopener noreferrer" class="text-n-blue-text" data-testid="inclamo-awaiting-link">{{ t('AWAITING.PAYMENT_LINK') }}</a>
              <button type="button" class="text-n-blue-text" data-testid="inclamo-awaiting-insert" @click="insertIntoReply(draft.invoice_url)">{{ t('AWAITING.INSERT') }}</button>
              <a :href="draft.admin_url" target="_blank" rel="noopener noreferrer" class="text-n-blue-text" data-testid="inclamo-awaiting-admin-link">{{ t('ORDER.OPEN_IN_ADMIN') }}</a>
            </span>
          </div>
        </section>
        <div class="section-title">
          <h4>
            {{ t("WORKSPACE.STORE_ORDERS") }}
            <span class="count">{{ panel.customer.orders_count }}</span>
          </h4>
          <span>{{ t('WORKSPACE.SHOPIFY') }}</span>
        </div>
        <p v-if="!orders.length" class="text-n-slate-11">
          {{ t("ORDERS.NO_ORDERS") }}
        </p>
        <OrderCard
          v-for="(order, index) in orders"
          :key="order.id"
          :start-open="index === 0"
          :conversation-id="conversationId"
          :order="order"
          :connection="connection"
          :viewer="viewer"
          :marked="order.id === markedId"
          :open-action="openActionFor(order)"
          :can-change-marks="!!can.order_marks"
          can-order-again
          @changed="load"
          @mark="mark"
          @unmark="unmark"
          @order-again="startNewOrder"
        />
        <button
          v-if="panel.page && panel.page.has_more"
          type="button"
          class="self-center text-n-blue-text"
          :disabled="loadingMore"
          data-testid="inclamo-orders-more"
          @click="loadMore"
        >
          {{ t("ORDERS.LOAD_MORE") }}
        </button>
      </div>

      <form
        v-if="lookupStates.includes(state)"
        class="flex items-end gap-2"
        data-testid="inclamo-lookup"
        @submit.prevent="findOrder"
      >
        <label class="flex flex-1 flex-col gap-1">
          <span class="text-xs text-n-slate-11">{{
            t("ORDERS.LOOKUP.LABEL")
          }}</span>
          <input
            v-model="lookupNumber"
            type="text"
            :placeholder="t('ORDERS.LOOKUP.PLACEHOLDER')"
            class="rounded-[var(--inclamo-control-radius,0.375rem)] border border-n-weak bg-n-alpha-black2 px-2 py-1.5"
            data-testid="inclamo-lookup-number"
          />
        </label>
        <button
          type="submit"
          class="rounded-[var(--inclamo-control-radius,0.375rem)] border border-n-weak px-3 py-1.5"
          :disabled="lookupBusy"
          data-testid="inclamo-lookup-find"
        >
          {{ t("ORDERS.LOOKUP.FIND") }}
        </button>
      </form>
      <div v-if="lookupResult" class="mt-2 flex flex-col gap-2">
        <p v-if="!lookupResult.found" data-testid="inclamo-lookup-not-found">
          {{ t("ORDERS.LOOKUP.NOT_FOUND") }}
        </p>
        <template v-else>
          <OrderCard
            :conversation-id="conversationId"
            :order="lookupResult.order"
            :connection="connection"
            :viewer="viewer"
            :marked="lookupResult.order.id === markedId"
            :open-action="openActionFor(lookupResult.order)"
            :can-change-marks="!!can.order_marks"
            start-open
            @changed="findOrder"
            @mark="mark"
            @unmark="unmark"
          />
          <button
            v-if="lookupResult.order.customer"
            type="button"
            class="self-start text-n-blue-text text-xs"
            data-testid="inclamo-lookup-keep"
            @click="choose(lookupResult.order.customer.id)"
          >
            {{ t("ORDERS.KEEP_CUSTOMER") }} ({{
              lookupResult.order.customer.name
            }})
          </button>
          <p v-else-if="state === 'limited'" class="text-xs text-n-slate-11">
            {{ t("ORDER.CUSTOMER_HIDDEN") }}
          </p>
        </template>
      </div>

      <details class="reference-store-menu">
        <summary>{{ t("WORKSPACE.STORE_SETTINGS") }}</summary>
        <div v-if="state === 'matched'" class="reference-match-detail">
          <span data-testid="inclamo-customer-name">{{
            panel.customer.name
          }}</span
          ><button
            type="button"
            data-testid="inclamo-customer-forget"
            @click="forget"
          >
            {{ t("ORDERS.FORGET_CUSTOMER") }}
          </button>
        </div>
        <section
          v-if="throughApp"
          class="mt-3 flex flex-col gap-1 border-t border-n-weak pt-2 text-xs"
          data-testid="inclamo-app-connection"
        >
          <p class="font-medium">{{ t("ORDERS.APP.CONNECTED") }}</p>
          <p data-testid="inclamo-app-store">{{ connection.shop_name }} · {{ connection.shop_domain }}</p>
          <p data-testid="inclamo-app-checked">{{ t("ORDERS.APP.LAST_CHECK", { time: dateTime(connection.last_checked_at) }) }}</p>
          <p v-if="connection.renewed_at" data-testid="inclamo-app-renewed">{{ t("ORDERS.APP.LAST_RENEWAL", { time: dateTime(connection.renewed_at) }) }}</p>
          <ul class="flex flex-col gap-0.5" data-testid="inclamo-app-actions">
            <li v-for="action in appActions" :key="action.name" :data-testid="`inclamo-app-action-${action.name}`" :data-available="action.available ? 'true' : 'false'">
              <span class="font-medium">{{ t(`ACTION_RIGHTS.${action.name}`) }}</span>: <span :class="action.available ? '' : 'text-n-slate-11'">{{ action.text }}</span>
            </li>
          </ul>
        </section>
        <div
          v-if="viewer.administrator"
          class="mt-3 flex flex-wrap items-center gap-3 border-t border-n-weak pt-2 text-xs"
          data-testid="inclamo-manage"
        >
          <span class="text-n-slate-11">{{ connection.shop_name }}</span>
          <button
            type="button"
            class="text-n-blue-text"
            data-testid="inclamo-manage-recheck"
            @click="recheck"
          >
            {{ t("ORDERS.MANAGE.CHECK_AGAIN") }}
          </button>
          <router-link
            :to="{ name: ORDER_ROLES_ROUTE }"
            class="text-n-blue-text"
            data-testid="inclamo-manage-roles"
            >{{ t("ORDERS.MANAGE.WHO_CAN_ACT") }}</router-link
          >
          <button
            v-if="!confirmingRemoval && !managedByApp"
            type="button"
            class="text-n-ruby-11"
            data-testid="inclamo-manage-remove"
            @click="confirmingRemoval = true"
          >
            {{ t("ORDERS.MANAGE.REMOVE") }}
          </button>
          <span v-else-if="!managedByApp" class="flex flex-col gap-1">
            <span>{{ t("ORDERS.MANAGE.REMOVE_CONFIRM") }}</span>
            <span class="flex gap-3">
              <button
                type="button"
                class="text-n-ruby-11"
                data-testid="inclamo-manage-remove-confirm"
                @click="remove"
              >
                {{ t("ORDERS.MANAGE.REMOVE_YES") }}
              </button>
              <button
                type="button"
                class="text-n-slate-11"
                @click="confirmingRemoval = false"
              >
                {{ t("DIALOG.BACK") }}
              </button>
            </span>
          </span>
        </div>
      </details>
    </template>

    <ConnectDialog ref="connectDialog" @connected="load" />
    <NewOrderDialog
      v-if="state === 'matched' && canCreateOrder"
      ref="newOrderDialog"
      :conversation-id="conversationId"
      :customer="panel.customer"
      :can-discount="canPerform(viewer, 'discount')"
      :currency="connection.shop_currency"
      @done="load"
    />
  </div>
</template>
