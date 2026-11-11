<script setup>
import { useI18n } from 'vue-i18n';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import Button from 'dashboard/components-next/button/Button.vue';
const { t: nativeT } = useI18n();
</script>
<template>
  <div class="inclamo-global-tools flex gap-2">
    <RouterLink
      :to="{ name: 'search' }"
      :aria-label="nativeT('COMBOBOX.SEARCH_PLACEHOLDER')"
      :title="nativeT('COMBOBOX.SEARCH_PLACEHOLDER')"
      ><span class="i-lucide-search size-4" aria-hidden="true"
    /></RouterLink>
    <ComposeConversation align="end"
      ><template #trigger
        ><Button
          icon="i-lucide-pen-line"
          size="sm"
          color="slate"
          variant="ghost"
          :aria-label="nativeT('CONTACT_PANEL.NEW_MESSAGE')" /></template
    ></ComposeConversation>
  </div>
</template>
