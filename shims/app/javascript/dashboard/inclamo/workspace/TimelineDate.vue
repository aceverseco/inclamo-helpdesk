<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
const props = defineProps({ timestamp: Number });
const { locale } = useI18n();
const label = computed(() =>
  new Intl.DateTimeFormat(locale.value, {
    weekday: 'long',
    month: 'long',
    day: 'numeric',
  }).format(new Date(props.timestamp * 1000))
);
</script>

<template>
  <li class="inclamo-ref reference-date">
    <div class="date-separator">
      <time>{{ label }}</time>
    </div>
  </li>
</template>
