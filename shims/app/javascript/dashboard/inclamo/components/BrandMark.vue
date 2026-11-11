<script setup>
import { t } from '../i18n';
defineProps({ compact: Boolean });
</script>

<template>
  <div class="inclamo-brand-mark" :class="{ 'is-compact': compact }">
    <img
      :src="
        compact
          ? '/brand-assets/inclamo-mark.svg'
          : '/brand-assets/inclamo-logo-combined.jpg'
      "
      :alt="t('BRAND.NAME')"
      :width="compact ? 36 : 64"
      :height="compact ? 36 : 64"
    />
  </div>
</template>
