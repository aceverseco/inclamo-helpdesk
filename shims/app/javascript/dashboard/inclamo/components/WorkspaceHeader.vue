<script setup>
import { computed, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { t as inclamoT } from '../i18n';
import WorkspaceTools from './WorkspaceTools.vue';
import WidgetHost from '../widgets/WidgetHost.vue';
import SupportLauncher from '../support/SupportLauncher.vue';
import { clearCommerce } from '../widgets/commerce';
import { forgetOrderState } from '../orderState';
const currentUser = useMapGetter('getCurrentUser');
watch(() => currentUser.value?.id, () => { clearCommerce(); forgetOrderState(); });
const route = useRoute();
const { t: nativeT } = useI18n();
const section = computed(() => {
  if (route.path.includes('/settings')) return nativeT('SIDEBAR.SETTINGS');
  if (route.path.includes('/contacts')) return nativeT('SIDEBAR.CONTACTS');
  if (route.path.includes('/reports')) return nativeT('SIDEBAR.REPORTS');
  return inclamoT('WORKSPACE.INBOX');
});
const isInbox = computed(() =>
  /\/conversations\/|\/dashboard$/.test(route.path)
);
</script>
<template>
  <header class="inclamo-workspace-header">
    <div class="inclamo-workspace-breadcrumb">
      <span>{{ inclamoT('BRAND.WORKSPACE') }}</span>
      <span class="i-lucide-chevron-right" aria-hidden="true" />
      <strong>{{ section }}</strong>
      <template v-if="isInbox"
        ><span class="i-lucide-chevron-right" aria-hidden="true" /><span>{{
          inclamoT('WORKSPACE.ALL')
        }}</span></template
      >
    </div>
    <WidgetHost placement="workspace-header" />
    <div class="inclamo-workspace-user">
      <SupportLauncher />
      <WorkspaceTools />
      <template v-if="currentUser?.name"
        ><span>{{ currentUser.name }}</span
        ><Avatar
          :name="currentUser.name"
          :src="currentUser.avatar_url"
          :size="25"
          rounded-full
      /></template>
    </div>
  </header>
</template>
