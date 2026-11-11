import { onMounted, onUnmounted } from 'vue';

// Account workspace owns the scope, including dialogs teleported to body.
export const useDashboardTheme = () => {
  onMounted(() => document.body.classList.add('inclamo-dashboard-theme'));
  onUnmounted(() => document.body.classList.remove('inclamo-dashboard-theme'));
};
