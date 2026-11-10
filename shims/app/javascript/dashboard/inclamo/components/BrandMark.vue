<script setup>
import { t } from "../i18n";
defineProps({ compact: Boolean });
</script>

<template>
  <div class="inclamo-brand-mark" :class="{ 'is-compact': compact }">
    <img
      :src="'/brand-assets/inclamo-mark.svg'"
      :alt="compact ? t('BRAND.NAME') : ''"
      width="36"
      height="36"
    />
    <span v-if="!compact"
      >{{ t("BRAND.WORDMARK") }}<span class="inclamo-brand-dot">.</span></span
    >
  </div>
</template>
