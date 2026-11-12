<script setup>
import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import { dynamicTime, shortTimestamp } from 'shared/helpers/timeHelper';
const props = defineProps({
  timestamp: { type: [Number, String], required: true },
});
const label = ref('');
const refresh = () => {
  label.value = shortTimestamp(dynamicTime(props.timestamp));
};
let timer;
watch(() => props.timestamp, refresh, { immediate: true });
onMounted(() => {
  timer = setInterval(refresh, 60000);
});
onUnmounted(() => clearInterval(timer));
const exact = computed(() =>
  new Date(Number(props.timestamp) * 1000).toLocaleString()
);
</script>

<template>
  <time :title="exact">{{ label }}</time>
</template>
