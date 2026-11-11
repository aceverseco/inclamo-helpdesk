<script setup>
import { ref, onErrorCaptured, watch } from 'vue';
import { t } from '../i18n';
const props = defineProps({ identity: { type: String, required: true } });
const failed = ref(false);
const attempt = ref(0);
onErrorCaptured(() => { failed.value = true; return false; });
watch(() => props.identity, () => { failed.value = false; });
const retry = () => { attempt.value += 1; failed.value = false; };
</script>
<template>
  <div v-if="failed" key="error" role="status" class="p-2 text-sm">
    <span>{{ t('WIDGETS.FAILED') }}</span>
    <button type="button" class="underline" @click="retry">{{ t('WIDGETS.RETRY') }}</button>
  </div>
  <div v-else :key="`content-${attempt}`"><slot /></div>
</template>
