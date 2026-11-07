<script setup>
// The tags and the note of an order or of a customer, as the store holds them,
// and, for a member allowed to change them, the controls to do so. A change is
// sent at once, without a confirmation: tags and notes cost no money and the
// opposite click undoes them. The store's refusal is shown and the old value
// stays.
import { ref, reactive, computed, watch } from 'vue';
import InclamoAPI from '../api';
import { t, has } from '../i18n';
import { newActionId } from '../format';

const props = defineProps({
  // 'order' or 'customer': names the action and the test ids, e.g. inclamo-order-tags.
  subject: { type: String, required: true },
  // The store's id of the order or of the customer.
  subjectId: { type: String, default: null },
  conversationId: { type: [Number, String], default: null },
  tags: { type: Array, default: () => [] },
  note: { type: String, default: null },
  // The panel's `can` decision for this subject: the role and the app's scope.
  editable: { type: Boolean, default: false },
  connection: { type: Object, default: null },
});

const current = reactive({ tags: [...props.tags], note: props.note });
const busy = ref(false);
const reading = ref(false);
const message = ref('');
const newTag = ref('');
const editing = ref(false);
const draft = ref('');

// A fresh panel read replaces what is shown; an equal one changes nothing.
watch(
  () => JSON.stringify([props.tags, props.note]),
  () => {
    current.tags = [...props.tags];
    current.note = props.note;
  }
);

const scopeEntry = computed(() => (props.connection?.actions || []).find(entry => entry.name === `${props.subject}_tags`));
const missingScopes = computed(() => (scopeEntry.value?.missing_scopes || []).join(', '));
// The line naming the permission the merchant's app lacks, when that is why nothing can be changed.
const lacks = computed(() => (scopeEntry.value && !scopeEntry.value.available && scopeEntry.value.reason === 'missing_scope' ? missingScopes.value : ''));

const target = () => (props.subject === 'customer' ? { customer_id: props.subjectId } : { order_id: props.subjectId });

const explain = record => {
  if (record.outcome === 'unknown' || record.outcome === 'running') return t('MARKS.UNKNOWN');
  if (record.refusal === 'not_allowed') return t('DIALOG.NOT_ALLOWED');
  if (record.refusal === 'store_refused' && record.store_message) return t('DIALOG.FAILED', { message: record.store_message });
  if (has(`MARKS.WHY_NOT.${record.refusal}`)) return t(`MARKS.WHY_NOT.${record.refusal}`, { scopes: missingScopes.value });
  return t('DIALOG.FAILED_PLAIN');
};

const show = marks => {
  current.tags = marks.tags || [];
  current.note = marks.note || null;
};

// Sends one change; true when the store accepted it.
const send = async payload => {
  busy.value = true;
  message.value = '';
  try {
    const { data } = await InclamoAPI.performAction(props.conversationId, { ...payload, ...target(), action_id: newActionId() });
    if (data.outcome === 'accepted') return true;
    message.value = explain(data);
    return false;
  } catch (error) {
    // No answer: the change may or may not have been made.
    message.value = t('MARKS.UNKNOWN');
    return false;
  } finally {
    busy.value = false;
  }
};

// After a change, shows what the store holds now, with what others changed
// meanwhile; when that cannot be read, shows the change alone.
const refresh = async fallback => {
  try {
    show((await InclamoAPI.marks(props.conversationId, target())).data);
  } catch (error) {
    fallback();
  }
};

const addTag = async () => {
  const tag = newTag.value.trim();
  if (!tag || busy.value) return;
  if (!(await send({ action_name: `${props.subject}_tags`, params: { operation: 'add', tag } }))) return;
  newTag.value = '';
  await refresh(() => {
    if (!current.tags.some(existing => existing.toLowerCase() === tag.toLowerCase())) current.tags.push(tag);
  });
};

const removeTag = async tag => {
  if (busy.value) return;
  if (!(await send({ action_name: `${props.subject}_tags`, params: { operation: 'remove', tag } }))) return;
  await refresh(() => {
    current.tags = current.tags.filter(existing => existing !== tag);
  });
};

// The editor starts from the note as the store holds it now, not from the panel's copy.
const startEditing = async () => {
  reading.value = true;
  message.value = '';
  try {
    show((await InclamoAPI.marks(props.conversationId, target())).data);
    draft.value = current.note || '';
    editing.value = true;
  } catch (error) {
    message.value = t('MARKS.READ_FAILED');
  } finally {
    reading.value = false;
  }
};

