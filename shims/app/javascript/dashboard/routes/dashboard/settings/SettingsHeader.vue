<script>
// Stands in for Chatwoot's SettingsHeader.vue (kept beside this file as
// SettingsHeader.chatwoot.vue) and renders it as it is: the heading of a settings page carries the workspace theme's label.
// Props, listeners and slots pass through untouched.
import { defineComponent, h } from 'vue';
import Chatwoot from './SettingsHeader.chatwoot.vue';

// A component, not a function: the router takes a function for a page to load.
export default defineComponent({
  name: 'InclamoSettingsHeader',
  inheritAttrs: false,
  setup(_, { attrs, slots }) {
    return () => h(Chatwoot, { ...attrs, class: [attrs.class, 'inclamo-page-heading'] }, slots);
  },
});
</script>
