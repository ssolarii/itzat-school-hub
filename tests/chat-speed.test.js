import test from 'node:test';
import assert from 'node:assert/strict';
import {createCommunityController} from '../src/community-controller.js';
const session={user:{id:'speed-user',email_confirmed_at:'2026-10-13'}};
function fixture(){
 const calls=[],alerts=[],own={user_id:'speed-user',real_name:'User',class_group:'3CS'};
 const rooms=[{id:'class-room',kind:'class',class_group:'3CS',status:'approved'},{id:'dm-room',kind:'dm',status:'approved'}];
 let friends=[];
 const client={storage:{},rpc:async(name,args)=>{calls.push({name,args});const data={community_admission_state:{admitted:true},community_get_profile:own,community_profiles_directory:[own],community_list_rooms:rooms,community_list_friends:friends,school_space_get_state:{profile:own,authority:{role:'Student'},channels:[],server:{}},community_activity:{cursor:0,events:[]}};return {data:data[name]||[],error:null};}};
 const controller=createCommunityController({client,storage:{getItem:()=>null,setItem:()=>{}},getContext:()=>({session,audience:'student',group:'3CS',groups:['3CS'],online:true}),onChange:()=>{},onNavigate:()=>{},onAlert:(message,options)=>alerts.push({message,options})});
 return {controller,calls,alerts,setFriends:value=>{friends=value;}};
}
test('chat startup omits Q+A and review RPCs; changing rooms requests only messages',async()=>{
 const {controller,calls}=fixture();controller.render('chat');await controller.load();
 assert.ok(!calls.some(c=>['community_list_posts','community_reports','community_list_user_reports'].includes(c.name)));
 calls.length=0;await controller.action({dataset:{communityAction:'open-conversation',id:'dm-room'}});
 assert.deepEqual(calls.map(c=>c.name),['community_messages']);assert.equal(controller.model.chatSpace,'dms');
});
test('new incoming friend requests produce one actionable toast and never repeat on unchanged polls',async()=>{
 const {controller,alerts,setFriends}=fixture();controller.render('chat');await controller.load();
 setFriends([{id:'friend-request',status:'pending',requested_by:'other-user',other_id:'other-user',display_name:'Alex'}]);
 await controller.pollNotifications();assert.equal(alerts.length,1);assert.match(alerts[0].message,/Alex sent you a friend request/);assert.equal(alerts[0].options.actionLabel,'View requests');
 await controller.pollNotifications();assert.equal(alerts.length,1);
});

test('new student accounts open the welcome channel on first chat entry',async()=>{
 const userId='speed-user',welcome={id:'welcome-room',kind:'school',school_channel:'welcome',status:'approved'};
 const own={user_id:userId,real_name:'User',class_group:'3CS'};
 const saved=new Map([['school-chat-first-entry:'+userId,'welcome']]);
 const storage={getItem:key=>saved.get(key)||null,setItem:(key,value)=>saved.set(key,value)};
 const client={storage:{},rpc:async name=>({data:({community_admission_state:{admitted:true},community_get_profile:own,community_profiles_directory:[own],community_list_rooms:[{id:'class-room',kind:'class',class_group:'3CS',status:'approved'},welcome],community_list_friends:[],school_space_get_state:{profile:{...own,space_onboarded:false,cosmetic_roles:[]},authority:{role:'Student'},channels:[welcome],server:{}},community_activity:{cursor:0,events:[]},community_messages:[]})[name]||[],error:null})};
 const controller=createCommunityController({client,storage,getContext:()=>({session,audience:'student',group:'3CS',groups:['3CS'],online:true}),onChange:()=>{},onNavigate:()=>{}});
 controller.render('chat');await controller.load();
 assert.equal(controller.model.chatSpace,'campus');
 assert.equal(controller.model.activeConversationId,'welcome-room');
 assert.equal(saved.get('school-chat-first-entry:'+userId),'');
});
