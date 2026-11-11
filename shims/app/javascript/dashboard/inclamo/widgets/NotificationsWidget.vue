<script setup>
import { useMapGetter } from 'dashboard/composables/store';
import { t } from '../i18n';
const unread = useMapGetter('notifications/getUnreadCount');
</script>
<template>
  <RouterLink :to="{ name: 'inbox_view' }" class="inclamo-notification-widget"
    :aria-label="t('WORKSPACE.NOTIFICATION_COUNT', { count: unread || 0 })" :title="t('WORKSPACE.NOTIFICATION_COUNT', { count: unread || 0 })">
    <span class="i-lucide-bell size-5" aria-hidden="true" /><span v-if="unread" class="inclamo-widget-badge">{{ unread > 99 ? '99+' : unread }}</span>
  </RouterLink>
</template>
<style scoped>
.inclamo-notification-widget { display:flex; position:relative; align-items:center; justify-content:center; width:36px; height:36px; border-radius:10px; color:#fff; background:linear-gradient(145deg,#a66af6,#6240ce); }
.inclamo-notification-widget:focus-visible { outline:2px solid currentColor; outline-offset:3px; }
.inclamo-widget-badge { position:absolute; inset-inline-end:-3px; top:-3px; border-radius:10px; padding:0 4px; background:#be123c; color:#fff; font-size:10px; }
</style>
