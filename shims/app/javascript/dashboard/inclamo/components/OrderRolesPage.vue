<script setup>
// Settings → Order actions: which agents may cancel, refund, change addresses
// and send replacements. Administrators always may.
import { ref, onMounted } from 'vue';
import SettingsLayout from 'dashboard/routes/dashboard/settings/SettingsLayout.vue';
import BaseSettingsHeader from 'dashboard/routes/dashboard/settings/components/BaseSettingsHeader.vue';
import InclamoAPI from '../api';
import { t } from '../i18n';

const members = ref([]);
const loading = ref(true);
const failed = ref(false);
const busy = ref(false);
const saveFailed = ref(false);

const load = async () => {
  try {
    const { data } = await InclamoAPI.getRoles();
    members.value = data.members;
  } catch (error) {
    failed.value = true;
  } finally {
    loading.value = false;
  }
};

const toggle = async (member, event) => {
  busy.value = true;
  saveFailed.value = false;
  try {
    const { data } = member.can_act ? await InclamoAPI.takeRole(member.user_id) : await InclamoAPI.giveRole(member.user_id);
    members.value = data.members;
  } catch (error) {
    // A failed response must not leave the requested permission looking saved.
    event.target.checked = member.can_act;
    saveFailed.value = true;
  } finally {
    busy.value = false;
  }
};

onMounted(load);
</script>

<template>
  <SettingsLayout :is-loading="loading" :loading-message="t('SETTINGS.ORDER_ROLES.LOADING')">
    <template #header>
      <BaseSettingsHeader :title="t('SETTINGS.ORDER_ROLES.TITLE')" :description="t('SETTINGS.ORDER_ROLES.INTRO')" />
    </template>
    <template #body>
      <p v-if="failed" class="text-sm text-n-ruby-11" data-testid="inclamo-roles-failed">{{ t('SETTINGS.ORDER_ROLES.FAILED') }}</p>
      <div v-else class="flex flex-col divide-y divide-n-weak text-sm text-n-slate-12" data-testid="inclamo-roles-page">
        <p v-if="saveFailed" role="alert" class="py-3 text-n-ruby-11" data-testid="inclamo-role-error">{{ t('SETTINGS.ORDER_ROLES.SAVE_FAILED') }}</p>
        <label v-for="member in members" :key="member.user_id" class="flex items-center justify-between gap-2 py-3" :data-testid="`inclamo-role-${member.user_id}`">
          <span class="flex flex-col">
            <span>{{ member.name }}</span>
            <span class="text-xs text-n-slate-11">{{ member.switchable ? member.email : t('SETTINGS.ORDER_ROLES.ADMIN') }}</span>
          </span>
          <input type="checkbox" :checked="member.can_act" :disabled="!member.switchable || busy" :aria-label="t('SETTINGS.ORDER_ROLES.ALLOW')" @change="toggle(member, $event)" />
        </label>
      </div>
    </template>
  </SettingsLayout>
</template>
