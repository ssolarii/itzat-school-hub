import test from 'node:test';
import assert from 'node:assert/strict';
import {createCommunityApi} from '../src/community-api.js';
import {renderCommunity,renderMessageList,safeCommunityMedia} from '../src/community-views.js';
import {createCommunityController,safeGifURL,readSavedGifs} from '../src/community-controller.js';

const session={user:{id:'student-a',email_confirmed_at:'2026-10-11'}};
const calls=[];
function client(data={}){return {rpc:async(name,args)=>{calls.push({name,args});return {data:data[name]??(name==='community_admission_state'?{admitted:true}:[]),error:null};},storage:{from:()=>({createSignedUrls:async paths=>({data:paths.map(path=>({path,signedUrl:`https://school.example/${path}`}))})})}};}
test('community adapter keeps vote, like and reviews separate with typed RPC parameters',async()=>{
  calls.length=0;const api=createCommunityApi(client());
  await api.votePost('p',true);await api.likePost('p',true);await api.reviewRoom('r',false);await api.setDecision('p','no','Reason');
  assert.deepEqual(calls.map(c=>c.name),['community_vote','community_like','community_review_room','community_set_decision']);
  assert.deepEqual(calls[0].args,{p_post:'p',p_vote:true});assert.equal(calls[2].args.p_approve,false);assert.equal(calls[3].args.p_note,'Reason');
});
test('private media links are short-lived and upload MIME/size is checked before upload',async()=>{
  const api=createCommunityApi(client());assert.deepEqual(await api.signMedia(['x','x']),{x:'https://school.example/x'});
  await assert.rejects(api.uploadMedia({type:'image/svg+xml',size:20}),/JPG/);
  await assert.rejects(api.uploadMedia({type:'image/gif',size:6*1024*1024}),/5 MB/);
});
test('saved GIFs accept only direct trusted HTTPS GIFs and reject corrupt local data',()=>{
  assert.ok(safeGifURL('https://media.tenor.com/example.gif'));
  for(const url of ['http://media.tenor.com/a.gif','https://evil.example/a.gif','https://media.tenor.com/a.svg','https://media.tenor.com@evil.example/a.gif','javascript:alert(1)'])assert.equal(safeGifURL(url),'');
  assert.deepEqual(readSavedGifs({getItem:()=>'{broken'}),[]);
  assert.equal(readSavedGifs({getItem:()=>JSON.stringify([{url:'https://media.giphy.com/test.gif',name:'Wave'},{url:'https://evil.example/a.gif'}])}).length,1);
  assert.equal(readSavedGifs({getItem:()=>JSON.stringify([{url:'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==',name:'Local GIF'}])}).length,1);
});
test('guest chat and class polls are gated while approved site suggestions remain readable',()=>{
  assert.match(renderCommunity({section:'chat'}),/Sign in or create an account/);
  assert.match(renderCommunity({section:'qa',model:{qaScope:'class'}}),/Class polls are for your class/);
  const html=renderCommunity({section:'qa',model:{qaScope:'site',proposals:[{id:'p',scope:'site',title:'Better calendar',body:'Details',status:'approved',target:'parent',yes_count:2,no_count:1,like_count:5}]}});
  assert.match(html,/Better calendar/);assert.match(html,/5 likes/);assert.match(html,/data-community-action="vote"[^>]*disabled/);
});
test('profile text, messages, proposal copy and custom colors cannot inject markup',()=>{
  const html=renderCommunity({section:'profile',session,model:{groups:['3CS'],profile:{real_name:'<script>bad</script>',display_name:'<img src=x>',class_group:'3CS',bio:'<svg onload=x>',accent:'red;position:fixed'}}});
  assert.ok(!html.includes('<script>bad'));assert.ok(!html.includes('<svg onload=x>'));assert.ok(!html.includes('red;position'));
  const messages=renderMessageList({session,model:{messages:[{id:1,room_id:'r',author_id:'student-a',body:'<script>alert(1)</script>',gif_url:'javascript:alert(1)'}]},roomId:'r'});
  assert.match(messages,/&lt;script&gt;/);assert.ok(!messages.includes('src="javascript:'));
  assert.equal(safeCommunityMedia('javascript:alert(1)'),'');
});
test('principal reviews rooms but cannot author Developer Updates or decisions',()=>{
  const membership={active:true,role:'principal'};
  const html=renderCommunity({section:'qa',session,membership,model:{qaScope:'updates'}});
  assert.ok(!html.includes('data-community-form="announcement"'));
  const post=renderCommunity({section:'qa',session,membership,model:{qaScope:'site',proposals:[{id:'p',scope:'site',title:'Idea',status:'approved'}]}});
  assert.ok(!post.includes('data-community-form="decision"'));
});
test('parent profile preview does not imply membership in the schedule picker class',()=>{
  const html=renderCommunity({section:'profile',session,group:'3CS',model:{profile:{real_name:'Parent name',audience:'parent'},groups:['3CS']}});
  assert.match(html,/Parent name · Parent/);assert.ok(!html.includes('Parent name · 3CS'));
});
test('controller clears all private state across account changes and never saves chats locally',async()=>{
  const writes=[];let ctx={session,membership:null,audience:'student',group:'3CS',groups:['3CS'],online:true};
  const apiClient=client({community_get_profile:{user_id:'student-a',class_group:'3CS'},community_profiles_directory:[],community_list_rooms:[{id:'r',kind:'class',status:'approved',class_group:'3CS'}],community_messages:[{id:1,room_id:'r',body:'Private message'}]});
  const controller=createCommunityController({client:apiClient,storage:{getItem:()=>null,setItem:(...args)=>writes.push(args)},getContext:()=>ctx,onChange:()=>{},onNavigate:()=>{}});
  await controller.load();assert.equal(controller.model.messages[0].body,'Private message');
  ctx={...ctx,session:null};controller.reset();assert.equal(controller.model.messages.length,0);assert.equal(controller.model.profiles.length,0);assert.equal(controller.model.profile,null);assert.deepEqual(writes,[]);
});
test('finishing a conversation load rerenders the composer with Send enabled',async()=>{
 let controller,html='';const apiClient=client({community_get_profile:{user_id:'student-a',class_group:'3CS'},community_list_rooms:[{id:'r',kind:'class',status:'approved',class_group:'3CS'}]});
 controller=createCommunityController({client:apiClient,storage:{getItem:()=>null},getContext:()=>({session,audience:'student',group:'3CS',groups:['3CS'],online:true}),onChange:()=>{html=controller.render('chat');},onNavigate:()=>{}});
 await controller.load();assert.ok(html.includes('aria-label="Send message"'));assert.ok(!html.includes('aria-label="Send message" disabled'));assert.ok(!html.includes('Loading conversations…'));
});
test('pending conversations never get an active composer',async()=>{
  const controller=createCommunityController({client:client({community_get_profile:{user_id:'student-a',class_group:'3CS'},community_list_rooms:[{id:'pending',kind:'dm',status:'pending'}]}),storage:{getItem:()=>null},getContext:()=>({session,online:true,groups:['3CS'],audience:'student'}),onChange:()=>{},onNavigate:()=>{}});
  await controller.load();assert.equal(controller.model.activeConversationId,null);assert.equal(controller.model.joinRequests.length,1);assert.equal(controller.model.conversations.length,0);
});
test('a delayed message load cannot repopulate private state after sign-out',async()=>{
  let ctx={session,online:true,groups:['3CS'],audience:'student'},release,started;
  const ready=new Promise(resolve=>started=resolve),pending=new Promise(resolve=>release=resolve);
  const apiClient=client({community_get_profile:{user_id:'student-a',class_group:'3CS'},community_list_rooms:[{id:'r',kind:'class',status:'approved'}]});
  const rpc=apiClient.rpc;apiClient.rpc=async(name,args)=>name==='community_messages'?(started(),await pending):rpc(name,args);
  const controller=createCommunityController({client:apiClient,storage:{getItem:()=>null},getContext:()=>ctx,onChange:()=>{},onNavigate:()=>{}});
  const loading=controller.load();await ready;ctx={...ctx,session:null};controller.reset();release({data:[{id:1,room_id:'r',body:'Old private response'}],error:null});await loading;
  assert.deepEqual(controller.model.messages,[]);assert.equal(controller.model.profile,null);
});
test('an old poll cannot replace the newly selected conversation',async()=>{
  let release,started,polling=false;
  const ready=new Promise(resolve=>started=resolve),pending=new Promise(resolve=>release=resolve);
  const apiClient=client({community_get_profile:{user_id:'student-a',class_group:'3CS'},community_list_rooms:[{id:'a',kind:'class',status:'approved'},{id:'b',kind:'dm',status:'approved'}]});
  const rpc=apiClient.rpc;apiClient.rpc=async(name,args)=>{if(name!=='community_messages')return rpc(name,args);if(polling&&args.p_room==='a'){started();return pending;}return {data:[{id:args.p_room==='a'?1:2,room_id:args.p_room,body:args.p_room}],error:null};};
  const controller=createCommunityController({client:apiClient,storage:{getItem:()=>null},getContext:()=>({session,online:true,groups:['3CS'],audience:'student'}),onChange:()=>{},onNavigate:()=>{}});
  await controller.load();controller.render('chat');polling=true;const poll=controller.poll();await ready;
  await controller.action({dataset:{communityAction:'open-conversation',id:'b'}});release({data:[{id:1,room_id:'a',body:'Old room response'}],error:null});await poll;
  assert.equal(controller.model.activeConversationId,'b');assert.equal(controller.model.messages[0].room_id,'b');
});
