<script setup>
import { computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useSidebarContext } from 'dashboard/components-next/sidebar/provider';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import {
  getUserPermissions,
  filterItemsByPermission,
} from 'dashboard/helper/permissionsHelper';
import { ASSIGNEE_TYPE_TAB_PERMISSIONS } from 'dashboard/constants/permissions';
import {
  Inbox,
  UserRound,
  UsersRound,
  ChevronDown,
  BookOpen,
  CircleHelp,
  Settings2,
  MoreHorizontal,
  Mail,
  Bell,
  ArrowUpRight,
} from 'lucide-vue-next';
import { Button } from '../ui/button';
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
} from '../ui/dropdown-menu';
import { t } from '../i18n';
import { useQueueCounts } from './useQueueCounts';
const props = defineProps({
  items: { type: Array, required: true },
  collapsed: Boolean,
});
const emit = defineEmits(['help']);
const route = useRoute();
const router = useRouter();
const { isAllowed, resolvePath } = useSidebarContext();
const { accountId, accountScopedRoute } = useAccount();
const currentUser = useMapGetter('getCurrentUser');
const filters = useMapGetter('getChatListFilters');
const stats = useQueueCounts(accountId);
const notifications = useMapGetter('notifications/getUnreadCount');
const primary = computed(() =>
  props.items.find(item => item.name === 'Conversation')
);
const channelGroup = computed(() =>
  primary.value?.children?.find(item => item.name === 'Channels')
);
const channels = computed(() =>
  (channelGroup.value?.children || []).filter(item => isAllowed(item.to))
);
function leaves(items) {
  return items.flatMap(item => {
    if (item.children) return leaves(item.children);
    return item.to && isAllowed(item.to) ? [item] : [];
  });
}

const group = name => props.items.find(item => item.name === name);
const first = name => leaves(group(name) ? [group(name)] : [])[0];
const customers = computed(() => first('Contacts'));
const knowledge = computed(() => first('Portals'));
const inbox = computed(() => first('Inbox'));
const queues = computed(() =>
  filterItemsByPermission(
    ASSIGNEE_TYPE_TAB_PERMISSIONS,
    getUserPermissions(currentUser.value, Number(accountId.value)),
    item => item.permissions
  ).sort(
    (a, b) =>
      ['all', 'me', 'unassigned'].indexOf(a.key) -
      ['all', 'me', 'unassigned'].indexOf(b.key)
  )
);
const queueNames = { all: 'ALL', me: 'MINE', unassigned: 'UNASSIGNED' };
const queueIcons = { all: Inbox, me: UserRound, unassigned: UsersRound };
const inMainInbox = computed(() =>
  ['home', 'inbox_conversation'].includes(route.name)
);
const activeQueue = computed(
  () => filters.value?.assigneeType || route.query.queue || 'all'
);
const extraGroups = computed(() =>
  props.items
    .filter(
      item => !['Conversation', 'Contacts', 'Portals'].includes(item.name)
    )
    .map(item => ({ ...item, links: leaves([item]) }))
    .filter(item => item.links.length)
);
const websiteWidget = computed(() => extraGroups.value.flatMap(item => item.links).find(item => item.name === 'Settings inclamo_website_widget'));
const views = computed(() =>
  leaves(
    (primary.value?.children || []).filter(
      item => !['All', 'Channels'].includes(item.name)
    )
  )
);
const customerViews = computed(() =>
  leaves(group('Contacts')?.children || []).slice(1)
);
const isCurrent = item =>
  resolvePath(item.to) === route.path || item.activeOn?.includes(route.name);
function selectQueue(key) {
  router.push({ ...accountScopedRoute('home'), query: { queue: key } });
}
</script>

