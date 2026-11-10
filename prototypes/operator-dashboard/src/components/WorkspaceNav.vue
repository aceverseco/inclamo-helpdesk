<script setup lang="ts">
import {
  Inbox,
  UserRound,
  UsersRound,
  Sparkles,
  ChevronDown,
  ChevronsUpDown,
  Mail,
  MessageCircle,
  Instagram,
  CircleHelp,
  ArrowUpRight,
  Check,
  X,
  BookOpen,
} from "lucide-vue-next";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
} from "@/components/ui/dropdown-menu";
import PersonAvatar from "./PersonAvatar.vue";
import IconButton from "./IconButton.vue";
import type { Queue, Conversation } from "@/lib/demo";
import { ref } from "vue";

const props = defineProps<{ queue: Queue; conversations: Conversation[] }>();
const emit = defineEmits<{
  queue: [value: Queue];
  contacts: [];
  knowledge: [];
  help: [];
  close: [];
}>();
const presence = ref("Available");
const queues: { key: Queue; label: string; icon: typeof Inbox }[] = [
  { key: "all", label: "All conversations", icon: Inbox },
  { key: "mine", label: "Assigned to me", icon: UserRound },
  { key: "unassigned", label: "Unassigned", icon: UsersRound },
  { key: "ai", label: "AI handling", icon: Sparkles },
];
const channels: { key: Queue; label: string; icon: typeof Mail }[] = [
  { key: "Email", label: "Email", icon: Mail },
  { key: "Live chat", label: "Live chat", icon: MessageCircle },
  { key: "Instagram", label: "Instagram", icon: Instagram },
];
function count(key: Queue) {
  return props.conversations.filter(
    (c) =>
      c.status === "open" &&
      (key === "all" ||
        (key === "mine" && c.assignee === "You") ||
        (key === "unassigned" && c.assignee === "Unassigned") ||
        (key === "ai" && c.assignee === "Inclamo AI") ||
        c.channel === key),
  ).length;
}
</script>

<template>
  <aside class="workspace-nav" aria-label="Workspace navigation">
    <div class="brand">
      <img src="/inclamo-logo.svg" alt="" /><span
        >inclamo<span class="brand-dot">.</span></span
      ><IconButton
        label="Close navigation"
        class="mobile-nav-close"
        @click="emit('close')"
        ><X
      /></IconButton>
    </div>
    <div class="workspace-switch">
      <div class="store-mark">n<span>°</span></div>
      <div><strong>Northstar</strong><small>Support workspace</small></div>
    </div>
    <div class="nav-heading">WORKSPACE</div>
    <div class="nav-section-title">
      <Inbox /><strong>Inbox</strong><ChevronDown class="trailing" />
    </div>
    <nav class="queue-nav">
      <button
        v-for="item in queues"
        :key="item.key"
        :class="['nav-row', { selected: queue === item.key }]"
        :aria-current="queue === item.key ? 'page' : undefined"
        @click="emit('queue', item.key)"
      >
        <component :is="item.icon" /><span>{{ item.label }}</span
        ><span class="nav-count">{{ count(item.key) }}</span>
      </button>
    </nav>
    <button class="nav-row standalone" @click="emit('contacts')">
      <UsersRound /><span>Customers</span>
    </button>
    <button class="nav-row standalone" @click="emit('knowledge')">
      <BookOpen /><span>Knowledge</span>
    </button>
    <div class="nav-heading channel-heading">
      CHANNELS<span class="channel-count">3</span>
    </div>
    <nav class="channel-nav">
      <button
        v-for="item in channels"
        :key="item.key"
        :class="['nav-row', { selected: queue === item.key }]"
        :aria-current="queue === item.key ? 'page' : undefined"
        @click="emit('queue', item.key)"
      >
        <component :is="item.icon" /><span>{{ item.label }}</span
        ><span class="connected-dot" />
      </button>
    </nav>
    <div class="nav-spacer" />
    <div class="ai-status-card">
      <div class="ai-status-title">
        <span class="ai-orb"><Sparkles /></span
        ><strong>Your AI teammate</strong>
      </div>
      <p>Your team and AI,<br />working better together.</p>
      <Button variant="ghost" size="sm" @click="emit('queue', 'ai')"
        >View AI conversations <ArrowUpRight
      /></Button>
    </div>
    <button class="nav-row help-link" @click="emit('help')">
      <CircleHelp /><span>Help & shortcuts</span><kbd>?</kbd>
    </button>
    <DropdownMenu>
      <DropdownMenuTrigger as-child
        ><button class="account-switch">
          <span class="account-avatar"
            ><PersonAvatar initials="AK" tone="sky" /><i
              :class="{ away: presence !== 'Available' }" /></span
          ><span
            ><strong>Alex Kim</strong><small>{{ presence }}</small></span
          ><ChevronsUpDown /></button
      ></DropdownMenuTrigger>
      <DropdownMenuContent side="top" align="start" class="w-52"
        ><DropdownMenuLabel>Set your status</DropdownMenuLabel
        ><DropdownMenuSeparator /><DropdownMenuItem
          v-for="status in ['Available', 'Away', 'Do not disturb']"
          :key="status"
          @select="presence = status"
          >{{ status
          }}<Check
            v-if="presence === status"
            class="ml-auto size-4" /></DropdownMenuItem
      ></DropdownMenuContent>
    </DropdownMenu>
  </aside>
</template>
