import { defineAsyncComponent, markRaw } from 'vue';
import manifest from '../../../../../custom/config/workspace_widgets.json';

export { manifest };
const loaders = {
  'customer-profile': () => import('./CustomerProfileWidget.vue'),
  'purchase-statistics': () => import('./PurchaseStatisticsWidget.vue'),
  orders: () => import('./OrdersWidget.vue'),
  'sla-overview': () => import('./SlaOverviewWidget.vue'),
  notifications: () => import('./NotificationsWidget.vue'),
};

// Both hosts use descriptors; adding a built-in requires no host changes.
export function createRegistry(definition, components) {
  const registry = new Map();
  for (const descriptor of definition.widgets) {
    if (registry.has(descriptor.id)) throw new Error('duplicate_widget');
    if (!definition.placements.includes(descriptor.placement)) throw new Error('unsupported_placement');
    if (!components[descriptor.id]) throw new Error('missing_component');
    registry.set(descriptor.id, {
      ...descriptor,
      available: context => descriptor.placement === 'workspace-header' || Boolean(context.conversationId),
      component: markRaw(defineAsyncComponent(components[descriptor.id])),
    });
  }
  return registry;
}
export const registry = createRegistry(manifest, loaders);
export const productLayout = () => ({
  schema_version: manifest.schema_version,
  placements: Object.fromEntries(manifest.placements.map(placement => [
    placement,
    manifest.widgets.filter(widget => widget.placement === placement).map(widget => ({ id: widget.id, collapsed: false })),
  ])),
});
export const copyLayout = layout => JSON.parse(JSON.stringify(layout));
export const entriesFor = (layout, placement, descriptors = registry) =>
  (layout?.placements?.[placement] || []).filter(entry => descriptors.get(entry.id)?.placement === placement);
