import fs from 'node:fs/promises';
const names = ['star','award','heart','flame','sparkles','crown','shield-check','rosette','rocket','palette','music','device-gamepad','book','ball-football','moon','sun','coffee','code','school','planet','bolt','headphones','mood-smile'];
const icons = {};
for (const name of names) icons[name] = (await fs.readFile(`node_modules/@tabler/icons/icons/outline/${name}.svg`, 'utf8')).replace(/<svg[^>]*>/, '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" class="chat-symbol">').replace(/\s+/g, ' ').trim();
await fs.writeFile('src/chat-icon-catalog.js', '// Generated from @tabler/icons (MIT). Run node scripts/build-chat-icons.mjs to refresh.\nexport const CHAT_ICONS = '+JSON.stringify(icons,null,2)+';\n');
await fs.copyFile('node_modules/emoji-picker-element-data/en/emojibase/data.json','public/emoji-data.json');
