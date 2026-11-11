<script setup>
import { ref, watch, nextTick } from 'vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { Button } from '../ui/button';
import LayoutEditor from './LayoutEditor.vue';
import { copyLayout, productLayout } from './registry';
import { useWorkspaceLayout } from './layoutState';
import { t } from '../i18n';
const { state, accountId, save, refresh } = useWorkspaceLayout();
const dialog = ref(null);
const draft = ref(productLayout());
const revision = ref(null);
const error = ref('');
const busy = ref(false);
const opened = ref(false);
let trigger;
const open = () => {
  trigger = document.activeElement;
  draft.value = copyLayout(state.value.layout);
  revision.value = state.value.revision;
  error.value = '';
  opened.value = true;
  dialog.value.open();
};
const close = async () => { opened.value = false; await nextTick(); trigger?.focus(); };
watch(accountId, () => dialog.value?.close());
const commit = async (reset = false) => {
  busy.value = true;
  try { await save(draft.value, revision.value, reset); dialog.value.close(); }
  catch (failure) { error.value = failure.response?.status === 409 ? 'WIDGETS.CONFLICT' : 'WIDGETS.SAVE_FAILED'; await refresh(); }
  finally { busy.value = false; }
};
const reload = async () => { await refresh(); draft.value = copyLayout(state.value.layout); revision.value = state.value.revision; error.value = ''; };
</script>
<template>
  <Button type="button" variant="ghost" size="sm" :aria-label="t('WIDGETS.CONFIGURE')" :title="t('WIDGETS.CONFIGURE')" :disabled="state.denied" data-testid="configure-widgets" @click="open">
    <span class="i-lucide-sliders-horizontal size-4" aria-hidden="true" />
    <slot />
  </Button>
  <Dialog ref="dialog" :title="t('WIDGETS.CONFIGURE')" :confirm-button-label="t('WIDGETS.SAVE')" :is-loading="busy"
    :disable-confirm-button="!revision || revision !== state.revision || state.denied" overflow-y-auto @confirm="commit(false)" @close="close">
    <p v-if="error || (opened && revision !== state.revision)" role="alert">{{ t(error || 'WIDGETS.CONFLICT') }}</p>
    <Button v-if="!revision || revision !== state.revision || error" type="button" variant="outline" @click="reload">{{ t('WIDGETS.RELOAD') }}</Button>
    <LayoutEditor v-model="draft" />
    <Button type="button" variant="outline" :disabled="busy || !revision || revision !== state.revision" @click="commit(true)">{{ t('WIDGETS.RESET') }}</Button>
  </Dialog>
</template>
