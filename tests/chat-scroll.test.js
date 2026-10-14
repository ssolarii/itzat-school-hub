import test from 'node:test';
import assert from 'node:assert/strict';
import {captureChatScroll,restoreChatScroll} from '../src/chat-scroll.js';

const root=history=>({querySelector:()=>history});

test('chat redraw keeps the reading position in the same room',()=>{
  const previous=captureChatScroll(root({dataset:{roomId:'class'},scrollTop:210,scrollHeight:1200,clientHeight:400}));
  const next={dataset:{},scrollTop:0,scrollHeight:1300,clientHeight:400};
  restoreChatScroll(root(next),previous,'class');
  assert.equal(next.scrollTop,210);
});

test('new messages and a new room open at the latest message',()=>{
  const atEnd=captureChatScroll(root({dataset:{roomId:'class'},scrollTop:800,scrollHeight:1200,clientHeight:400}));
  const next={dataset:{},scrollTop:0,scrollHeight:1350,clientHeight:400};
  restoreChatScroll(root(next),atEnd,'class');
  assert.equal(next.scrollTop,1350);
  const changed={dataset:{},scrollTop:0,scrollHeight:900,clientHeight:400};
  restoreChatScroll(root(changed),{...atEnd,atEnd:false},'school');
  assert.equal(changed.scrollTop,900);
});
