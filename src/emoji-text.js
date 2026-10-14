import {escape as e} from './views.js';

export const emojiCodePattern=/:([a-z0-9_]{1,32}):/g;
export function approvedEmoji(model,name){return (model?.emojis||[]).find(item=>item.status==='approved'&&item.name===name);}
export function emojiImage(emoji,{editing=false}={}){
  if(!emoji||emoji.status!=='approved')return '';
  let url;try{url=new URL(emoji.image_url||emoji.url);}catch{return '';}
  if(url.protocol!=='https:'||url.username||url.password)return '';
  const code=`:${emoji.name}:`;
  return `<img class="chat-inline-emoji" src="${e(url.href)}" alt="${e(code)}" title="${e(code)}" ${editing?`contenteditable="false" draggable="false" data-emoji-code="${e(code)}"`:''}>`;
}
export function emojiText(text,model,{editing=false}={}){
  let output='',start=0;const value=String(text||'');
  for(const match of value.matchAll(emojiCodePattern)){
    output+=e(value.slice(start,match.index));
    output+=emojiImage(approvedEmoji(model,match[1]),{editing})||e(match[0]);start=match.index+match[0].length;
  }
  output+=e(value.slice(start));return editing?output.replaceAll('\n','<br>'):output;
}
