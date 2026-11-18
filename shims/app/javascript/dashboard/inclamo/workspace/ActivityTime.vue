<script setup>
import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import { dynamicTime, shortTimestamp } from 'shared/helpers/timeHelper';
import { formatLanguage, has, t } from '../i18n';

const props = defineProps({
  timestamp: { type: [Number, String], required: true },
});
// Chatwoot's short age of a moment: "now", "5m", "2h", "3d", "1mo", "1y".
const age = ref('');
const refresh = () => {
  age.value = shortTimestamp(dynamicTime(props.timestamp));
};
let timer;
watch(() => props.timestamp, refresh, { immediate: true });
onMounted(() => {
  timer = setInterval(refresh, 60000);
});
onUnmounted(() => clearInterval(timer));
// The same age in the words of the interface language. An age in a shape
// this does not know is shown as Chatwoot gave it.
const label = computed(() => {
  const [, count, unit] = age.value.trim().match(/^(\d+)\s*([a-z]+)$/) || [];
  if (unit && has(`WORKSPACE.TIME.${unit}`)) return t(`WORKSPACE.TIME.${unit}`, { count });
  return age.value === 'now' ? t('WORKSPACE.TIME.now') : age.value;
});
const exact = computed(() =>
  new Date(Number(props.timestamp) * 1000).toLocaleString(formatLanguage())
);
</script>

<template>
  <time :title="exact">{{ label }}</time>
</template>
