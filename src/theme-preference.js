export const readThemePreference = () => globalThis.scheduleTheme?.read() || null;
export function saveThemePreference(theme) { globalThis.scheduleTheme?.save(theme); }
export function applyThemePreference(theme='system') {
  if(globalThis.scheduleTheme)globalThis.scheduleTheme.apply(readThemePreference()||theme);
  else if(typeof document!=='undefined')document.documentElement.dataset.accountTheme=theme==='dark'||theme==='system'&&globalThis.matchMedia?.('(prefers-color-scheme: dark)').matches?'dark':'light';
}
