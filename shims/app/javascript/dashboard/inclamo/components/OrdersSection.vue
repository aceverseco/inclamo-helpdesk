<script setup>
// The "Orders" section of the conversation sidebar.
import { ref, computed, watch } from "vue";
import Spinner from "dashboard/components-next/spinner/Spinner.vue";
import InclamoAPI from "../api";
import OrderCard from "./OrderCard.vue";
import ConnectDialog from "./ConnectDialog.vue";
import { ORDER_ROLES_ROUTE } from "../routes";
import { useCommerce, acceptPanel } from "../widgets/commerce";
import { t } from "../i18n";
import { money } from "../format";

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  contactId: { type: [Number, String], default: undefined },
  accountId: { type: [Number, String], default: undefined },
  showStatistics: { type: Boolean, default: true },
});

const { entry, panel, load: refreshPanel } = useCommerce(() => props);
const loading = computed(() => entry.value.loading);
const failed = computed(() => entry.value.failed);
const orders = computed(() => panel.value?.orders || []);
const loadingMore = ref(false);
const lookupNumber = ref("");
const lookupBusy = ref(false);
const lookupResult = ref(null);
const connectDialog = ref(null);
const confirmingRemoval = ref(false);

const state = computed(() => panel.value?.state);
const viewer = computed(
  () =>
    panel.value?.viewer || { administrator: false, can_act_on_orders: false },
);
const connection = computed(
  () => panel.value?.connection || { connected: false },
);
const markedId = computed(() => panel.value?.marked_order?.id);
const lookupStates = ["none", "no_identifier", "limited"];
const openActionFor = (order) =>
  (panel.value?.open_actions || []).find(
    (action) => action.order_id === order.id,
  ) || null;

// The spinner shows on the first read only; a refresh after an action keeps
// what is on screen, so an expanded order stays expanded.
const load = async () => {
  lookupResult.value = null;
  await refreshPanel();
};

const loadMore = async () => {
  const current = entry.value;
  loadingMore.value = true;
  try {
    const { data } = await InclamoAPI.getPanel(current.conversationId, current.panel.page.cursor, current.account);
    acceptPanel(current, { ...current.panel, orders: [...(current.panel.orders || []), ...(data.orders || [])], page: data.page });
  } catch {
    if (entry.value === current) current.failed = true;
  } finally {
    if (entry.value === current) loadingMore.value = false;
  }
};

const mutate = async operation => {
  const current = entry.value;
  const { data } = await operation(current.conversationId);
  current.generation += 1;
  current.pending = null;
  current.loading = false;
  acceptPanel(current, data);
};

const findOrder = async () => {
  if (!lookupNumber.value.trim()) return;
  lookupBusy.value = true;
  const current = entry.value;
  try {
    const { data } = await InclamoAPI.lookup(
      props.conversationId,
      lookupNumber.value.trim(),
    );
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
const recheck = async () => {
  try {
    await InclamoAPI.recheck();
  } finally {
    await load();
  }
};
const remove = async () => {
  await InclamoAPI.disconnect();
  confirmingRemoval.value = false;
  await load();
};

watch(entry, () => {
  lookupNumber.value = '';
  lookupResult.value = null;
  lookupBusy.value = false;
  loadingMore.value = false;
  confirmingRemoval.value = false;
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
      <Spinner size="24" class="text-n-brand" />
      <span class="sr-only">{{ t("ORDERS.LOADING") }}</span>
    </div>

    <div
      v-else-if="failed || state === 'unavailable'"
      class="flex flex-col items-start gap-2"
      data-testid="inclamo-orders-unavailable"
    >
      <p>{{ t("ORDERS.UNAVAILABLE") }}</p>
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
      <template v-if="viewer.administrator">
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
      <p class="text-n-ruby-11">{{ t("ORDERS.BROKEN.TEXT") }}</p>
      <template v-if="viewer.administrator">
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
        <p class="text-xs">{{ t("ORDERS.REFUSED.ADMIN_HINT") }}</p>
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
      <div
        v-if="state === 'limited'"
        class="mb-2 p-2 rounded-md bg-n-amber-3 text-n-amber-11"
        data-testid="inclamo-orders-limited"
      >
        <p>{{ t("ORDERS.LIMITED.TEXT") }}</p>
        <p v-if="viewer.administrator" class="text-xs">
          {{ t("ORDERS.LIMITED.WHY") }}
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
          @changed="load"
          @mark="mark"
          @unmark="unmark"
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
            v-if="!confirmingRemoval"
            type="button"
            class="text-n-ruby-11"
            data-testid="inclamo-manage-remove"
            @click="confirmingRemoval = true"
          >
            {{ t("ORDERS.MANAGE.REMOVE") }}
          </button>
          <span v-else class="flex flex-col gap-1">
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
  </div>
</template>
