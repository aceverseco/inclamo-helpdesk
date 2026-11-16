<script>
// Stands in for Chatwoot's menuItem.vue (kept beside this file as
// menuItem.chatwoot.vue) and renders it as it is: an item of the context menu carries the workspace theme's label.
// Props, listeners and slots pass through untouched.
import { h } from 'vue';
import Chatwoot from './menuItem.chatwoot.vue';

export default (props, { attrs, slots }) =>
  h(Chatwoot, { ...attrs, 'data-inclamo-control': 'context-menu-item' }, slots);
</script>
