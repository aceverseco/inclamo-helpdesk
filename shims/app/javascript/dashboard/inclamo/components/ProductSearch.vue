<script setup>
// The store's catalogue, searched by title or SKU: one search for every
// dialog that picks a product. Emits `select` with { product, variant }, the
// shapes of the search answer.
import { ref, watch, onBeforeUnmount } from 'vue';
import InclamoAPI from '../api';
import { t } from '../i18n';
import { money } from '../format';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  // Whether a variant the store cannot sell may still be chosen.
  allowUnavailable: { type: Boolean, default: false },
  disabled: { type: Boolean, default: false },
  // Whether to mark a product that is not in the online store (it has no link).
  showStorefront: { type: Boolean, default: false },
});
const emit = defineEmits(['select']);

const DELAY = 300;
const query = ref('');
const products = ref([]);
const page = ref({ has_more: false, cursor: null });
const busy = ref(false);
const searched = ref(false);
const problem = ref('');
let timer = null;
let asked = 0;

const explain = error => {
  const data = error?.response?.data || {};
  if (data.error === 'missing_scope') return t('PRODUCTS.MISSING_SCOPE', { scopes: (data.missing_scopes || []).join(', ') });
  return t('PRODUCTS.UNAVAILABLE');
};

const search = async ({ more = false } = {}) => {
  const text = query.value.trim();
  clearTimeout(timer);
  asked += 1;
  const ticket = asked;
  if (!text) {
    products.value = [];
    searched.value = false;
    problem.value = '';
    busy.value = false;
    return;
  }
  busy.value = true;
  problem.value = '';
  try {
    const { data } = await InclamoAPI.searchProducts(props.conversationId, { query: text, after: more ? page.value.cursor : undefined });
    // An answer to an older text is dropped.
    if (ticket !== asked) return;
    products.value = more ? [...products.value, ...data.products] : data.products;
    page.value = data.page || { has_more: false, cursor: null };
    searched.value = true;
  } catch (error) {
    if (ticket === asked) problem.value = explain(error);
  } finally {
    if (ticket === asked) busy.value = false;
  }
};

watch(query, () => {
  clearTimeout(timer);
  timer = setTimeout(() => search(), DELAY);
});
onBeforeUnmount(() => clearTimeout(timer));

const selectable = variant => props.allowUnavailable || variant.available_for_sale;
const choose = (product, variant) => {
  if (props.disabled || !selectable(variant)) return;
  emit('select', { product, variant });
};
const reset = () => {
  clearTimeout(timer);
  asked += 1;
  query.value = '';
  products.value = [];
  page.value = { has_more: false, cursor: null };
  searched.value = false;
  problem.value = '';
  busy.value = false;
};

defineExpose({ reset, search });
</script>

<template>
  <div class="flex flex-col gap-2" data-testid="inclamo-product-search">
    <input
      v-model="query"
      type="search"
      :placeholder="t('PRODUCTS.PLACEHOLDER')"
      :aria-label="t('PRODUCTS.LABEL')"
      :disabled="disabled"
      class="rounded-md border border-n-weak bg-n-alpha-black2 px-2 py-1.5"
      data-testid="inclamo-product-query"
      @keydown.enter.prevent="search()"
    />
    <p v-if="busy" class="text-xs text-n-slate-11" data-testid="inclamo-product-searching">{{ t('PRODUCTS.SEARCHING') }}</p>
    <p v-if="problem" class="text-xs text-n-ruby-11" data-testid="inclamo-product-problem">{{ problem }}</p>
    <p v-else-if="searched && !busy && !products.length" class="text-xs text-n-slate-11" data-testid="inclamo-product-none">{{ t('PRODUCTS.NONE') }}</p>
    <ul v-if="products.length" class="flex max-h-60 flex-col gap-1 overflow-y-auto" data-testid="inclamo-product-results">
      <li v-for="product in products" :key="product.id" class="flex flex-col" data-testid="inclamo-product">
        <span class="flex items-center gap-2 text-xs font-medium text-n-slate-12">
          <img v-if="product.image_url" :src="product.image_url" alt="" class="size-6 rounded object-cover" />
          {{ product.title }}
          <span v-if="showStorefront && !product.online_store_url" class="font-normal text-n-slate-11" data-testid="inclamo-product-no-link">{{ t('INSERTS.PRODUCT.NOT_IN_STORE') }}</span>
        </span>
        <button
          v-for="variant in product.variants"
          :key="variant.id"
          type="button"
          class="flex w-full items-center justify-between gap-2 rounded px-2 py-1 text-left text-xs hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
          :disabled="disabled || !selectable(variant)"
          data-testid="inclamo-product-variant"
          :data-variant-id="variant.id"
          @click="choose(product, variant)"
        >
          <span class="truncate">{{ variant.title || product.title }}<template v-if="variant.sku"> · {{ variant.sku }}</template></span>
          <span class="flex shrink-0 items-center gap-2">
            <span v-if="!variant.available_for_sale" class="text-n-ruby-11" data-testid="inclamo-product-variant-unavailable">{{ t('PRODUCTS.UNAVAILABLE_VARIANT') }}</span>
            <span>{{ money(variant.price.amount, variant.price.currency) }}</span>
          </span>
        </button>
      </li>
    </ul>
    <button v-if="page.has_more" type="button" class="self-center text-xs text-n-blue-text" :disabled="busy" data-testid="inclamo-product-more" @click="search({ more: true })">
      {{ t('PRODUCTS.MORE') }}
    </button>
  </div>
</template>
