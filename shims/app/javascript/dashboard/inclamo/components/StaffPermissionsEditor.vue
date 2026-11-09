<script setup>
import { ref, onMounted } from 'vue';
import InclamoAPI from '../api';
import { ACTION_RIGHTS } from '../permissions';
import { t } from '../i18n';

const emit = defineEmits(['loaded', 'changed']);
const members = ref([]);
const loading = ref(true);
const failed = ref(false);
const busy = ref(false);
const saveFailed = ref(false);
const load = async () => {
  loading.value = true;
  failed.value = false;
  try {
    const { data } = await InclamoAPI.getRoles();
    members.value = data.members;
    emit('loaded', data.members);
  } catch {
    failed.value = true;
  } finally {
    loading.value = false;
  }
};
const toggle = async (member, action, event) => {
  const saved = member.permissions?.[action] === true;
  busy.value = true;
  saveFailed.value = false;
  try {
    const { data } = await InclamoAPI.setPermission(member.user_id, action, !saved);
    members.value = data.members;
    emit('changed', data.members);
  } catch {
    event.target.checked = saved;
    saveFailed.value = true;
  } finally {
    busy.value = false;
  }
};
onMounted(load);
defineExpose({ reload: load });
</script>

<template>
  <div class="flex flex-col gap-4 text-sm text-n-slate-12" data-testid="inclamo-roles-page" :aria-busy="loading || busy">
    <p v-if="loading">{{ t('SETTINGS.ORDER_ROLES.LOADING') }}</p>
    <div v-else-if="failed" role="alert" data-testid="inclamo-roles-failed">
      <p class="text-n-ruby-11">{{ t('SETTINGS.ORDER_ROLES.FAILED') }}</p>
      <button type="button" class="text-n-blue-text" @click="load">{{ t('SETTINGS.ORDER_ROLES.RETRY') }}</button>
    </div>
    <template v-else>
      <p class="text-n-slate-11">{{ t('SETTINGS.ORDER_ROLES.COMPOUND') }}</p>
      <p v-if="saveFailed" role="alert" class="text-n-ruby-11" data-testid="inclamo-role-error">{{ t('SETTINGS.ORDER_ROLES.SAVE_FAILED') }}</p>
      <fieldset v-for="member in members" :key="member.user_id" class="rounded-lg border border-n-weak p-4" :data-testid="`inclamo-role-${member.user_id}`">
        <legend class="px-1 font-medium">{{ member.name }}</legend>
        <p class="mb-3 text-xs text-n-slate-11">{{ member.switchable ? member.email : t('SETTINGS.ORDER_ROLES.ADMIN') }}</p>
        <div class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-x-4 gap-y-3">
          <label v-for="action in ACTION_RIGHTS" :key="action" class="flex items-start gap-2">
            <input type="checkbox" class="mt-0.5" :checked="member.permissions?.[action] === true"
              :disabled="!member.switchable || busy" :data-testid="`inclamo-permission-${member.user_id}-${action}`"
              @change="toggle(member, action, $event)" />
            <span>{{ t(`ACTION_RIGHTS.${action}`) }}</span>
          </label>
        </div>
      </fieldset>
    </template>
  </div>
</template>
