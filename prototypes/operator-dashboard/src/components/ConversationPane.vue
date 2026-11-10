<script setup lang="ts">
import { computed, nextTick, onMounted, ref, watch } from "vue";
import {
  ArrowLeft,
  Check,
  CheckCheck,
  ChevronDown,
  Clock3,
  Flag,
  Mail,
  MessageCircle,
  Instagram,
  MoreHorizontal,
  PanelRight,
  Paperclip,
  Send,
  Smile,
  Sparkles,
  Zap,
  X,
  Undo2,
} from "lucide-vue-next";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
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
import type { Conversation, Message, Status } from "@/lib/demo";

const props = defineProps<{
  conversation: Conversation;
  showCustomer: boolean;
}>();
const emit = defineEmits<{
  send: [kind: Message["kind"], text: string];
  draft: [kind: "reply" | "note", value: string];
  suggest: [];
  status: [value: Status];
  priority: [];
  assign: [value: string];
  customer: [];
  back: [];
  copy: [];
}>();
const mode = ref<"reply" | "note">("reply");
const attachment = ref("");
const fileInput = ref<HTMLInputElement>();
const messages = ref<HTMLElement>();
const icons = { Email: Mail, "Live chat": MessageCircle, Instagram };
const draft = computed({
  get: () =>
    mode.value === "reply"
      ? props.conversation.draft
      : props.conversation.noteDraft,
  set: (value) => emit("draft", mode.value, value),
});
const canSend = computed(() => Boolean(draft.value.trim() || attachment.value));
function send() {
  if (!canSend.value) return;
  const text = [
    draft.value.trim(),
    attachment.value ? `Attachment: ${attachment.value} (preview only)` : "",
  ]
    .filter(Boolean)
    .join("\n");
  emit("send", mode.value === "note" ? "note" : "agent", text);
  attachment.value = "";
}
function attach(event: Event) {
  const input = event.target as HTMLInputElement;
  attachment.value = input.files?.[0]?.name || "";
  input.value = "";
}
function suggestion() {
  mode.value = "reply";
  emit("suggest");
}
watch(
  () => props.conversation.id,
  () => {
    attachment.value = "";
    mode.value = "reply";
  },
);
async function scrollToLatest() {
  await nextTick();
  messages.value?.scrollTo({ top: messages.value.scrollHeight });
}
watch(
  () => [props.conversation.id, props.conversation.messages.length],
  scrollToLatest,
);
onMounted(scrollToLatest);
</script>

