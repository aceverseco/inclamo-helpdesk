<script setup>
import { t } from '../i18n';
defineProps({ saved: { type: Object, required: true } });
const emit = defineEmits(['image', 'remove']);
const draft = defineModel('draft', { type: Object, required: true });
import { Input } from '../ui/input';
import { Button } from '../ui/button';
</script>

<template>
  <section class="widget-form-grid">
    <div class="widget-field">
      <span>{{ t('WEBSITE_WIDGET.LOGO_INSIDE_THE_CHAT') }}</span>
      <img
        v-if="
          draft.avatar_image?.preview ||
          (!draft.remove_avatar && saved.avatar_url)
        "
        :src="draft.avatar_image?.preview || saved.avatar_url"
        alt="Header logo"
        class="widget-image-sample"
      />
      <input
        :aria-label="t('WEBSITE_WIDGET.UPLOAD_HEADER_LOGO')"
        type="file"
        accept=".png,.jpg,.jpeg,.webp"
        @change="emit('image', 'avatar_image', $event)"
      />
      <Button variant="ghost" @click="emit('remove', 'avatar')">
        {{ t('WEBSITE_WIDGET.REMOVE_LOGO') }}
      </Button>
    </div>
    <label class="widget-field">
      {{ t('WEBSITE_WIDGET.BRAND_COLOR') }}
      <Input
        v-model="draft.native.widget_color"
        :placeholder="t('WEBSITE_WIDGET.1F93FF')"
        maxlength="7"
      />
      <input
        v-model="draft.native.widget_color"
        type="color"
        :aria-label="t('WEBSITE_WIDGET.CHOOSE_BRAND_COLOR')"
      />
    </label>
    <label class="widget-field">
      {{ t('WEBSITE_WIDGET.CHAT_ICON') }}
      <select v-model="draft.settings.icon">
        <option value="chat">{{ t('WEBSITE_WIDGET.CHAT') }}</option>
        <option value="message">{{ t('WEBSITE_WIDGET.MESSAGE') }}</option>
        <option value="help">{{ t('WEBSITE_WIDGET.QUESTION_MARK') }}</option>
        <option value="custom">{{ t('WEBSITE_WIDGET.MY_IMAGE') }}</option>
      </select>
    </label>
    <div v-if="draft.settings.icon === 'custom'" class="widget-field">
      <span>{{ t('WEBSITE_WIDGET.CUSTOM_CHAT_ICON') }}</span>
      <img
        v-if="
          draft.icon_image?.preview || (!draft.remove_icon && saved.icon_url)
        "
        :src="draft.icon_image?.preview || saved.icon_url"
        class="widget-image-sample"
        alt="Chat icon"
      />
      <input
        :aria-label="t('WEBSITE_WIDGET.UPLOAD_CHAT_ICON')"
        type="file"
        accept=".png,.jpg,.jpeg,.webp,.svg"
        @change="emit('image', 'icon_image', $event)"
      />
      <small>{{ t('WEBSITE_WIDGET.PNG_JPEG_WEBP_OR_SVG_UP_TO_1_MB') }}</small>
      <Button variant="ghost" @click="emit('remove', 'icon')">
        {{ t('WEBSITE_WIDGET.USE_DEFAULT_ICON') }}
      </Button>
    </div>
    <label class="widget-field">
      {{ t('WEBSITE_WIDGET.BUTTON_STYLE') }}
      <select v-model="draft.settings.type">
        <option value="standard">{{ t('WEBSITE_WIDGET.ICON_ONLY') }}</option>
        <option value="expanded_bubble">
          {{ t('WEBSITE_WIDGET.ICON_AND_LABEL') }}
        </option>
      </select>
    </label>
    <label
      v-if="draft.settings.type === 'expanded_bubble'"
      class="widget-field"
    >
      {{ t('WEBSITE_WIDGET.BUTTON_LABEL') }}
      <Input
        v-model="draft.settings.launcher_title"
        maxlength="60"
        :placeholder="t('WEBSITE_WIDGET.CHAT_WITH_US')"
      />
    </label>
    <label class="widget-field">
      {{ t('WEBSITE_WIDGET.POSITION') }}
      <select v-model="draft.settings.position">
        <option value="right">{{ t('WEBSITE_WIDGET.RIGHT') }}</option>
        <option value="left">{{ t('WEBSITE_WIDGET.LEFT') }}</option>
      </select>
    </label>
    <label class="widget-field">
      {{ t('WEBSITE_WIDGET.APPEARANCE') }}
      <select v-model="draft.settings.theme">
        <option value="light">{{ t('WEBSITE_WIDGET.LIGHT') }}</option>
        <option value="dark">{{ t('WEBSITE_WIDGET.DARK') }}</option>
        <option value="auto">
          {{ t('WEBSITE_WIDGET.MATCH_VISITOR_S_DEVICE') }}
        </option>
      </select>
    </label>
    <label class="widget-field">
      {{ t('WEBSITE_WIDGET.SIDE_OFFSET_PX') }}
      <input
        v-model.number="draft.settings.offset_x"
        type="number"
        min="0"
        max="160"
      />
    </label>
    <label class="widget-field">
      {{ t('WEBSITE_WIDGET.BOTTOM_OFFSET_PX') }}
      <input
        v-model.number="draft.settings.offset_y"
        type="number"
        min="0"
        max="160"
      />
    </label>
  </section>
</template>
