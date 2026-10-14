import {emojiText} from './emoji-text.js';

export function composerText(editor){
  function read(node){
    if(node.nodeType===3)return node.nodeValue;
    if(node.nodeType!==1&&node.nodeType!==11)return '';
    if(node.dataset?.emojiCode)return node.dataset.emojiCode;
    if(node.nodeName==='BR')return '\n';
    let text='';for(const child of node.childNodes){if(['DIV','P'].includes(child.nodeName)&&text&&!text.endsWith('\n'))text+='\n';text+=read(child);}return text;
  }
  return read(editor).replaceAll('\u00a0',' ');
}
export function composerCaret(editor){
  const selection=editor.ownerDocument.getSelection();
  if(selection?.rangeCount&&editor.contains(selection.anchorNode)){
    const range=selection.getRangeAt(0).cloneRange();range.selectNodeContents(editor);range.setEnd(selection.focusNode,selection.focusOffset);
    return composerText(range.cloneContents()).length;
  }
  return Number(editor.dataset.caretOffset??composerText(editor).length);
}
export function setComposerCaret(editor,offset){
  const doc=editor.ownerDocument,range=doc.createRange();let remaining=offset,found=false;
  function visit(node){
    if(found)return;
    if(node.nodeType===3){if(remaining<=node.length){range.setStart(node,remaining);found=true;}else remaining-=node.length;return;}
    if(node.dataset?.emojiCode||node.nodeName==='BR'){
      const length=node.dataset?.emojiCode?.length||1;
      if(remaining<=length){remaining===0?range.setStartBefore(node):range.setStartAfter(node);found=true;}else remaining-=length;return;
    }
    for(const child of node.childNodes)visit(child);
  }
  visit(editor);if(!found){range.selectNodeContents(editor);range.collapse(false);}else range.collapse(true);
  const selection=doc.getSelection();selection.removeAllRanges();selection.addRange(range);editor.dataset.caretOffset=String(offset);
}
export function syncComposer(editor,model){
  const offset=composerCaret(editor),value=composerText(editor).slice(0,4000),html=emojiText(value,model,{editing:true});
  if(editor.dataset.composing!=='true'&&editor.innerHTML!==html){editor.innerHTML=html;setComposerCaret(editor,Math.min(offset,value.length));}
  const hidden=editor.closest('form')?.querySelector('[name="body"]');if(hidden)hidden.value=value;
  editor.dataset.caretOffset=String(Math.min(offset,value.length));return value;
}
export function insertComposerText(editor,text,model){
  const value=composerText(editor),offset=composerCaret(editor),selection=editor.ownerDocument.getSelection();
  let start=offset,end=offset;if(selection?.rangeCount&&editor.contains(selection.anchorNode)&&!selection.isCollapsed){const range=selection.getRangeAt(0);const prefix=range.cloneRange();prefix.selectNodeContents(editor);prefix.setEnd(range.startContainer,range.startOffset);start=composerText(prefix.cloneContents()).length;end=start+composerText(range.cloneContents()).length;}
  const next=(value.slice(0,start)+text+value.slice(end)).slice(0,4000);
  editor.innerHTML=emojiText(next,model,{editing:true});editor.focus();setComposerCaret(editor,Math.min(start+text.length,next.length));
  return syncComposer(editor,model);
}
export function bindComposer(root,onInput){
  root.addEventListener('pointerdown',()=>{const editor=root.querySelector('[data-emoji-composer]');if(editor)editor.dataset.caretOffset=String(composerCaret(editor));});
  root.addEventListener('compositionstart',event=>{if(event.target.matches('[data-emoji-composer]'))event.target.dataset.composing='true';});
  root.addEventListener('compositionend',event=>{if(event.target.matches('[data-emoji-composer]')){delete event.target.dataset.composing;onInput(event.target);}});
  root.addEventListener('paste',event=>{const editor=event.target.closest('[data-emoji-composer]');if(!editor)return;event.preventDefault();const text=event.clipboardData?.getData('text/plain')||'';editor.focus();const selection=editor.ownerDocument.getSelection();if(selection?.rangeCount&&editor.contains(selection.anchorNode)){const range=selection.getRangeAt(0);range.deleteContents();const node=editor.ownerDocument.createTextNode(text);range.insertNode(node);range.setStartAfter(node);range.collapse(true);selection.removeAllRanges();selection.addRange(range);}else editor.append(text);onInput(editor);});
}
