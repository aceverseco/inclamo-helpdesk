<script setup>
import { ref, computed } from 'vue';
import { useRoute } from 'vue-router';
import WidgetHost from '../widgets/WidgetHost.vue';
import PersonalLayout from '../widgets/PersonalLayout.vue';
import { useCommerce } from '../widgets/commerce';
import { useWorkspaceLayout } from '../widgets/layoutState';
import { entriesFor } from '../widgets/registry';
import { useI18n } from 'vue-i18n';
import { X, SlidersHorizontal } from 'lucide-vue-next';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '../ui/tabs';
import { Button } from '../ui/button';
import { t } from '../i18n';
const props = defineProps({
  conversationId: { type: [String, Number], required: true },
  contactId: { type: [String, Number], default: undefined },
});
const route = useRoute();
const context = computed(() => ({ ...props, accountId: route.params.accountId }));
// Keep reply-order context fresh even if every optional commerce card is hidden.
useCommerce(() => context.value);
const { state } = useWorkspaceLayout();
const enabled = id => entriesFor(state.value.layout, 'conversation-sidebar').some(entry => entry.id === id);
const emit = defineEmits(['close']);
const { t: nativeT } = useI18n();
const tab = ref('details');
</script>

<template>
  <div class="inclamo-ref reference-customer-pane">
    <Tabs v-model="tab">
      <div class="customer-tabs-bar">
        <TabsList class="customer-tabs">
          <TabsTrigger value="details">
            {{ t('WORKSPACE.DETAILS') }}
          </TabsTrigger>
          <TabsTrigger value="manage">
            <SlidersHorizontal />
            {{ t('WORKSPACE.MANAGE') }}
          </TabsTrigger>
        </TabsList>
        <PersonalLayout />
        <Button
          variant="ghost"
          size="icon"
          class="icon-button"
          :aria-label="nativeT('GENERAL.CLOSE')"
          @click="emit('close')"
        >
          <X />
        </Button>
      </div>
      <TabsContent value="details" class="reference-customer-body">
        <slot name="labels" />
        <WidgetHost placement="conversation-sidebar" :context="context">
          <template #customer-profile><slot name="profile" /></template>
        </WidgetHost>
      </TabsContent>
      <TabsContent value="manage" class="reference-customer-manage">
        <slot v-if="!enabled('customer-profile')" name="profile" />
        <slot v-if="!enabled('orders')" name="commerce" />
        <slot name="manage" />
      </TabsContent>
    </Tabs>
  </div>
</template>
