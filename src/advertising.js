const COOKIE='school-ads';
const MODES=['off','standard','more'];
export function readAdPreference(cookies=globalThis.document?.cookie||'') {
  const value=cookies.match(/(?:^|;\s*)school-ads=(off|standard|more)(?:;|$)/)?.[1];
  return value||'standard';
}
function savePreference(mode) {
  if(!MODES.includes(mode))return;
  const path=location.pathname.slice(0,location.pathname.lastIndexOf('/')+1)||'/';
  document.cookie=`${COOKIE}=${mode}; Path=${path}; Max-Age=31536000; SameSite=Lax${location.protocol==='https:'?'; Secure':''}`;
}
export function adPreferences() {
  const selected=readAdPreference();
  return `<section class="section ad-preferences" aria-labelledby="ad-preferences-title"><h3 id="ad-preferences-title">Advertising</h3><p>Ads help cover hosting and bandwidth costs. They’re optional, and your access stays the same with ads off.</p><div class="ad-mode-options" role="group" aria-label="Desktop ad amount">${[['off','Off'],['standard','Standard'],['more','More']].map(([mode,label])=>`<button type="button" class="button secondary" data-ad-mode="${mode}" aria-pressed="${selected===mode}">${label}</button>`).join('')}</div><p class="subtle" data-ad-preference-status>Standard allows one desktop placement. More allows up to two where there’s room. No mobile ads, popups, or full-screen ads.</p><p class="subtle">AdSense setup must be completed before ads can appear. This preference stays on your browser. <a href="privacy.html">Privacy and advertising</a></p></section>`;
}

/** Manual placements only. No account or class identifiers in request options. */
export function createAdvertising({root,config={},getRoute}) {
  const desktop=matchMedia('(min-width: 1100px) and (hover: hover) and (pointer: fine)');
  const mobileDevice=navigator.userAgentData?.mobile===true||/Android|iPhone|iPad|iPod|Mobile/i.test(navigator.userAgent);
  const publicRoutes=new Set(['schedule','calendar','updates']);
  let host=null,observer=null,dialog=null,opener=null,scriptPromise=null,generation=0;
  const eligible=()=>!mobileDevice&&desktop.matches&&publicRoutes.has(getRoute())&&readAdPreference()!=='off'&&config.ready===true&&/^ca-pub-\d+$/.test(config.publisher||'')&&/^\d+$/.test(config.slot||'')&&location.protocol==='https:'&&!/[?&#](?:code|access_token|refresh_token|token_hash|error_description)=/.test(location.search+location.hash);
  function clear(){generation++;observer?.disconnect();observer=null;host?.remove();host=null;}
  function loadScript(){
    if(scriptPromise)return scriptPromise;
    window.adsbygoogle=window.adsbygoogle||[];
    window.adsbygoogle.requestNonPersonalizedAds=1;
    scriptPromise=new Promise((resolve,reject)=>{
      const script=document.createElement('script');
      script.id='school-adsense';script.async=true;script.crossOrigin='anonymous';script.referrerPolicy='origin';
      script.src='https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client='+config.publisher;
      script.onload=resolve;script.onerror=reject;document.head.append(script);
    });
    return scriptPromise;
  }
  async function request(unit){
    const token=generation;
    if(!eligible()||unit.dataset.requested)return;
    unit.dataset.requested='true';
    try{
      await loadScript();
      if(token!==generation||!eligible()||!unit.isConnected)return;
      // No timers or automatic ad refreshes. Consent setup is a launch gate.
      window.adsbygoogle.pauseAdRequests=0;
      window.adsbygoogle.push({});
    }catch{unit.closest('.desktop-ad')?.remove();}
  }
  function build(){
    host=document.createElement('aside');host.className='desktop-ad-area';host.setAttribute('aria-label','Advertisements');
    const count=readAdPreference()==='more'?2:1;
    for(let index=0;index<count;index++){
      const card=document.createElement('section');card.className='desktop-ad';
      const header=document.createElement('div');header.className='desktop-ad-heading';
      const label=document.createElement('span');label.textContent='Advertisement';header.append(label);
      const close=document.createElement('button');close.type='button';close.className='ad-close';close.dataset.closeAds='';close.textContent='Close';close.setAttribute('aria-label','Turn off website ads');header.append(close);card.append(header);
      const unit=document.createElement('ins');unit.className='adsbygoogle';unit.style.cssText='display:inline-block;width:728px;height:90px';
      unit.dataset.adClient=config.publisher;unit.dataset.adSlot=config.slot;card.append(unit);host.append(card);
    }
    observer=new IntersectionObserver(entries=>{for(const entry of entries)if(entry.isIntersecting){observer?.unobserve(entry.target);void request(entry.target);}},{rootMargin:'100px'});
    for(const unit of host.querySelectorAll('ins'))observer.observe(unit);
  }
  function mount(){
    if(!eligible()){clear();return;}
    const target=root.querySelector('.content');if(!target)return;
    if(!host)build();
    target.append(host);
  }
  function reflect(){
    const mode=readAdPreference();
    root.querySelectorAll('[data-ad-mode]').forEach(button=>button.setAttribute('aria-pressed',String(button.dataset.adMode===mode)));
    const status=root.querySelector('[data-ad-preference-status]');
    if(status)status.textContent=mode==='off'?'Ads are off across this browser.':`Saved for the next page load: ${mode==='more'?'up to two':'one'} desktop ad placement${mode==='more'?'s':''}. Mobile stays ad-free.`;
  }
  function choose(mode){
    savePreference(mode);clear();
    if(mode==='off'&&window.adsbygoogle)window.adsbygoogle.pauseAdRequests=1;
    // A changed density applies on the next page load, never by refreshing ads.
    reflect();
  }
  function closeDialog(){dialog?.close();dialog?.remove();dialog=null;opener?.focus();opener=null;}
  function askToDisable(button){
    if(dialog)return;opener=button;dialog=document.createElement('dialog');dialog.className='ad-disable-dialog';dialog.setAttribute('aria-labelledby','disable-ads-title');
    dialog.innerHTML='<h2 id="disable-ads-title">Turn off ads?</h2><p>Ads help cover hosting and bandwidth costs. You can use the site without them. Turning them off applies across this browser.</p><div class="dialog-actions"><button class="button secondary" type="button" data-keep-ads>Keep ads</button><button class="button" type="button" data-confirm-no-ads>Turn off ads</button></div>';
    dialog.addEventListener('cancel',event=>{event.preventDefault();closeDialog();});
    dialog.addEventListener('click',event=>{if(event.target.closest('[data-confirm-no-ads]')){choose('off');closeDialog();}else if(event.target.closest('[data-keep-ads]'))closeDialog();});
    document.body.append(dialog);dialog.showModal();dialog.querySelector('[data-confirm-no-ads]').focus();
  }
  root.addEventListener('click',event=>{
    const choice=event.target.closest('[data-ad-mode]');if(choice){choose(choice.dataset.adMode);return;}
    const close=event.target.closest('[data-close-ads]');if(close)askToDisable(close);
  });
  desktop.addEventListener('change',()=>{if(!desktop.matches){clear();if(window.adsbygoogle)window.adsbygoogle.pauseAdRequests=1;}else mount();});
  return {mount,detach(){host?.remove();},clear};
}
