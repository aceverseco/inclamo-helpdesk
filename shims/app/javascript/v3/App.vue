<script setup>
// Stands in for Chatwoot's sign-in App.vue (kept beside this file as
// App.chatwoot.vue) and renders it as it is, inside the workspace theme's
// scope and with the theme's styles for the sign-in pages after Chatwoot's.
// The language of these pages is passed on to the overlay's own texts.
import ChatwootApp from './App.chatwoot.vue';
import { useApplicationTheme } from 'dashboard/inclamo/theme/useApplicationTheme';
import { useInterfaceLanguage } from 'dashboard/inclamo/language';

useApplicationTheme();
useInterfaceLanguage();
</script>

<template>
  <ChatwootApp class="inclamo-auth-root" />
</template>

<style lang="scss">
@import 'shared/assets/fonts/InterDisplay/inter-display';
@import '../dashboard/inclamo/theme/authentication';
</style>
