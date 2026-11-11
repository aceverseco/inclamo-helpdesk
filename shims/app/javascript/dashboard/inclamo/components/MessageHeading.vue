<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
const props = defineProps({ name: String, createdAt: Number });
const { locale } = useI18n();
const date = computed(() => new Date(props.createdAt * 1000));
const time = computed(() =>
  new Intl.DateTimeFormat(locale.value, {
    hour: 'numeric',
    minute: '2-digit',
  }).format(date.value)
);
</script>
<template>
  <div class="inclamo-message-heading">
    <strong>{{ name }}</strong
    ><time :datetime="date.toISOString()">{{ time }}</time>
  </div>
</template>
