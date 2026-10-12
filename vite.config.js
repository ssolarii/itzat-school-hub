import {defineConfig} from 'vite';
export default defineConfig({base:'./',build:{assetsDir:'assets',rollupOptions:{input:{landing:'index.html',schedule:'schedule.html'}}}});
