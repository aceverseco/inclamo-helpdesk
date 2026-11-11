<script setup>
import { ref, onMounted, onUnmounted } from 'vue';
import { Button } from '../ui/button';
import { canvasBlob } from './capture';
import { t } from '../i18n';
const props = defineProps({ image: { type: Blob, required: true } });
const emit = defineEmits(['done', 'cancel']);
const canvas = ref(null);
const tool = ref('rectangle');
const history = [];
const historySize = ref(0);
const busy = ref(true);
const failed = ref(false);
let start;
let disposed = false;
const point = event => {
  const bounds = canvas.value.getBoundingClientRect();
  return { x: Math.max(0, Math.min(canvas.value.width, (event.clientX - bounds.left) * canvas.value.width / bounds.width)),
    y: Math.max(0, Math.min(canvas.value.height, (event.clientY - bounds.top) * canvas.value.height / bounds.height)) };
};
const remember = () => {
  history.push(canvas.value.getContext('2d').getImageData(0, 0, canvas.value.width, canvas.value.height));
  if (history.length > 3) history.shift();
  historySize.value = history.length;
};
const undo = () => {
  const previous = history.pop();
  if (!previous) return;
  canvas.value.width = previous.width;
  canvas.value.height = previous.height;
  canvas.value.getContext('2d').putImageData(previous, 0, 0);
  historySize.value = history.length;
};
const begin = event => {
  if (busy.value || failed.value) return;
  start = point(event);
  canvas.value.setPointerCapture(event.pointerId);
};
const finish = event => {
  if (!start) return;
  const end = point(event);
  const from = start;
  start = null;
  const x = Math.floor(Math.min(from.x, end.x));
  const y = Math.floor(Math.min(from.y, end.y));
  const width = Math.min(canvas.value.width - x, Math.ceil(Math.abs(end.x - from.x)));
  const height = Math.min(canvas.value.height - y, Math.ceil(Math.abs(end.y - from.y)));
  if (tool.value === 'arrow' ? Math.hypot(end.x - from.x, end.y - from.y) < 2 : width < 2 || height < 2) return;
  remember();
  const context = canvas.value.getContext('2d');
  context.lineWidth = Math.max(3, canvas.value.width / 400);
  context.strokeStyle = '#ff6b00';
  if (tool.value === 'crop') {
    const pixels = context.getImageData(x, y, width, height);
    canvas.value.width = width;
    canvas.value.height = height;
    context.putImageData(pixels, 0, 0);
  } else if (tool.value === 'redact') {
    context.fillStyle = '#000000';
    context.globalAlpha = 1;
    context.fillRect(x, y, width, height);
  } else if (tool.value === 'rectangle') {
    context.strokeRect(x, y, width, height);
  } else {
    const angle = Math.atan2(end.y - from.y, end.x - from.x);
    const length = Math.max(15, canvas.value.width / 70);
    context.beginPath(); context.moveTo(from.x, from.y); context.lineTo(end.x, end.y);
    context.moveTo(end.x - length * Math.cos(angle - Math.PI / 6), end.y - length * Math.sin(angle - Math.PI / 6));
    context.lineTo(end.x, end.y);
    context.lineTo(end.x - length * Math.cos(angle + Math.PI / 6), end.y - length * Math.sin(angle + Math.PI / 6));
    context.stroke();
  }
};
onMounted(async () => {
  let bitmap;
  try {
    bitmap = await createImageBitmap(props.image);
    if (disposed) return;
    if (bitmap.width * bitmap.height > 16_000_000) throw new Error('image_dimensions');
    canvas.value.width = bitmap.width;
    canvas.value.height = bitmap.height;
    canvas.value.getContext('2d').drawImage(bitmap, 0, 0);
  } catch { failed.value = true; }
  finally { bitmap?.close(); busy.value = false; }
});
const done = async () => {
  busy.value = true;
  try { const flattened = await canvasBlob(canvas.value); if (!disposed) emit('done', flattened); }
  catch { failed.value = true; }
  finally { busy.value = false; }
};
onUnmounted(() => { disposed = true; history.length = 0; if (canvas.value) canvas.value.width = canvas.value.height = 0; });
</script>
<template>
  <section class="space-y-3" data-testid="support-image-editor">
    <p class="text-sm">{{ t('SUPPORT.EDITOR_HINT') }}</p>
    <div class="flex flex-wrap gap-2" role="toolbar" :aria-label="t('SUPPORT.EDIT_IMAGE')">
      <Button v-for="item in ['crop', 'arrow', 'rectangle', 'redact']" :key="item" type="button" size="sm" :variant="tool === item ? 'default' : 'outline'" :aria-pressed="tool === item" @click="tool = item">{{ t(`SUPPORT.TOOLS.${item}`) }}</Button>
      <Button type="button" size="sm" variant="outline" :disabled="!historySize" @click="undo">{{ t('SUPPORT.UNDO') }}</Button>
    </div>
    <p v-if="failed" role="alert">{{ t('SUPPORT.IMAGE_FAILED') }}</p>
    <canvas ref="canvas" class="max-w-full border border-n-weak" style="touch-action: none" :aria-label="t('SUPPORT.IMAGE_PREVIEW')" @pointerdown="begin" @pointerup="finish" @pointercancel="start = null" />
    <div class="flex gap-2"><Button type="button" :disabled="busy || failed" @click="done">{{ t('SUPPORT.USE_IMAGE') }}</Button><Button type="button" variant="outline" @click="emit('cancel')">{{ t('SUPPORT.CANCEL') }}</Button></div>
  </section>
</template>
