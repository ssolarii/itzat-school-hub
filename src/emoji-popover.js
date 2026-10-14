import {escape as e,icon} from './views.js';
import {emojiImage} from './emoji-text.js';

export function renderEmojiPopover(model){
  if(!model.emojiPicker)return '';
  const reaction=model.emojiPicker==='reaction',emojis=(model.emojis||[]).filter(item=>item.status==='approved');
  return `<section id="chat-emoji-popover" class="chat-emoji-popover" popover="auto" role="dialog" aria-label="${reaction?'Choose a reaction':'Choose an emoji'}"><header><h2>${reaction?'Add a reaction':'Emoji'}</h2><button type="button" class="chat-control chat-icon-button" data-community-action="cancel-emoji-picker" aria-label="Close emoji picker">${icon('x')}</button></header>${emojis.length?`<div class="picker-custom-emojis"><h3>School emoji</h3><div>${emojis.map(item=>`<button type="button" class="chat-control" data-community-action="picker-custom-emoji" data-value=":${e(item.name)}:" title=":${e(item.name)}:" aria-label="${e(item.name)}">${emojiImage(item)}</button>`).join('')}</div></div>`:''}<emoji-picker data-emoji-target="${reaction?'reaction':'message'}" data-message-id="${e(model.reactingMessageId||'')}" data-source="emoji-data.json" aria-label="${reaction?'Choose a reaction':'Choose an emoji'}"></emoji-picker>${reaction?'':'<button type="button" class="chat-control picker-media-link" data-community-action="chat-panel" data-value="media">GIFs & custom emoji uploads</button>'}</section>`;
}
export function positionEmojiPopover(root,model,onClose){
  const popup=root.querySelector('#chat-emoji-popover');if(!popup)return;
  const width=Math.min(352,window.innerWidth-24),height=Math.min(510,window.innerHeight-24),anchor=model.emojiPickerAnchor||{left:window.innerWidth/2,top:window.innerHeight-80,bottom:window.innerHeight-50};
  popup.style.width=width+'px';popup.style.maxHeight=height+'px';
  popup.style.left=Math.max(12,Math.min(anchor.left,window.innerWidth-width-12))+'px';
  popup.style.top=Math.max(12,Math.min(anchor.top-height-8,window.innerHeight-height-12))+'px';
  if(popup.showPopover){popup.showPopover();popup.addEventListener('toggle',event=>{if(event.newState==='closed'&&popup.isConnected)onClose();});}
  else popup.style.display='block';
}
