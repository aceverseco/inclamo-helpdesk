<script>
// Stands in for Chatwoot's SettingsWrapper.vue (kept beside this file as
// SettingsWrapper.chatwoot.vue) and renders it as it is: a settings page carries the workspace theme's label.
// Props, listeners and slots pass through untouched.
import { defineComponent, h } from 'vue';
import Chatwoot from './SettingsWrapper.chatwoot.vue';

// A component, not a function: the router takes a function for a page to load.
export default defineComponent({
  name: 'InclamoSettingsWrapper',
  inheritAttrs: false,
  setup(_, { attrs, slots }) {
    return () => h(Chatwoot, { ...attrs, class: [attrs.class, 'inclamo-settings-page'] }, slots);
  },
});
</script>
