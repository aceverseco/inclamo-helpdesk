<script setup>
import { ref, computed, watch } from 'vue';
import SettingsLayout from 'dashboard/routes/dashboard/settings/SettingsLayout.vue';
import BaseSettingsHeader from 'dashboard/routes/dashboard/settings/components/BaseSettingsHeader.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { Button } from '../ui/button';
import LayoutEditor from './LayoutEditor.vue';
import { copyLayout, productLayout } from './registry';
import { layoutURL, useWorkspaceLayout } from './layoutState';
import { t } from '../i18n';
const { accountId, refresh } = useWorkspaceLayout();
const draft = ref(productLayout());
const members = ref([]);
const revision = ref(null);
const loading = ref(true);
const busy = ref(false);
const error = ref('');
const applied = ref(false);
const target = ref('default');
const userId = ref(null);
const confirm = ref(null);
const summary = computed(() => {
  if (target.value === 'all') return t('WIDGETS.CONFIRM_ALL', { count: members.value.length });
  if (target.value === 'member') return t('WIDGETS.CONFIRM_MEMBER', { name: members.value.find(member => member.user_id === userId.value)?.name || '' });
  return t('WIDGETS.CONFIRM_DEFAULT');
});
let generation = 0;
const load = async () => {
  const mine = ++generation;
  loading.value = true;
  error.value = '';
  try {
    const { data } = await axios.get(`${layoutURL(accountId.value)}/administration`);
    if (mine !== generation) return;
    draft.value = copyLayout(data.layout);
    members.value = data.members;
    revision.value = data.revision;
    userId.value = data.members[0]?.user_id;
  } catch { if (mine === generation) error.value = 'WIDGETS.LOAD_FAILED'; }
  finally { if (mine === generation) loading.value = false; }
};
watch(accountId, () => { confirm.value?.close(); load(); }, { immediate: true });
const apply = async () => {
  busy.value = true;
  applied.value = false;
  const mine = generation;
  try {
    const { data } = await axios.put(`${layoutURL(accountId.value)}/administer`, {
      layout: draft.value, revision: revision.value, target: target.value,
      user_id: userId.value, confirmed_count: members.value.length,
    });
    if (mine !== generation) return;
    revision.value = data.revision;
    members.value = data.members;
    applied.value = true;
    error.value = '';
    await refresh();
  } catch (failure) {
    if (mine === generation) error.value = failure.response?.status === 409 ? 'WIDGETS.CONFLICT' : 'WIDGETS.SAVE_FAILED';
  } finally { busy.value = false; confirm.value?.close(); }
};
</script>
<template>
  <SettingsLayout :is-loading="loading" :loading-message="t('ORDERS.LOADING')">
    <template #header><BaseSettingsHeader :title="t('WIDGETS.ADMIN_TITLE')" :description="t('WIDGETS.ADMIN_DESCRIPTION')" /></template>
    <template #body>
      <div class="space-y-4 max-w-2xl text-n-slate-12">
        <p v-if="error" role="alert">{{ t(error) }} <Button type="button" variant="outline" @click="load">{{ t('WIDGETS.RELOAD') }}</Button></p>
        <p v-if="applied" role="status">{{ t('WIDGETS.APPLIED') }}</p>
        <LayoutEditor v-model="draft" />
        <label class="flex flex-col gap-2">{{ t('WIDGETS.TARGET') }}
          <select v-model="target" :aria-label="t('WIDGETS.TARGET')"><option value="default">{{ t('WIDGETS.DEFAULT') }}</option><option value="member">{{ t('WIDGETS.MEMBER') }}</option><option value="all">{{ t('WIDGETS.ALL') }}</option></select>
        </label>
        <select v-if="target === 'member'" v-model="userId" :aria-label="t('WIDGETS.MEMBER')"><option v-for="member in members" :key="member.user_id" :value="member.user_id">{{ member.name }}</option></select>
        <Button type="button" :disabled="!revision || busy || Boolean(error)" @click="confirm.open()">{{ t('WIDGETS.APPLY') }}</Button>
      </div>
      <Dialog ref="confirm" :title="t('WIDGETS.APPLY')" :description="summary" :confirm-button-label="t('WIDGETS.APPLY')" :is-loading="busy" @confirm="apply" />
    </template>
  </SettingsLayout>
</template>