<template>
  <section class="conversation-pane" aria-label="Selected conversation">
    <header class="conversation-header">
      <IconButton
        label="Back to inbox"
        class="mobile-back"
        @click="emit('back')"
        ><ArrowLeft
      /></IconButton>
      <PersonAvatar
        :initials="conversation.initials"
        :tone="conversation.tone"
      />
      <div class="conversation-identity">
        <h2>{{ conversation.name }}</h2>
        <p>
          <component :is="icons[conversation.channel]" />{{
            conversation.email
          }}
        </p>
      </div>
      <div class="conversation-actions">
        <DropdownMenu
          ><DropdownMenuTrigger as-child
            ><Button
              variant="ghost"
              size="icon"
              class="icon-button"
              aria-label="Snooze conversation"
              ><Clock3 /></Button></DropdownMenuTrigger
          ><DropdownMenuContent align="end"
            ><DropdownMenuLabel>Snooze conversation</DropdownMenuLabel
            ><DropdownMenuItem @select="emit('status', 'snoozed')"
              >For one hour</DropdownMenuItem
            ><DropdownMenuItem @select="emit('status', 'snoozed')"
              >Until tomorrow</DropdownMenuItem
            ></DropdownMenuContent
          ></DropdownMenu
        >
        <DropdownMenu
          ><DropdownMenuTrigger as-child
            ><Button
              variant="ghost"
              size="icon"
              class="icon-button"
              aria-label="More conversation actions"
              ><MoreHorizontal /></Button></DropdownMenuTrigger
          ><DropdownMenuContent align="end"
            ><DropdownMenuItem @select="emit('priority')"
              ><Flag class="mr-2 size-4" />{{
                conversation.priority ? "Remove priority" : "Mark as priority"
              }}</DropdownMenuItem
            ><DropdownMenuItem @select="emit('copy')"
              >Copy conversation reference</DropdownMenuItem
            ></DropdownMenuContent
          ></DropdownMenu
        >
        <Button
          v-if="conversation.status === 'open'"
          size="sm"
          class="resolve-button"
          @click="emit('status', 'done')"
          ><Check /><span>Resolve</span></Button
        >
        <Button
          v-else
          size="sm"
          variant="outline"
          class="resolve-button"
          @click="emit('status', 'open')"
          ><Undo2 /><span>Reopen</span></Button
        >
        <IconButton
          label="Toggle customer details"
          :active="showCustomer"
          @click="emit('customer')"
          ><PanelRight
        /></IconButton>
      </div>
    </header>
    <div class="conversation-toolbar">
      <span class="conversation-reference">#{{ conversation.id }}</span
      ><span class="toolbar-divider" /><span
        :class="['status-label', conversation.status]"
        ><i />{{
          conversation.status === "open"
            ? "Open"
            : conversation.status === "done"
              ? "Resolved"
              : "Snoozed"
        }}</span
      ><button
        :class="['priority-control', { flagged: conversation.priority }]"
        :aria-label="
          conversation.priority ? 'Remove priority' : 'Mark as priority'
        "
        @click="emit('priority')"
      >
        <Flag /><span>{{
          conversation.priority ? "Priority" : "Set priority"
        }}</span></button
      ><DropdownMenu
        ><DropdownMenuTrigger as-child
          ><button class="assignee">
            <span class="assignee-avatar">{{
              conversation.assignee === "You"
                ? "AK"
                : conversation.assignee === "Mia"
                  ? "ML"
                  : conversation.assignee === "Inclamo AI"
                    ? "AI"
                    : "—"
            }}</span
            >{{ conversation.assignee
            }}<ChevronDown /></button></DropdownMenuTrigger
        ><DropdownMenuContent align="end"
          ><DropdownMenuLabel>Assign conversation</DropdownMenuLabel
          ><DropdownMenuItem
            v-for="person in ['You', 'Mia', 'Inclamo AI', 'Unassigned']"
            :key="person"
            @select="emit('assign', person)"
            >{{ person
            }}<Check
              v-if="conversation.assignee === person"
              class="ml-auto size-4" /></DropdownMenuItem></DropdownMenuContent
      ></DropdownMenu>
    </div>
    <div
      ref="messages"
      class="message-feed"
      role="log"
      aria-label="Conversation messages"
      aria-live="polite"
    >
      <div class="conversation-subject">
        <span>{{ conversation.channel }} conversation</span>
        <h3>{{ conversation.subject }}</h3>
      </div>
      <div class="date-separator"><span>Today, November 10</span></div>
      <article
        v-for="message in conversation.messages"
        :key="message.id"
        :class="['message', message.kind]"
      >
        <PersonAvatar
          v-if="message.kind !== 'note'"
          :initials="
            message.kind === 'customer'
              ? conversation.initials
              : message.author === 'Inclamo AI'
                ? 'AI'
                : 'AK'
          "
          :tone="message.kind === 'customer' ? conversation.tone : 'sky'"
        />
        <div class="message-content">
          <div class="message-meta">
            <strong>{{
              message.kind === "customer"
                ? conversation.name
                : message.kind === "note"
                  ? "Private note · Alex"
                  : message.author || "Alex Kim"
            }}</strong
            ><time>{{ message.time }}</time>
          </div>
          <div class="message-body">{{ message.text }}</div>
          <div v-if="message.kind === 'agent'" class="message-delivery">
            <CheckCheck />{{
              message.author === "Inclamo AI" ? "Sent by Inclamo AI" : "Sent"
            }}
          </div>
        </div>
      </article>
    </div>
    <div class="composer-area">
      <button
        v-if="conversation.id === 1048 && !conversation.draft"
        class="suggestion-nudge"
        @click="suggestion"
      >
        <span class="nudge-icon"><Sparkles /></span
        ><span
          ><strong>A little context, before you reply</strong
          ><small>Returning customer · Order hasn’t shipped yet</small></span
        ><span class="nudge-action">Draft reply <span>↗</span></span>
      </button>
      <div :class="['composer', { 'note-composer': mode === 'note' }]">
        <div class="composer-header">
          <Tabs v-model="mode"
            ><TabsList class="composer-tabs"
              ><TabsTrigger value="reply">Reply <ChevronDown /></TabsTrigger
              ><TabsTrigger value="note">Private note</TabsTrigger></TabsList
            ></Tabs
          ><span class="composer-recipient">{{
            mode === "reply"
              ? `to ${conversation.name.split(" ")[0]}`
              : "Only visible to your team"
          }}</span
          ><Button
            variant="ghost"
            size="sm"
            class="ai-draft-button"
            @click="suggestion"
            ><Sparkles /><span>AI draft</span></Button
          >
        </div>
        <Textarea
          :model-value="draft"
          :aria-label="
            mode === 'reply' ? 'Write a reply' : 'Write a private note'
          "
          :placeholder="
            mode === 'reply'
              ? 'Write a thoughtful reply…'
              : 'Leave a note for your team…'
          "
          @update:model-value="draft = String($event)"
          @keydown.meta.enter.prevent="send"
          @keydown.ctrl.enter.prevent="send"
        />
        <div v-if="attachment" class="attachment-chip">
          <Paperclip />{{ attachment
          }}<button aria-label="Remove attachment" @click="attachment = ''">
            <X />
          </button>
        </div>
        <div class="composer-footer">
          <div class="composer-tools">
            <IconButton
              label="Attach a file (local preview)"
              @click="fileInput?.click()"
              ><Paperclip /></IconButton
            ><input
              ref="fileInput"
              type="file"
              class="sr-only"
              tabindex="-1"
              aria-label="Choose attachment"
              @change="attach"
            /><IconButton label="Add a smile" @click="draft += ' 🙂'"
              ><Smile /></IconButton
            ><DropdownMenu
              ><DropdownMenuTrigger as-child
                ><Button
                  variant="ghost"
                  size="icon"
                  class="icon-button"
                  aria-label="Saved replies"
                  ><Zap /></Button></DropdownMenuTrigger
              ><DropdownMenuContent align="start" side="top"
                ><DropdownMenuLabel>Saved replies</DropdownMenuLabel
                ><DropdownMenuItem
                  @select="
                    draft = `Hi ${conversation.name.split(' ')[0]}, thanks for reaching out! How can I help you today?`
                  "
                  >Friendly greeting</DropdownMenuItem
                ><DropdownMenuItem
                  @select="
                    draft =
                      'Thanks for your patience. I’m checking this with our team and will get back to you shortly.'
                  "
                  >Checking with the team</DropdownMenuItem
                ><DropdownMenuItem
                  @select="
                    draft =
                      'You’re very welcome! If there’s anything else you need, we’re always happy to help.'
                  "
                  >Happy to help</DropdownMenuItem
                ></DropdownMenuContent
              ></DropdownMenu
            >
          </div>
          <span class="send-shortcut">⌘ ↵</span
          ><Button size="sm" :disabled="!canSend" @click="send"
            >{{ mode === "note" ? "Add note" : "Send reply" }}<Send
          /></Button>
        </div>
      </div>
      <div class="composer-caption">
        <span class="secure-dot" />{{
          mode === "note"
            ? "Private notes stay with your team"
            : `Replying via ${conversation.channel.toLowerCase()}`
        }}<span>Made personal. Powered by Inclamo.</span>
      </div>
    </div>
  </section>
</template>
