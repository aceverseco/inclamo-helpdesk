import { onMounted, onBeforeUnmount } from 'vue';

export function useApplicationTheme() {
  onMounted(() => document.body.classList.add('inclamo-app-theme'));
  onBeforeUnmount(() => document.body.classList.remove('inclamo-app-theme'));
}
