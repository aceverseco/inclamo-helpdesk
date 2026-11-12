<script setup>
import { t } from '../i18n';
defineProps({
  saved: { type: Object, required: true },
  inboxUrl: { type: String, required: true },
});
const draft = defineModel('draft', { type: Object, required: true });
import { Input } from '../ui/input';
import { Button } from '../ui/button';
const nativeSections = [
  ['business-hours', 'Working hours and away message'],
  ['pre-chat-form', 'Pre-chat form'],
  ['csat', 'Customer satisfaction survey'],
  ['bot-configuration', 'Bot configuration'],
  ['configuration', 'Domains and identity verification'],
  ['', 'Files, emoji and email continuity'],
];
</script>

<template>
  <section class="widget-form-stack">
    <label class="widget-field">
      {{ t('WEBSITE_WIDGET.WIDGET_LANGUAGE') }}
      <select v-model="draft.settings.language_mode">
        <option value="fixed">{{ t('WEBSITE_WIDGET.ONE_LANGUAGE') }}</option>
        <option value="browser">
          {{ t('WEBSITE_WIDGET.MATCH_VISITOR_S_BROWSER') }}
        </option>
      </select>
    </label>
    <label v-if="draft.settings.language_mode === 'fixed'" class="widget-field">
      {{ t('WEBSITE_WIDGET.LANGUAGE') }}
      <select v-model="draft.settings.locale">
        <option v-for="locale in saved.locales" :key="locale" :value="locale">
          {{ locale }}
        </option>
      </select>
    </label>
    <p>
      {{
        t(
          'WEBSITE_WIDGET.BUTTONS_AND_SYSTEM_MESSAGES_USE_THE_SELECTED_LANGUAGE_YOUR_OWN_TE'
        )
      }}
    </p>
    <label class="widget-field">
      {{ t('WEBSITE_WIDGET.EXPECTED_REPLY_TIME') }}
      <select v-model="draft.native.reply_time">
        <option value="in_a_few_minutes">
          {{ t('WEBSITE_WIDGET.A_FEW_MINUTES') }}
        </option>
        <option value="in_a_few_hours">
          {{ t('WEBSITE_WIDGET.A_FEW_HOURS') }}
        </option>
        <option value="in_a_day">{{ t('WEBSITE_WIDGET.A_DAY') }}</option>
      </select>
    </label>
    <label class="widget-field">
      {{ t('WEBSITE_WIDGET.WHERE_TO_SHOW_THE_WIDGET') }}
      <select v-model="draft.settings.visibility.mode">
        <option value="all">{{ t('WEBSITE_WIDGET.EVERY_PAGE') }}</option>
        <option value="include">
          {{ t('WEBSITE_WIDGET.ONLY_THESE_PATHS') }}
        </option>
        <option value="exclude">
          {{ t('WEBSITE_WIDGET.EVERYWHERE_EXCEPT_THESE_PATHS') }}
        </option>
      </select>
    </label>
    <template v-if="draft.settings.visibility.mode !== 'all'">
      <div
        v-for="(rule, i) in draft.settings.visibility.rules"
        :key="i"
        class="widget-rule"
      >
        <select
          v-model="rule.match"
          :aria-label="t('WEBSITE_WIDGET.PATH_MATCH')"
        >
          <option value="exact">{{ t('WEBSITE_WIDGET.EQUALS') }}</option>
          <option value="prefix">
            {{ t('WEBSITE_WIDGET.STARTS_WITH') }}
          </option>
        </select>
        <Input
          v-model="rule.path"
          :aria-label="t('WEBSITE_WIDGET.PAGE_PATH')"
          :placeholder="t('WEBSITE_WIDGET.CHECKOUT')"
        />
        <Button
          variant="ghost"
          @click="draft.settings.visibility.rules.splice(i, 1)"
        >
          {{ t('WEBSITE_WIDGET.REMOVE') }}
        </Button>
      </div>
      <Button
        variant="outline"
        :disabled="draft.settings.visibility.rules.length >= 20"
        @click="
          draft.settings.visibility.rules.push({ path: '/', match: 'exact' })
        "
      >
        {{ t('WEBSITE_WIDGET.ADD_PATH') }}
      </Button>
    </template>
    <div class="widget-section-heading">
      <div>
        <h3>{{ t('WEBSITE_WIDGET.CHANNEL_SETTINGS') }}</h3>
        <p>
          {{
            t('WEBSITE_WIDGET.OPEN_THE_LINKED_SECTION_AND_SAVE_CHANGES_THERE')
          }}
        </p>
      </div>
    </div>
    <router-link
      v-for="[tab, label] in nativeSections"
      :key="label"
      :to="`${inboxUrl}${tab ? '/' + tab : ''}`"
      class="widget-native-link"
    >
      {{ label }}
      <span aria-hidden="true">{{ t('WEBSITE_WIDGET._TEXT') }}</span>
    </router-link>
  </section>
</template>
