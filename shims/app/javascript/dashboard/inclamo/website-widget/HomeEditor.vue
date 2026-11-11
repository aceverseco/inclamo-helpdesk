<script setup>
import { t } from '../i18n';
const props = defineProps({ saved: { type: Object, required: true } });
const draft = defineModel('draft', { type: Object, required: true });
import { computed } from 'vue';
import { Input } from '../ui/input';
import { Button } from '../ui/button';
const articles = computed(() =>
  props.saved.articles.filter(
    a => a.portal_id === Number(draft.value.native.portal_id)
  )
);
function add(kind) {
  draft.value.settings[kind].push({
    id: crypto.randomUUID(),
    label: '',
    enabled: true,
    ...(kind === 'starters'
      ? { message: '' }
      : { kind: 'url', url: '', article_id: null }),
  });
}
function move(list, i, direction) {
  const j = i + direction;
  if (j < 0 || j >= list.length) return;
  [list[i], list[j]] = [list[j], list[i]];
}
</script>

<template>
  <section class="widget-form-stack">
    <label class="widget-field">
      {{ t('WEBSITE_WIDGET.CHAT_NAME') }}
      <Input v-model="draft.native.name" />
    </label>
    <label class="widget-field">
      {{ t('WEBSITE_WIDGET.WELCOME_HEADING') }}
      <Input v-model="draft.native.welcome_title" maxlength="120" />
    </label>
    <label class="widget-field">
      {{ t('WEBSITE_WIDGET.WELCOME_MESSAGE') }}
      <textarea
        v-model="draft.native.welcome_tagline"
        maxlength="255"
        rows="3"
      />
    </label>
    <label class="widget-field">
      {{ t('WEBSITE_WIDGET.HELP_CENTER') }}
      <select v-model="draft.native.portal_id">
        <option :value="null">{{ t('WEBSITE_WIDGET.NONE') }}</option>
        <option
          v-for="portal in saved.portals"
          :key="portal.id"
          :value="portal.id"
        >
          {{ portal.name }}
        </option>
      </select>
    </label>
    <div class="widget-section-heading">
      <div>
        <h3>{{ t('WEBSITE_WIDGET.SUGGESTED_INTENTS') }}</h3>
        <p>
          {{
            t(
              'WEBSITE_WIDGET.HELP_VISITORS_START_A_CONVERSATION_WITH_A_QUESTION'
            )
          }}
        </p>
      </div>
      <Button
        variant="outline"
        :disabled="draft.settings.starters.filter(e => e.enabled).length >= 6"
        @click="add('starters')"
      >
        {{ t('WEBSITE_WIDGET.ADD_BUTTON') }}
      </Button>
    </div>
    <p v-if="!draft.settings.starters.length" class="widget-empty">
      {{
        t(
          'WEBSITE_WIDGET.NO_STARTER_BUTTONS_YET_VISITORS_CAN_STILL_WRITE_THEIR_OWN_MESSAGE'
        )
      }}
    </p>
    <article
      v-for="(entry, i) in draft.settings.starters"
      :key="entry.id"
      class="widget-entry"
    >
      <label class="widget-field">
        {{ t('WEBSITE_WIDGET.BUTTON_LABEL') }}
        <Input
          v-model="entry.label"
          maxlength="60"
          :placeholder="t('WEBSITE_WIDGET.WHERE_IS_MY_ORDER')"
        />
      </label>
      <label class="widget-field">
        {{ t('WEBSITE_WIDGET.MESSAGE_TO_SEND') }}
        <textarea
          v-model="entry.message"
          maxlength="500"
          rows="2"
          :placeholder="
            t('WEBSITE_WIDGET.I_D_LIKE_TO_CHECK_THE_STATUS_OF_MY_ORDER')
          "
        />
      </label>
      <div class="widget-entry-actions">
        <label>
          <input v-model="entry.enabled" type="checkbox" />
          {{ t('WEBSITE_WIDGET.ENABLED') }}
        </label>
        <Button
          variant="ghost"
          :disabled="i === 0"
          :aria-label="t('WEBSITE_WIDGET.MOVE_INTENT_UP')"
          @click="move(draft.settings.starters, i, -1)"
        >
          {{ t('WEBSITE_WIDGET.') }}
        </Button>
        <Button
          variant="ghost"
          :disabled="i === draft.settings.starters.length - 1"
          :aria-label="t('WEBSITE_WIDGET.MOVE_INTENT_DOWN')"
          @click="move(draft.settings.starters, i, 1)"
        >
          {{ t('WEBSITE_WIDGET._TEXT') }}
        </Button>
        <Button variant="ghost" @click="draft.settings.starters.splice(i, 1)">
          {{ t('WEBSITE_WIDGET.REMOVE') }}
        </Button>
      </div>
    </article>
    <div class="widget-section-heading">
      <div>
        <h3>{{ t('WEBSITE_WIDGET.QUICK_HELP_LINKS') }}</h3>
        <p>
          {{
            t(
              'WEBSITE_WIDGET.OPEN_AN_ARTICLE_OR_PAGE_WITHOUT_STARTING_A_CONVERSATION'
            )
          }}
        </p>
      </div>
      <Button
        variant="outline"
        :disabled="draft.settings.links.filter(e => e.enabled).length >= 6"
        @click="add('links')"
      >
        {{ t('WEBSITE_WIDGET.ADD_LINK') }}
      </Button>
    </div>
    <article
      v-for="(entry, i) in draft.settings.links"
      :key="entry.id"
      class="widget-entry"
    >
      <label class="widget-field">
        {{ t('WEBSITE_WIDGET.LINK_LABEL') }}
        <Input v-model="entry.label" maxlength="60" />
      </label>
      <label class="widget-field">
        {{ t('WEBSITE_WIDGET.DESTINATION') }}
        <select v-model="entry.kind">
          <option value="url">{{ t('WEBSITE_WIDGET.WEBSITE_PAGE') }}</option>
          <option value="article">
            {{ t('WEBSITE_WIDGET.HELP_CENTER_ARTICLE') }}
          </option>
        </select>
      </label>
      <label v-if="entry.kind === 'url'" class="widget-field">
        {{ t('WEBSITE_WIDGET.HTTPS_ADDRESS') }}
        <Input
          v-model="entry.url"
          type="url"
          :placeholder="t('WEBSITE_WIDGET.HTTPS_YOUR_STORE_COM_RETURNS')"
        />
      </label>
      <label v-else class="widget-field">
        {{ t('WEBSITE_WIDGET.PUBLISHED_ARTICLE') }}
        <select v-model="entry.article_id">
          <option :value="null">
            {{ t('WEBSITE_WIDGET.CHOOSE_AN_ARTICLE') }}
          </option>
          <option
            v-for="article in articles"
            :key="article.id"
            :value="article.id"
          >
            {{ article.title }}
          </option>
        </select>
      </label>
      <div class="widget-entry-actions">
        <label>
          <input v-model="entry.enabled" type="checkbox" />
          {{ t('WEBSITE_WIDGET.ENABLED') }}
        </label>
        <Button
          variant="ghost"
          :disabled="i === 0"
          :aria-label="t('WEBSITE_WIDGET.MOVE_LINK_UP')"
          @click="move(draft.settings.links, i, -1)"
        >
          {{ t('WEBSITE_WIDGET.') }}
        </Button>
        <Button
          variant="ghost"
          :disabled="i === draft.settings.links.length - 1"
          :aria-label="t('WEBSITE_WIDGET.MOVE_LINK_DOWN')"
          @click="move(draft.settings.links, i, 1)"
        >
          {{ t('WEBSITE_WIDGET._TEXT') }}
        </Button>
        <Button variant="ghost" @click="draft.settings.links.splice(i, 1)">
          {{ t('WEBSITE_WIDGET.REMOVE') }}
        </Button>
      </div>
    </article>
    <small>
      {{
        t(
          'WEBSITE_WIDGET.UP_TO_SIX_ENABLED_BUTTONS_AND_SIX_LINKS_TEXT_APPEARS_IN_THE_LANGU'
        )
      }}
    </small>
  </section>
</template>
