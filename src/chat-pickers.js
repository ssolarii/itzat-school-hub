import 'emoji-picker-element';
export function bindChatPickers(root,onInput){
  root.addEventListener('click',event=>{
    const choice=event.target.closest('[data-symbol-choice]');
    if(choice){const group=choice.closest('.chat-icon-picker'),input=group.querySelector('input[type=hidden]');input.value=choice.dataset.symbolChoice;group.querySelectorAll('[data-symbol-choice]').forEach(b=>b.setAttribute('aria-pressed',String(b===choice)));if(input.name==='status_icon'&&input.value){input.form.querySelector('[name="status_emoji"]').value='';input.form.querySelector('[name="status_emoji_id"]').value='';}onInput(input);return;}
    const toggle=event.target.closest('[data-emoji-toggle]');if(toggle){const container=toggle.parentElement.querySelector('[data-emoji-container]');container.hidden=!container.hidden;toggle.setAttribute('aria-expanded',String(!container.hidden));}
  });
  root.addEventListener('input',event=>{if(event.target.matches('[data-icon-search]')){const query=event.target.value.toLowerCase();event.target.closest('.chat-icon-picker').querySelectorAll('[data-symbol-name]').forEach(b=>b.hidden=!b.dataset.symbolName.includes(query));}});
  root.addEventListener('emoji-click',event=>{const picker=event.target.closest('emoji-picker'),unicode=event.detail?.unicode;if(!picker||!unicode)return;const status=picker.dataset.emojiTarget==='status',form=status?picker.closest('form'):root.querySelector('[data-community-form="message"]'),input=form?.querySelector(status?'[name="status_emoji"]':'[name="body"]');if(!input)return;if(status){input.value=unicode;const custom=form.querySelector('[name="status_emoji_id"]');if(custom)custom.value='';const symbol=form.querySelector('[name="status_icon"]');if(symbol)symbol.value='';}else input.setRangeText(unicode,input.selectionStart,input.selectionEnd,'end');onInput(input);input.focus();});
}
export const emojiPickerMarkup = target => `<emoji-picker data-emoji-target="${target}" data-source="emoji-data.json" aria-label="Choose an emoji"></emoji-picker>`;
