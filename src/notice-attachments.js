import {escape as esc,icon} from './views.js';
const https = value => {try{const url=new URL(value);return url.protocol==='https:'&&!url.username&&!url.password?url.href:'';}catch{return '';}};
export function noticeContent(notice){
 let body=String(notice.body||''),classroomUrl=https(notice.classroomUrl);
 const legacy=body.match(/\n\nOriginal Classroom post: (https:\/\/classroom\.google\.com\/\S+)$/);
 if(legacy){classroomUrl=classroomUrl||legacy[1];body=body.slice(0,legacy.index);}
 if(classroomUrl&&!/^https:\/\/classroom\.google\.com\//.test(classroomUrl))classroomUrl='';
 const linked=body.split(/(https:\/\/[^\s<>]+)/g).map(part=>{const url=https(part);return url?`<a href="${esc(url)}" target="_blank" rel="noopener noreferrer">${esc(part)}</a>`:esc(part);}).join('');
 const attachments=(notice.attachments||[]).slice(0,20).map(item=>{
   const url=https(item.url);if(!url)return '';
   const image=https(item.imageUrl),title=String(item.title||'Attachment');
   return `<a class="notice-attachment" href="${esc(url)}" target="_blank" rel="noopener noreferrer">${image?`<img src="${esc(image)}" alt="${esc(title)}" loading="lazy" referrerpolicy="no-referrer" data-notice-preview>`:icon(item.kind==='video'?'play':'paperclip')}<span>${esc(title)}<small>${item.kind==='file'?'Open file':item.kind==='video'?'Open video':'Open link'}</small></span>${icon('external-link')}</a>`;
 }).join('');
 return `<p class="notice-body">${linked}</p>${attachments?`<div class="notice-attachments">${attachments}</div>`:''}${classroomUrl?`<div class="notice-source"><a class="button secondary" href="${esc(classroomUrl)}" target="_blank" rel="noopener noreferrer">${icon('external-link')}Link to Classroom</a></div>`:''}`;
}
