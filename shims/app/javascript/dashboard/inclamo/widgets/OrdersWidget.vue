<script setup>
import OrdersSection from '../components/OrdersSection.vue';
defineProps({ context: { type: Object, required: true } });
</script>
<template><OrdersSection :conversation-id="context.conversationId" :contact-id="context.contactId" :account-id="context.accountId" :show-statistics="false" /></template>
