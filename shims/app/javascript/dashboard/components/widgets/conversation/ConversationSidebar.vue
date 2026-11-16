<script>
// Stands in for Chatwoot's ConversationSidebar.vue (kept beside this file as
// ConversationSidebar.chatwoot.vue) and renders it as it is: the customer sidebar carries the workspace theme's label.
// Props, listeners and slots pass through untouched.
import { h } from 'vue';
import Chatwoot from './ConversationSidebar.chatwoot.vue';

export default (props, { attrs, slots }) =>
  h(Chatwoot, { ...attrs, class: [attrs.class, 'inclamo-customer-sidebar'] }, slots);
</script>