<template>
  <nav
    class="inclamo-ref reference-navigation"
    :class="{ collapsed }"
    :aria-label="t('WORKSPACE.HEADING')"
  >
    <div class="nav-heading">{{ t('WORKSPACE.HEADING') }}</div>
    <button
      class="nav-section-title"
      :title="t('WORKSPACE.INBOX')"
      @click="selectQueue(queues[0]?.key || 'me')"
    >
      <Inbox />
      <strong>{{ t('WORKSPACE.INBOX') }}</strong>
      <ChevronDown class="trailing" />
    </button>
    <div class="queue-nav">
      <button
        v-for="item in queues"
        :key="item.key"
        class="nav-row"
        :class="{ selected: inMainInbox && activeQueue === item.key }"
        :aria-current="
          inMainInbox && activeQueue === item.key ? 'page' : undefined
        "
        :title="t(`WORKSPACE.${queueNames[item.key]}`)"
        :data-testid="`inclamo-queue-${item.key}`"
        @click="selectQueue(item.key)"
      >
        <component :is="queueIcons[item.key]" />
        <span>{{ t(`WORKSPACE.${queueNames[item.key]}`) }}</span>
        <span class="nav-count" :title="t('WORKSPACE.OPEN_COUNT')">
          {{ stats?.[item.count] ?? '—' }}
        </span>
      </button>
    </div>
    <RouterLink
      v-if="customers"
      :to="customers.to"
      class="nav-row standalone"
      :class="{ selected: route.path.includes('/contacts') }"
      :title="t('WORKSPACE.CUSTOMERS')"
    >
      <UsersRound />
      <span>{{ t('WORKSPACE.CUSTOMERS') }}</span>
    </RouterLink>
    <RouterLink
      v-if="knowledge"
      :to="knowledge.to"
      class="nav-row standalone"
      :class="{ selected: route.path.includes('/portals') }"
      :title="t('WORKSPACE.KNOWLEDGE')"
    >
      <BookOpen />
      <span>{{ t('WORKSPACE.KNOWLEDGE') }}</span>
    </RouterLink>
    <div class="nav-heading channel-heading">
      {{ t('WORKSPACE.CHANNELS') }}
      <span class="channel-count">{{ channels.length }}</span>
    </div>
    <div class="channel-nav">
      <RouterLink
        v-for="item in channels"
        :key="item.name"
        :to="item.to"
        class="nav-row"
        :class="{ selected: isCurrent(item) }"
        :title="item.label"
      >
        <component :is="item.icon" v-if="item.icon" />
        <Mail v-else />
        <span>{{ item.label }}</span>
        <span v-if="item.badgeCount" class="nav-count">
          {{ item.badgeCount }}
        </span>
      </RouterLink>
    </div>
    <div class="nav-spacer" />
    <RouterLink
      v-if="inbox"
      :to="inbox.to"
      class="notification-card"
      :class="{ selected: isCurrent(inbox) }"
    >
      <span class="notification-card-icon"><Bell /></span>
      <span>
        <strong>{{ t('WORKSPACE.NOTIFICATIONS') }}</strong>
        <small>
          {{
            notifications
              ? t('WORKSPACE.NOTIFICATION_COUNT', { count: notifications })
              : t('WORKSPACE.CAUGHT_UP')
          }}
        </small>
      </span>
      <ArrowUpRight />
    </RouterLink>
    <DropdownMenu>
      <DropdownMenuTrigger as-child>
        <Button variant="ghost" class="nav-row" :title="t('WORKSPACE.MORE')">
          <Settings2 />
          <span>{{ t('WORKSPACE.MORE') }}</span>
          <MoreHorizontal class="trailing" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent
        side="right"
        align="end"
        class="reference-navigation-menu"
      >
        <DropdownMenuItem v-if="websiteWidget" as-child><RouterLink :to="websiteWidget.to">{{ t('WEBSITE_WIDGET.WEBSITE_WIDGET') }}</RouterLink></DropdownMenuItem>
        <template v-if="views.length">
          <DropdownMenuLabel>{{ t('WORKSPACE.VIEWS') }}</DropdownMenuLabel>
          <DropdownMenuItem v-for="item in views" :key="item.name" as-child>
            <RouterLink :to="item.to">{{ item.label }}</RouterLink>
          </DropdownMenuItem>
        </template>
        <template v-if="customerViews.length">
          <DropdownMenuLabel>{{ t('WORKSPACE.CUSTOMERS') }}</DropdownMenuLabel>
          <DropdownMenuItem
            v-for="item in customerViews"
            :key="item.name"
            as-child
          >
            <RouterLink :to="item.to">{{ item.label }}</RouterLink>
          </DropdownMenuItem>
        </template>
        <template v-for="item in extraGroups" :key="item.name">
          <DropdownMenuSeparator />
          <DropdownMenuLabel>{{ item.label }}</DropdownMenuLabel>
          <DropdownMenuItem
            v-for="link in item.links"
            :key="link.name"
            as-child
          >
            <RouterLink :to="link.to">{{ link.label }}</RouterLink>
          </DropdownMenuItem>
        </template>
      </DropdownMenuContent>
    </DropdownMenu>
    <button
      class="nav-row help-link"
      :title="t('WORKSPACE.HELP')"
      @click="emit('help')"
    >
      <CircleHelp />
      <span>{{ t('WORKSPACE.HELP') }}</span>
      <kbd>?</kbd>
    </button>
  </nav>
</template>
