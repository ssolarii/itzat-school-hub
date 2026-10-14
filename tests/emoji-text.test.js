import test from 'node:test';
import assert from 'node:assert/strict';
import {emojiText} from '../src/emoji-text.js';
import {messageText} from '../src/message-interactions.js';
import {renderMessageList} from '../src/community-views.js';
import {renderChatShell} from '../src/chat-shell.js';
import {composerText} from '../src/emoji-composer.js';
import {founderDecoration,ORIGINAL_FOUNDER_BADGE} from '../src/chat-decorations.js';

const emoji={id:'emoji-1',name:'joeshrug',status:'approved',image_url:'https://example.com/shrug.gif'};
const model={emojis:[emoji,{...emoji,id:'pending',name:'pending',status:'pending'}]};
test('approved shortcode images replace every matching code and escape surrounding text',()=>{
 const html=messageText('Hi :joeshrug: <script>x</script> :joeshrug: :unknown: :pending:',model);
 assert.equal((html.match(/class="chat-inline-emoji"/g)||[]).length,2);
 assert.ok(html.includes('&lt;script&gt;'));assert.ok(html.includes(':unknown:'));assert.ok(html.includes(':pending:'));
 assert.ok(!emojiText(':joeshrug:',{emojis:[{...emoji,image_url:'javascript:alert(1)'}]}).includes('<img'));
});
test('legacy selected emoji is not rendered twice when its shortcode is in the body',()=>{
 const html=renderMessageList({model:{...model,messages:[{id:1,body:':joeshrug:',emoji_id:emoji.id}]}});
 assert.equal((html.match(/shrug.gif/g)||[]).length,1);
});
test('editable emoji chips serialize to codes with line breaks, not remote image markup',()=>{
 const text=value=>({nodeType:3,nodeValue:value});const element=(nodeName,childNodes=[],dataset={})=>({nodeType:1,nodeName,childNodes,dataset});
 const root=element('DIV',[text('Hi '),element('IMG',[],{emojiCode:':joeshrug:'}),element('BR'),text('next')]);
 assert.equal(composerText(root),'Hi :joeshrug:\nnext');
 assert.match(emojiText('Hi :joeshrug:',model,{editing:true}),/contenteditable="false"/);
});
test('reaction picker floats outside message articles and includes approved custom emoji',()=>{
 const html=renderChatShell({session:{user:{id:'a'}},model:{...model,profile:{real_name:'A'},emojiPicker:'reaction',reactingMessageId:1,messages:[{id:1,body:'Hi'}]}});
 assert.ok(html.includes('popover="auto"'));assert.ok(html.includes('data-value=":joeshrug:"'));assert.ok(!html.includes('data-value=":pending:"'));
 assert.ok(!html.includes('class="message-reaction-picker"'));
});
test('Founder decoration requires the awarded special badge identity',()=>{
 assert.equal(founderDecoration({badges:[{id:'fake',name:'Original Founder'}]}),'');
 assert.ok(founderDecoration({badges:[{id:ORIGINAL_FOUNDER_BADGE}]}).includes('founder-crest'));
});
