<script setup>
import { computed } from 'vue';
import { entriesFor, registry } from './registry';
import { useWorkspaceLayout } from './layoutState';
import WidgetBoundary from './WidgetBoundary.vue';
import PersonalLayout from './PersonalLayout.vue';
import { t } from '../i18n';
const props = defineProps({
  placement: { type: String, required: true }, context: { type: Object, default: () => ({}) },
});
const { state, save, refresh } = useWorkspaceLayout();
const entries = computed(() => entriesFor(state.value.layout, props.placement).filter(entry => registry.get(entry.id).available(props.context)));
const toggle = async entry => {
  const layout = JSON.parse(JSON.stringify(state.value.layout));
  layout.placements[props.placement].find(item => item.id === entry.id).collapsed = !entry.collapsed;
  try { await save(layout, state.value.revision); } catch { await refresh(); }
};
</script>
<template>
  <div :class="placement === 'workspace-header' ? 'inclamo-widget-dock' : 'inclamo-widget-sidebar'" :data-widget-host="placement">
    <div class="inclamo-widget-items">
      <section v-for="entry in entries" :key="entry.id" :data-widget="entry.id" class="inclamo-widget">
        <button v-if="placement === 'conversation-sidebar'" type="button" class="inclamo-widget-heading"
          :aria-expanded="!entry.collapsed" :disabled="!state.revision" @click="toggle(entry)">
          <span>{{ t(registry.get(entry.id).label) }}</span><span aria-hidden="true">{{ entry.collapsed ? '+' : '−' }}</span>
        </button>
        <WidgetBoundary v-if="!entry.collapsed || placement === 'workspace-header'" :identity="`${entry.id}:${context.accountId}:${context.conversationId}`">
          <component :is="registry.get(entry.id).component" :context="context"><slot :name="entry.id" /></component>
        </WidgetBoundary>
      </section>
      <p v-if="!entries.length && placement === 'conversation-sidebar'" class="p-3 text-sm">{{ t('WIDGETS.EMPTY') }}</p>
    </div>
    <PersonalLayout><span v-if="placement === 'conversation-sidebar'">{{ t('WIDGETS.CONFIGURE') }}</span></PersonalLayout>
  </div>
</template>
<style scoped>
.inclamo-widget-dock { display:flex; align-items:center; justify-content:center; gap:4px; min-width:0; flex:1; }
.inclamo-widget-dock .inclamo-widget-items { display:flex; gap:8px; min-width:0; overflow-x:auto; padding:4px; }
.inclamo-widget-dock > :deep(button) { flex-shrink:0; }
.inclamo-widget-sidebar .inclamo-widget { border-bottom:1px solid var(--color-border, rgba(128,128,128,.2)); padding-block:8px; }
.inclamo-widget-heading { width:100%; display:flex; justify-content:space-between; padding:6px 12px; font-size:12px; font-weight:600; }
.inclamo-widget-dock .inclamo-widget { flex:0 0 auto; }
</style>
