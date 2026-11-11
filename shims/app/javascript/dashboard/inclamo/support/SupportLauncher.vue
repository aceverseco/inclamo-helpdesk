<script setup>
import { defineAsyncComponent, watch } from 'vue';
import { useRoute } from 'vue-router';
import { Button } from '../ui/button';
import { openSupport, supportUI } from './state';
import { t } from '../i18n';
const Shell = defineAsyncComponent(() => import('./SupportShell.vue'));
const route = useRoute();
watch(() => route.query.support_request, reference => {
  if (typeof reference === 'string' && /^[0-9a-f-]{36}$/i.test(reference)) openSupport(reference);
}, { immediate: true });
</script>
<template>
  <Button type="button" variant="ghost" size="sm" :aria-label="t('SUPPORT.TITLE')" :title="t('SUPPORT.TITLE')" data-testid="inclamo-support-open" @click="openSupport()">
    <span class="i-lucide-life-buoy size-4" aria-hidden="true" />
  </Button>
  <Shell v-if="supportUI.sequence" />
</template>
