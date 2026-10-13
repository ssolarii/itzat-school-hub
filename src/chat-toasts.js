/** Ephemeral, account-scoped alerts. No messages or profile data are persisted. */
export function createChatToasts({document:doc=globalThis.document,max=3}={}){
 let region=null;const items=new Map();
 function remove(key){const item=items.get(key);if(!item)return;clearTimeout(item.timer);item.node.remove();items.delete(key);}
 function clear(){for(const key of [...items.keys()])remove(key);region?.remove();region=null;}
 function show(message,{tone='info',key=String(message),actionLabel,onAction}={}){
  if(!doc||!message||items.has(key))return;
  if(!region){region=doc.createElement('section');region.className='chat-toast-region';region.setAttribute('aria-label','Chat alerts');doc.body.append(region);}
  if(items.size>=max)remove(items.keys().next().value);
  const node=doc.createElement('div');node.className=`chat-toast chat-toast-${tone==='error'?'error':'info'}`;node.setAttribute('role',tone==='error'?'alert':'status');
  const text=doc.createElement('p');text.textContent=message;node.append(text);
  if(actionLabel&&onAction){const action=doc.createElement('button');action.type='button';action.textContent=actionLabel;action.onclick=()=>{remove(key);onAction();};node.append(action);}
  const dismiss=doc.createElement('button');dismiss.type='button';dismiss.className='chat-toast-dismiss';dismiss.textContent='Dismiss';dismiss.setAttribute('aria-label','Dismiss alert');dismiss.onclick=()=>remove(key);node.append(dismiss);
  region.append(node);const item={node,timer:null};items.set(key,item);
  const start=()=>{clearTimeout(item.timer);item.timer=setTimeout(()=>remove(key),tone==='error'?12000:7000);};
  node.onmouseenter=()=>clearTimeout(item.timer);node.onmouseleave=start;node.onfocusin=()=>clearTimeout(item.timer);node.onfocusout=start;start();
 }
 return {show,clear};
}
