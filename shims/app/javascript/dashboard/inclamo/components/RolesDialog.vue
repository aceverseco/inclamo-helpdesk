<script setup>
import { ref } from 'vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import InclamoAPI from '../api';
import { t } from '../i18n';

const dialog = ref(null);
const members = ref([]);
const busy = ref(false);

const load = async () => {
  const { data } = await InclamoAPI.getRoles();
  members.value = data.members;
};

const open = async () => {
  dialog.value.open();
  await load();
};

const toggle = async member => {
  busy.value = true;
  try {
    const { data } = member.can_act ? await InclamoAPI.takeRole(member.user_id) : await InclamoAPI.giveRole(member.user_id);
    members.value = data.members;
  } finally {
    busy.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog ref="dialog" :title="t('DIALOG.ROLES.TITLE')" :show-confirm-button="false" :cancel-button-label="t('DIALOG.CLOSE')" overflow-y-auto>
    <div class="flex flex-col gap-3 text-sm text-n-slate-12" data-testid="inclamo-roles-dialog">
      <p class="text-n-slate-11">{{ t('DIALOG.ROLES.INTRO') }}</p>
      <label v-for="member in members" :key="member.user_id" class="flex items-center justify-between gap-2" :data-testid="`inclamo-role-${member.user_id}`">
        <span class="flex flex-col">
          <span>{{ member.name }}</span>
          <span class="text-xs text-n-slate-11">{{ member.switchable ? member.email : t('DIALOG.ROLES.ADMIN') }}</span>
        </span>
        <input type="checkbox" :checked="member.can_act" :disabled="!member.switchable || busy" :aria-label="t('DIALOG.ROLES.ALLOW')" @change="toggle(member)" />
      </label>
    </div>
  </Dialog>
</template>
