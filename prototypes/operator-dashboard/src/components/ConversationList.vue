<script setup lang="ts">
import {
  Search,
  SlidersHorizontal,
  ArrowDownWideNarrow,
  Mail,
  MessageCircle,
  Instagram,
  Flag,
  SearchX,
  X,
} from "lucide-vue-next";
import { Input } from "@/components/ui/input";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuCheckboxItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
} from "@/components/ui/dropdown-menu";
import PersonAvatar from "./PersonAvatar.vue";
import type { Conversation, Status } from "@/lib/demo";

defineProps<{
  conversations: Conversation[];
  selectedId: number;
  search: string;
  status: Status;
  unreadOnly: boolean;
  priorityOnly: boolean;
  oldestFirst: boolean;
  counts: Record<Status, number>;
}>();
const emit = defineEmits<{
  select: [value: number];
  search: [value: string];
  status: [value: Status];
  unread: [value: boolean];
  priority: [value: boolean];
  sort: [];
  clear: [];
}>();
const icons = { Email: Mail, "Live chat": MessageCircle, Instagram };
</script>

<template>
  <section class="conversation-list" aria-label="Conversations">
    <div class="list-heading">
      <h1>
        Inbox <span>{{ counts.open }}</span>
      </h1>
      <DropdownMenu
        ><DropdownMenuTrigger as-child
          ><Button
            variant="ghost"
            size="icon"
            :class="['icon-button', { active: unreadOnly || priorityOnly }]"
            aria-label="Filter conversations"
            ><SlidersHorizontal /></Button></DropdownMenuTrigger
        ><DropdownMenuContent align="end"
          ><DropdownMenuLabel>Show conversations</DropdownMenuLabel
          ><DropdownMenuSeparator /><DropdownMenuCheckboxItem
            :model-value="unreadOnly"
            @update:model-value="emit('unread', $event)"
            >Unread only</DropdownMenuCheckboxItem
          ><DropdownMenuCheckboxItem
            :model-value="priorityOnly"
            @update:model-value="emit('priority', $event)"
            >Priority only</DropdownMenuCheckboxItem
          ></DropdownMenuContent
        ></DropdownMenu
      >
    </div>
    <div class="inbox-search">
      <Search /><Input
        :model-value="search"
        aria-label="Search conversations"
        placeholder="Search conversations…"
        @update:model-value="emit('search', String($event))"
      /><button
        v-if="search"
        aria-label="Clear search"
        @click="emit('search', '')"
      >
        <X /></button
      ><kbd v-else>/</kbd>
    </div>
    <Tabs
      :model-value="status"
      class="inbox-tabs"
      @update:model-value="emit('status', $event as Status)"
      ><TabsList
        ><TabsTrigger value="open"
          >Open <span>{{ counts.open }}</span></TabsTrigger
        ><TabsTrigger value="snoozed">Snoozed</TabsTrigger
        ><TabsTrigger value="done">Done</TabsTrigger></TabsList
      ></Tabs
    >
    <div class="list-sort">
      <span>{{
        unreadOnly ? "Unread" : priorityOnly ? "Priority" : "All conversations"
      }}</span
      ><DropdownMenu
        ><DropdownMenuTrigger as-child
          ><button
            :aria-label="
              oldestFirst ? 'Sort: oldest first' : 'Sort: newest first'
            "
          >
            {{ oldestFirst ? "Oldest" : "Newest"
            }}<ArrowDownWideNarrow /></button></DropdownMenuTrigger
        ><DropdownMenuContent align="end"
          ><DropdownMenuItem @select="!oldestFirst && emit('sort')"
            >Oldest first</DropdownMenuItem
          ><DropdownMenuItem @select="oldestFirst && emit('sort')"
            >Newest first</DropdownMenuItem
          ></DropdownMenuContent
        ></DropdownMenu
      >
    </div>
    <div class="conversation-rows">
      <button
        v-for="conversation in conversations"
        :key="conversation.id"
        :class="[
          'conversation-row',
          {
            selected: conversation.id === selectedId,
            unread: conversation.unread,
          },
        ]"
        :aria-label="`${conversation.name}: ${conversation.subject}`"
        :aria-pressed="conversation.id === selectedId"
        @click="emit('select', conversation.id)"
      >
        <div class="row-avatar">
          <PersonAvatar
            :initials="conversation.initials"
            :tone="conversation.tone"
          /><span class="channel-bubble"
            ><component :is="icons[conversation.channel]"
          /></span>
        </div>
        <div class="row-content">
          <div class="row-first">
            <strong>{{ conversation.name }}</strong
            ><time>{{ conversation.time }}</time>
          </div>
          <div class="row-subject">{{ conversation.subject }}</div>
          <p>{{ conversation.preview }}</p>
          <div class="row-bottom">
            <span
              :class="[
                'conversation-tag',
                { 'ai-tag': conversation.assignee === 'Inclamo AI' },
              ]"
              >{{ conversation.tag }}</span
            ><Flag v-if="conversation.priority" class="priority-flag" /><i
              v-if="conversation.unread"
              class="unread-dot"
            />
          </div>
        </div>
      </button>
      <div v-if="!conversations.length" class="empty-list">
        <SearchX /><strong>No conversations here</strong>
        <p>Try another search or filter.</p>
        <Button variant="outline" size="sm" @click="emit('clear')"
          >Reset filters</Button
        >
      </div>
    </div>
    <div class="list-footer">
      <span class="connected-dot" /> All caught up with your channels
    </div>
  </section>
</template>
