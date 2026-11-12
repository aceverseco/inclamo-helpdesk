<script setup>
import { ref, computed, defineAsyncComponent, onUnmounted } from 'vue';
import { Button } from '../ui/button';
import { captureAvailable, captureFrame, flattenImage, imageName } from './capture';
import { supportUI } from './state';
import { t } from '../i18n';
const ImageEditor = defineAsyncComponent(() => import('./ImageEditor.vue'));
const props = defineProps({
  draft: { type: Object, required: true }, metadata: { type: Object, default: null },
  busy: Boolean, reply: Boolean, error: { type: String, default: '' },
});
const emit = defineEmits(['submit']);
const editing = ref(null);
const localError = ref('');
const processing = ref(false);
const hasCapture = captureAvailable();
const sizeLimit = computed(() => props.metadata?.max_bytes || 10 * 1024 * 1024);
const countLimit = computed(() => props.metadata?.max_files || 5);
let disposed = false;
const remove = index => { const [file] = props.draft.files.splice(index, 1); if (file?.url) URL.revokeObjectURL(file.url); };
const add = async files => {
  localError.value = '';
  if (props.draft.files.length + files.length > countLimit.value) { localError.value = 'SUPPORT.FILE_COUNT'; return; }
  processing.value = true;
  try {
    for (const file of files) {
      if (file.size > sizeLimit.value || !['image/png', 'image/jpeg', 'image/webp', 'application/pdf', 'text/plain'].includes(file.type)) throw new Error('invalid_file');
      const blob = file.type.startsWith('image/') ? await flattenImage(file, sizeLimit.value) : file;
      if (disposed) return;
      if (blob.size > sizeLimit.value) throw new Error('invalid_file');
      const image = blob.type.startsWith('image/');
      props.draft.files.push({ blob, name: image ? imageName(file.name, blob.type) : file.name,
        url: image ? URL.createObjectURL(blob) : null, reference: null });
    }
  } catch { localError.value = 'SUPPORT.FILE_INVALID'; }
  finally { processing.value = false; }
};
const upload = async event => { await add(Array.from(event.target.files || [])); event.target.value = ''; };
const paste = event => {
  const images = Array.from(event.clipboardData?.files || []).filter(file => file.type.startsWith('image/'));
  if (images.length) { event.preventDefault(); add(images); }
};
const capture = async () => {
  if (props.draft.files.length >= countLimit.value) { localError.value = 'SUPPORT.FILE_COUNT'; return; }
  localError.value = '';
  processing.value = true;
  try {
    const blob = await captureFrame(() => {
      supportUI.capturing = true;
      document.documentElement.setAttribute('data-inclamo-capture', '');
    }, () => {
      supportUI.capturing = false;
      document.documentElement.removeAttribute('data-inclamo-capture');
    });
    if (!disposed) editing.value = { blob, index: null, name: 'screenshot.png' };
  } catch { localError.value = 'SUPPORT.CAPTURE_FAILED'; }
  finally { processing.value = false; }
};
const edited = blob => {
  if (blob.size > sizeLimit.value) { localError.value = 'SUPPORT.FILE_INVALID'; return; }
  const item = editing.value;
  const file = { blob, name: imageName(item.name, blob.type), reference: null, url: URL.createObjectURL(blob) };
  if (item.index === null) props.draft.files.push(file);
  else { URL.revokeObjectURL(props.draft.files[item.index].url); props.draft.files.splice(item.index, 1, file); }
  editing.value = null;
};
onUnmounted(() => { disposed = true; editing.value = null; });
</script>
<template>
  <div class="space-y-4" @paste="paste">
    <template v-if="!editing">
      <div v-if="metadata && !reply" class="text-sm"><strong>{{ metadata.author.name }}</strong> · {{ metadata.author.email }}<p>{{ metadata.account.name }}</p></div>
      <label v-if="!reply" class="flex flex-col gap-1">{{ t('SUPPORT.CATEGORY') }}
        <select v-model="draft.category" :disabled="busy"><option value="problem">{{ t('SUPPORT.CATEGORIES.problem') }}</option><option value="question">{{ t('SUPPORT.CATEGORIES.question') }}</option><option value="suggestion">{{ t('SUPPORT.CATEGORIES.suggestion') }}</option></select>
      </label>
      <label class="flex flex-col gap-1">{{ t(reply ? 'SUPPORT.REPLY' : 'SUPPORT.DESCRIPTION') }}
        <textarea v-model="draft.body" :disabled="busy" rows="5" maxlength="50000" class="rounded-lg border border-n-weak bg-n-alpha-2 p-3" data-testid="support-description" />
      </label>
      <div class="flex flex-wrap gap-2 items-center">
        <Button v-if="hasCapture" type="button" variant="outline" :disabled="busy || processing" @click="capture">{{ t('SUPPORT.CAPTURE') }}</Button>
        <label class="text-sm">{{ t('SUPPORT.UPLOAD') }}<input type="file" multiple accept="image/png,image/jpeg,image/webp,application/pdf,text/plain" :disabled="busy || processing" class="block max-w-full" @change="upload" /></label>
      </div>
      <p class="text-xs text-n-slate-11">{{ t('SUPPORT.FILE_LIMITS') }}</p>
      <ul class="space-y-2"><li v-for="(file, index) in draft.files" :key="file.url || file.name" class="border border-n-weak rounded-md p-2">
        <img v-if="file.url" :src="file.url" :alt="t('SUPPORT.IMAGE_PREVIEW')" class="max-h-40 max-w-full object-contain" />
        <span class="text-sm">{{ file.name }}</span>
        <Button v-if="file.url" type="button" variant="ghost" size="sm" :disabled="busy" @click="editing = { blob: file.blob, name: file.name, index }">{{ t('SUPPORT.EDIT_IMAGE') }}</Button>
        <Button type="button" variant="ghost" size="sm" :disabled="busy" @click="remove(index)">{{ t('SUPPORT.REMOVE') }}</Button>
      </li></ul>
      <details v-if="!reply" open class="text-xs border border-n-weak rounded-lg p-3">
        <summary>{{ t('SUPPORT.CONTEXT') }}</summary>
        <dl class="break-words"><dt>{{ t('SUPPORT.VERSION') }}</dt><dd>{{ metadata?.version }}</dd><dt>{{ t('SUPPORT.TIME') }}</dt><dd>{{ draft.context.timestamp }}</dd><dt>{{ t('SUPPORT.BROWSER') }}</dt><dd>{{ draft.context.browser }}</dd><dt>{{ t('SUPPORT.LOCATION') }}</dt><dd>{{ draft.context.location }}</dd></dl>
        <label v-if="draft.conversationReference" class="flex gap-2 mt-2"><input v-model="draft.includeConversation" type="checkbox" />{{ t('SUPPORT.INCLUDE_CONVERSATION', { id: draft.conversationReference }) }}</label>
        <p class="mt-2">{{ t('SUPPORT.CONTEXT_HINT') }}</p>
      </details>
      <p v-if="localError || error" role="alert" class="text-sm text-n-ruby-11">{{ t(localError || error) }}</p>
      <Button type="button" :disabled="busy || processing || !draft.body.trim() || (!metadata && !reply)" data-testid="support-submit" @click="emit('submit')">{{ t(busy ? 'SUPPORT.SENDING' : 'SUPPORT.SEND') }}</Button>
    </template>
    <ImageEditor v-else :image="editing.blob" :max-bytes="sizeLimit" @done="edited" @cancel="editing = null" />
  </div>
</template>
