<script setup>
// Stands in for Chatwoot's dashboard App.vue (kept beside this file as
// App.chatwoot.vue) and renders it as it is. Two additions. While the staff
// application is mounted, the page carries the workspace theme's scope
// (dashboard/inclamo/theme). And the interface language Chatwoot chooses is
// passed on to the overlay's own screens, with the forms of counted words a
// language needs (dashboard/inclamo/language).
import ChatwootApp from './App.chatwoot.vue';
import { useApplicationTheme } from './inclamo/theme/useApplicationTheme';
import { useInterfaceLanguage } from './inclamo/language';

useApplicationTheme();
useInterfaceLanguage();
</script>

<template>
  <ChatwootApp />
</template>
