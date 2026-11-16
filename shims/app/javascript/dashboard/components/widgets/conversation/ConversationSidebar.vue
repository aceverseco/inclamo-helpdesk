<script>
// Stands in for Chatwoot's ConversationSidebar.vue (kept beside this file as
// ConversationSidebar.chatwoot.vue) and renders it as it is: the customer sidebar carries the workspace theme's label.
// Props, listeners and slots pass through untouched.
import { defineComponent, h } from 'vue';
import Chatwoot from './ConversationSidebar.chatwoot.vue';

// A component, not a function: the router takes a function for a page to load.
export default defineComponent({
  name: 'InclamoConversationSidebar',
  inheritAttrs: false,
  setup(_, { attrs, slots }) {
    return () => h(Chatwoot, { ...attrs, class: [attrs.class, 'inclamo-customer-sidebar'] }, slots);
  },
});
</script>
