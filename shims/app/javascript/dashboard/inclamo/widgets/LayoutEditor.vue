<script setup>
import { ref } from 'vue';
import { Button } from '../ui/button';
import { manifest, registry, copyLayout } from './registry';
import { t } from '../i18n';
const props = defineProps({ modelValue: { type: Object, required: true } });
const emit = defineEmits(['update:modelValue']);
const dragged = ref(null);
const change = callback => {
  const next = copyLayout(props.modelValue);
  callback(next.placements);
  emit('update:modelValue', next);
};
const move = (placement, from, to) => change(placements => {
  if (to < 0 || to >= placements[placement].length) return;
  placements[placement].splice(to, 0, placements[placement].splice(from, 1)[0]);
});
const drop = (placement, to) => {
  if (dragged.value?.placement === placement) move(placement, dragged.value.index, to);
  dragged.value = null;
};
const remove = (placement, index) => change(placements => placements[placement].splice(index, 1));
const add = widget => change(placements => placements[widget.placement].push({ id: widget.id, collapsed: false }));
const included = id => Object.values(props.modelValue.placements).some(entries => entries.some(entry => entry.id === id));
</script>
<template>
  <div class="space-y-5" data-testid="widget-layout-editor">
    <section v-for="placement in manifest.placements" :key="placement">
      <h4>{{ t(placement === 'workspace-header' ? 'WIDGETS.HEADER' : 'WIDGETS.SIDEBAR') }}</h4>
      <ol class="space-y-2">
        <li v-for="(entry, index) in modelValue.placements[placement]" :key="entry.id"
          class="rounded-md border border-n-weak p-2 flex flex-wrap items-center gap-2"
          draggable="true" @dragstart="dragged = { placement, index }" @dragend="dragged = null"
          @dragover.prevent @drop.prevent="drop(placement, index)">
          <span class="flex-1">{{ registry.has(entry.id) ? t(registry.get(entry.id).label) : t('WIDGETS.UNAVAILABLE', { id: entry.id }) }}</span>
          <Button type="button" variant="ghost" size="sm" :disabled="index === 0" :aria-label="t('WIDGETS.UP')" @click="move(placement, index, index - 1)">↑</Button>
          <Button type="button" variant="ghost" size="sm" :disabled="index === modelValue.placements[placement].length - 1" :aria-label="t('WIDGETS.DOWN')" @click="move(placement, index, index + 1)">↓</Button>
          <label v-if="placement === 'conversation-sidebar'" class="flex gap-1 text-xs">
            <input type="checkbox" :checked="entry.collapsed" @change="change(placements => { placements[placement][index].collapsed = $event.target.checked; })" />
            {{ t('WIDGETS.COLLAPSED') }}
          </label>
          <Button type="button" variant="ghost" size="sm" @click="remove(placement, index)">{{ t('WIDGETS.REMOVE') }}</Button>
        </li>
      </ol>
      <p v-if="!modelValue.placements[placement].length" class="text-sm text-n-slate-11">{{ t('WIDGETS.EMPTY') }}</p>
      <div v-for="widget in manifest.widgets.filter(item => item.placement === placement && !included(item.id))" :key="widget.id" class="flex gap-2 items-center py-2">
        <div class="flex-1 text-sm"><strong>{{ t(widget.label) }}</strong><p>{{ t(widget.description) }}</p></div>
        <Button type="button" variant="outline" size="sm" @click="add(widget)">{{ t('WIDGETS.ADD') }}</Button>
      </div>
    </section>
  </div>
</template>
