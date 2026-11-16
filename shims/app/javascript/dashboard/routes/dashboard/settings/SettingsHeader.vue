<script>
// Stands in for Chatwoot's SettingsHeader.vue (kept beside this file as
// SettingsHeader.chatwoot.vue) and renders it as it is: the heading of a settings page carries the workspace theme's label.
// Props, listeners and slots pass through untouched.
import { h } from 'vue';
import Chatwoot from './SettingsHeader.chatwoot.vue';

export default (props, { attrs, slots }) =>
  h(Chatwoot, { ...attrs, class: [attrs.class, 'inclamo-page-heading'] }, slots);
</script>
