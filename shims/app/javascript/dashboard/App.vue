<script setup>
// Stands in for Chatwoot's dashboard App.vue (kept beside this file as
// App.chatwoot.vue) and renders it as it is. The only addition: while the
// staff application is mounted, the page carries the workspace theme's scope
// (dashboard/inclamo/theme).
import ChatwootApp from './App.chatwoot.vue';
import { useApplicationTheme } from './inclamo/theme/useApplicationTheme';

useApplicationTheme();
</script>

<template>
  <ChatwootApp />
</template>
