<script>
// Stands in for Chatwoot's SettingsWrapper.vue (kept beside this file as
// SettingsWrapper.chatwoot.vue) and renders it as it is: a settings page carries the workspace theme's label.
// Props, listeners and slots pass through untouched.
import { h } from 'vue';
import Chatwoot from './SettingsWrapper.chatwoot.vue';

export default (props, { attrs, slots }) =>
  h(Chatwoot, { ...attrs, class: [attrs.class, 'inclamo-settings-page'] }, slots);
</script>