const saveNote = async () => {
  if (busy.value) return;
  const note = draft.value;
  if (!(await send({ action_name: `${props.subject}_note`, note }))) return;
  editing.value = false;
  await refresh(() => {
    current.note = note.trim() ? note : null;
  });
};

const stopEditing = () => {
  editing.value = false;
  message.value = '';
};
</script>

<template>
  <section class="flex flex-col gap-2" :data-testid="`inclamo-${subject}-marks`">
    <div class="flex flex-col gap-1">
      <h4 class="text-xs uppercase text-n-slate-10">{{ t('MARKS.TAGS') }}</h4>
      <ul v-if="current.tags.length" class="flex flex-wrap gap-1" :data-testid="`inclamo-${subject}-tags`">
        <li v-for="tag in current.tags" :key="tag" class="inline-flex items-center gap-1 rounded-md bg-n-alpha-2 px-1.5 py-0.5 text-xs text-n-slate-12">
          <span :data-testid="`inclamo-${subject}-tag`">{{ tag }}</span>
          <button
            v-if="editable"
            type="button"
            class="text-n-slate-11 hover:text-n-ruby-11 disabled:opacity-50"
            :aria-label="t('MARKS.REMOVE_TAG', { tag })"
            :title="t('MARKS.REMOVE_TAG', { tag })"
            :disabled="busy"
            :data-testid="`inclamo-${subject}-tag-remove`"
            @click="removeTag(tag)"
          >
            ×
          </button>
        </li>
      </ul>
      <p v-else class="text-xs text-n-slate-11" :data-testid="`inclamo-${subject}-no-tags`">{{ t('MARKS.NO_TAGS') }}</p>
      <form v-if="editable" class="flex gap-1" :data-testid="`inclamo-${subject}-tag-form`" @submit.prevent="addTag">
        <input
          v-model="newTag"
          type="text"
          class="min-w-0 flex-1 rounded-md border border-n-weak bg-n-alpha-black2 px-2 py-1 text-xs"
          :placeholder="t('MARKS.TAG_PLACEHOLDER')"
          :aria-label="t('MARKS.TAG_PLACEHOLDER')"
          :data-testid="`inclamo-${subject}-tag-input`"
        />
        <button type="submit" class="rounded-md border border-n-weak px-2 py-1 text-xs disabled:opacity-50" :disabled="busy || !newTag.trim()" :data-testid="`inclamo-${subject}-tag-add`">
          {{ t('MARKS.ADD_TAG') }}
        </button>
      </form>
    </div>
    <div class="flex flex-col gap-1">
      <div class="flex items-center justify-between gap-2">
        <h4 class="text-xs uppercase text-n-slate-10">{{ t('MARKS.NOTE') }}</h4>
        <button v-if="editable && !editing" type="button" class="text-xs text-n-blue-text disabled:opacity-50" :disabled="reading || busy" :data-testid="`inclamo-${subject}-note-edit`" @click="startEditing">
          {{ t('MARKS.EDIT_NOTE') }}
        </button>
      </div>
      <template v-if="editing">
        <textarea
          v-model="draft"
          rows="3"
          class="rounded-md border border-n-weak bg-n-alpha-black2 px-2 py-1 text-sm"
          :aria-label="t('MARKS.NOTE')"
          :data-testid="`inclamo-${subject}-note-input`"
        />
        <div class="flex gap-3 text-xs">
          <button type="button" class="text-n-blue-text disabled:opacity-50" :disabled="busy" :data-testid="`inclamo-${subject}-note-save`" @click="saveNote">{{ t('MARKS.SAVE_NOTE') }}</button>
          <button type="button" class="text-n-slate-11" :disabled="busy" :data-testid="`inclamo-${subject}-note-cancel`" @click="stopEditing">{{ t('DIALOG.BACK') }}</button>
        </div>
      </template>
      <template v-else>
        <p v-if="current.note" class="whitespace-pre-line break-words" :data-testid="`inclamo-${subject}-note`">{{ current.note }}</p>
        <p v-else class="text-xs text-n-slate-11" :data-testid="`inclamo-${subject}-no-note`">{{ t('MARKS.NO_NOTE') }}</p>
      </template>
    </div>
    <p v-if="message" class="rounded-md bg-n-ruby-3 p-2 text-xs text-n-ruby-11" :data-testid="`inclamo-${subject}-marks-message`">{{ message }}</p>
    <p v-if="!editable && lacks" class="text-xs text-n-slate-11" :data-testid="`inclamo-${subject}-marks-lacks`">{{ t('MARKS.LACKS', { scopes: lacks }) }}</p>
  </section>
</template>
