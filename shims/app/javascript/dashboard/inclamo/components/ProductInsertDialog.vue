<script setup>
// "Insert product": the shared catalogue search. Picking a product puts one
// line into the reply the agent is writing (see productLine) and closes the
// dialog. Nothing is sent.
import { ref } from 'vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ProductSearch from './ProductSearch.vue';
import { insertIntoReply } from '../reply';
import { productLine } from '../inserts';
import { t } from '../i18n';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  // Whether the reply editor of this conversation keeps a link.
  links: { type: Boolean, default: false },
});

const dialog = ref(null);
const search = ref(null);

const open = () => {
  search.value?.reset();
  dialog.value.open();
};

const insert = choice => {
  insertIntoReply(productLine(choice, { links: props.links }));
  dialog.value.close();
};

defineExpose({ open });
</script>

<template>
  <Dialog ref="dialog" :title="t('INSERTS.PRODUCT.TITLE')" :show-confirm-button="false" :cancel-button-label="t('DIALOG.CLOSE')" overflow-y-auto>
    <div class="flex flex-col gap-2 text-sm text-n-slate-12" data-testid="inclamo-insert-product-dialog">
      <p class="text-xs text-n-slate-11">{{ t('INSERTS.PRODUCT.INTRO') }}</p>
      <ProductSearch ref="search" :conversation-id="conversationId" allow-unavailable show-storefront @select="insert" />
    </div>
  </Dialog>
</template>
