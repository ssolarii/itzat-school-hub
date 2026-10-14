import {readThemePreference,saveThemePreference,applyThemePreference} from './theme-preference.js';
import {renderConversationPeople} from './conversation-picker.js';
import {paintUnreadDots} from './chat-navigation.js';
import {editableMessage,outgoingMessage,messagePerson,personName,mentionLabel} from './message-interactions.js';
import {renderChatAdmission} from './chat-access.js';
import {createCommunityApi} from './community-api.js';
import {renderCommunity,renderMessageList} from './community-views.js';
import {renderChatShell,renderChatSidebar} from './chat-shell.js';
import {paintIcons} from './icons.js';
import {createFriendsApi} from './friends-api.js';
import {createChatNotifications} from './chat-notifications.js';
import {createSchoolSpaceApi} from './school-space-api.js';
import {createChatRealtime} from './chat-realtime.js';
import {renderSchoolMembers} from './school-space-views.js';
import {createProfilePreviewManager,updateProfilePreview,renderProfileModal} from './profile-modal.js';

const GIF_KEY='school-saved-gifs-v1';
const localGif=value=>typeof value==='string'&&value.length<1500000&&/^data:image\/gif;base64,R0lGOD[dl]/.test(value);
export function safeGifURL(value) {
  try { const url=new URL(String(value)); return url.protocol==='https:'&&!url.username&&!url.password&&['media.tenor.com','media.giphy.com','i.giphy.com'].includes(url.hostname)&&/\.gif$/i.test(url.pathname)&&url.href.length<=1500 ? url.href : ''; } catch { return ''; }
}
export function readSavedGifs(storage) {
  try { const data=JSON.parse(storage.getItem(GIF_KEY)||'[]'); return Array.isArray(data)?data.filter(g=>g&&(safeGifURL(g.url)||localGif(g.url))).slice(0,40).map(g=>({url:localGif(g.url)?g.url:safeGifURL(g.url),name:String(g.name||'Saved GIF').slice(0,60)})):[]; } catch { return []; }
}
export function createCommunityController({enabled=true,client,storage,getContext,onChange,onNavigate,onAlert=()=>{},onClearAlerts=()=>{}}) {
  const api=client?createCommunityApi(client):null;
  const friendsApi=client?createFriendsApi(client):null;
  const spaceApi=client?createSchoolSpaceApi(client):null;
  const previews=createProfilePreviewManager();
  let generation=0,userId=null,section='qa',loading=false,accountTheme='system',messageRequest=null,lastMessageFetch=0,lastAlertError='',friendPollBusy=false,relationshipsReady=false;
  let seenFriendStates=new Map(),seenInvites=new Set();
  const mediaCache=new Map();
  const blank=()=>({profile:null,profiles:[],peers:[],friends:[],friendRequests:[],blocks:[],conversations:[],activeConversationId:null,messages:[],qaScope:'site',proposals:[],announcements:[],reviewQueue:[],emojis:[],savedGifs:readSavedGifs(storage),joinRequests:[],error:'',loaded:false,groups:[],messageDraft:'',fromSchedule:typeof location!=='undefined'&&new URLSearchParams(location.search).get('from')==='schedule',chatSpace:'school',chatMain:'thread',friendTab:'all',unreadCounts:{}});
  let model=blank();
  const realtime=createChatRealtime({client,onChange:()=>pollMessages(),onState:status=>{model.realtimeStatus=status;}});
  function applyTheme(theme,cache=false){accountTheme=readThemePreference()||theme||'system';if(cache&&!readThemePreference()&&theme)saveThemePreference(theme);applyThemePreference(accountTheme);}
  const needsSchoolInterests=()=>model.chatSpace==='campus'&&(!model.spaceState?.profile?.space_onboarded||!model.spaceState?.profile?.cosmetic_roles?.length);
  function modalClose(){const decline=needsSchoolInterests();if(decline){model.chatSpace='school';model.activeConversationId=model.conversations.find(r=>r.kind==='class')?.id||null;model.messages=[];}previews.clear();model.profileMediaPreviews={};model.profileEditDraft=null;model.profileModalOpen=false;model.spaceOnboardingOpen=false;changed();if(decline)void load();}
  const context=()=>getContext();
  const pendingView=()=>'<main class="chat-guest"><a href="schedule.html#schedule">Back to Schedule Assistant</a><section><h1>Community features are coming soon.</h1><p>Chat, Q+A and account profiles are still being set up. Your schedule and school notices are available now.</p></section></main>';
  const alerts=createChatNotifications({storage,api:friendsApi,getUser:()=>context().session?.user,isViewingRoom:id=>section==='chat'&&model.chatMain!=='friends'&&model.activeConversationId===id&&!!document.querySelector('.chat-main-thread'),onUnread:counts=>{model.unreadCounts=counts;paintUnreadDots(model);if(typeof document!=='undefined')document.querySelectorAll('[data-room-unread]').forEach(el=>{const count=counts[el.dataset.roomUnread]||0;el.textContent=String(count);el.hidden=!count;});},onActivity:event=>{const token=generation;onAlert(event.mentioned?'Someone mentioned you in Chat.':'New message in another conversation.',{key:'message:'+event.room_id,actionLabel:'Open chat',onAction:()=>{if(token!==generation)return;model.activeConversationId=event.room_id;model.chatMain='thread';model.chatSpace=model.conversations.find(r=>r.id===event.room_id)?.kind==='school'?'campus':model.conversations.find(r=>r.id===event.room_id)?.kind==='class'?'school':'dms';onNavigate('chat');changed();void pollMessages();}});},onOpen:roomId=>{model.activeConversationId=roomId;storage.setItem?.(`school-chat-room:${context().session?.user.id}`,roomId);onNavigate('chat');if(section==='chat')void load();}});
  const developer=()=>context().membership?.active&&context().membership.role==='developer';
  const leader=()=>context().membership?.active&&['developer','principal'].includes(context().membership.role);
  const verified=()=>!!context().session?.user.email_confirmed_at;
  const assertCurrent=token=>{if(token!==generation)throw Error('Your account changed. Open this page again before saving.');};
  function requireAccount(){if(!api||!context().online)throw Error('Connect to the internet before posting.');if(!context().session)throw Error('Sign in to use this feature.');if(!verified())throw Error('Confirm your email before posting.');if(!model.profile)throw Error('Save your account profile first.');}
  function changed(){if(section==='chat'){if(model.success){onAlert(model.success);model.success='';}if(model.error&&model.error!==lastAlertError){onAlert(model.error,{tone:'error'});lastAlertError=model.error;}if(!model.error)lastAlertError='';}const modal=typeof document!=='undefined'&&document.querySelector('.profile-management-dialog');if(modal&&(model.profileModalOpen||model.spaceOnboardingOpen||needsSchoolInterests())){const save=modal.querySelector('.profile-primary');if(save&&modal.querySelector('form')?.dataset.sending!=='true')save.disabled=loading||!context().online;return;}onChange();}
  function reset(){generation++;onClearAlerts();messageRequest=null;lastMessageFetch=0;lastAlertError='';friendPollBusy=false;relationshipsReady=false;seenFriendStates=new Map();seenInvites=new Set();previews.clear();realtime.stop();applyTheme(readThemePreference()||'system');userId=context().session?.user.id||null;model=blank();model.activeConversationId=userId?storage.getItem(`school-chat-room:${userId}`):null;loading=false;mediaCache.clear();alerts.reset();}
  async function signed(rows) {
    const token=generation;
    const paths=[...new Set(rows.flatMap(p=>[p.avatar_path,p.banner_path,p.media_path,p.gif_path]).filter(Boolean))];
    if(!paths.length)return rows;
    const missing=paths.filter(path=>!mediaCache.has(path)||mediaCache.get(path).expires<Date.now());
    if(missing.length){const signed=await api.signMedia(missing);if(token!==generation)return rows;for(const [path,url] of Object.entries(signed))mediaCache.set(path,{url,expires:Date.now()+240000});}
    const urls=Object.fromEntries(paths.map(path=>[path,mediaCache.get(path)?.url]));
    return rows.map(row=>({...row,avatar_url:urls[row.avatar_path]||'',banner_url:urls[row.banner_path]||'',image_url:urls[row.media_path]||'',media_url:urls[row.media_path]||urls[row.gif_path]||''}));
  }
  async function load({quiet=false}={}) {
    if(!enabled)return;
    if(userId!==(context().session?.user.id||null))reset();
    const token=generation;
    if(!api){model.error='Community services are not configured.';changed();return;}
    if(!context().online){model.error='Chat and voting need an internet connection.';changed();return;}
    if(loading)return;
    loading=true;if(!quiet){model.loading=true;changed();}
    try {
      const site=section==='chat'?[]:await api.listPosts({scope:'site'});
      if(token!==generation)return;
      let spaceState=null;
      let own=null,profiles=[],rooms=[],emojis=[],classPosts=[],roomReviews=[],postReviews=[],emojiReviews=[],reports=[],userReports=[],classGroup=null,friendRows=[],blocks=[];
      if(verified()){
        model.admission=await spaceApi.admissionState();if(token!==generation)return;if(!model.admission.admitted){model.loaded=true;model.loading=false;model.error='';model.proposals=site.filter(p=>p.kind!=='announcement');model.announcements=site.filter(p=>p.kind==='announcement');changed();return;}
        own=await api.getProfile();
        if(token!==generation)return;
        if(!own&&context().name&&context().groups.includes(context().group)){
          await api.saveProfile({realName:context().name,displayName:'',audience:context().audience,classGroup:context().audience==='student'?context().group:null,bio:'',accent:'#512393',accentEnd:null,avatarPath:null,bannerPath:null});
          if(token!==generation)return;
          own=await api.getProfile();
        }
        [profiles,rooms,emojis,friendRows,blocks]=await Promise.all([api.listProfiles(),api.listRooms(),api.listEmojis(),friendsApi.listFriends(),friendsApi.listBlocks()]);
        friendRows=await signed(friendRows.map(f=>({...f,user_id:f.other_id,sender_id:f.requested_by})));
        classGroup=own?.class_group||null;
        const staff=context().membership;
        if(!classGroup&&staff?.active){const groups=staff.groups||[];classGroup=['developer','principal'].includes(staff.role)||groups.includes('*')||groups.includes(context().group)?context().group:groups[0]||null;}
        if(classGroup&&section!=='chat')classPosts=await api.listPosts({scope:'class',classGroup});
        if(developer()&&(section!=='chat'||model.chatPanel==='chat-access')){[model.admissionRequests,model.invites]=await Promise.all([spaceApi.listAdmissionRequests(),spaceApi.listInvites()]);}
        if(developer()&&(section!=='chat'||model.chatPanel==='moderation')){[postReviews,emojiReviews]=await Promise.all([api.listPendingPosts(),api.listPendingEmojis()]);reports=await signed(await api.listReports());userReports=await spaceApi.listUserReports();}
        try{spaceState=await spaceApi.getState();if(token!==generation)return;model.spaceSetupError='';if(spaceState?.server?.icon_path){const urls=await api.signMedia([spaceState.server.icon_path]);spaceState.server.icon_url=urls[spaceState.server.icon_path]||'';}if(own&&spaceState?.profile){own={...own,...spaceState.profile};applyTheme(spaceState.profile.theme,true);}if(spaceState?.members){spaceState.members=await signed(spaceState.members.map(p=>({...p,role:p.authority_role})));for(const member of spaceState.members){const found=profiles.findIndex(p=>p.user_id===member.user_id);if(found<0)profiles.push(member);else profiles[found]={...profiles[found],...member};}}}catch(error){model.spaceSetupError='Schoolwide chat is waiting for its database update.';}
        profiles=await signed(profiles||[]);
        if(own)own=(await signed([own]))[0];
        emojis=await signed(emojis||[]);
      }
      const announcements=site.filter(p=>p.kind==='announcement');
      if(token!==generation)return;
      const signedEmojiReviews=await signed(emojiReviews);
      if(token!==generation)return;
      const approvedRooms=rooms.filter(r=>r.status==='approved'&&!r.channel_archived&&(!r.my_consent||r.my_consent==='accepted'));
      const firstChatKey=`school-chat-first-entry:${userId}`;
      const welcomeRoom=approvedRooms.find(r=>r.kind==='school'&&r.school_channel==='welcome');
      const welcomeOnFirstLoad=own&&storage.getItem(firstChatKey)==='welcome'&&welcomeRoom;
      if(welcomeOnFirstLoad){model.chatSpace='campus';model.chatMain='thread';model.activeConversationId=welcomeRoom.id;}
      model={...model,spaceState,profile:own,classGroup,profiles,peers:profiles.filter(p=>p.user_id!==userId),friends:friendRows.filter(f=>f.status==='accepted'),friendRequests:friendRows.filter(f=>f.status==='pending'),blocks,conversations:approvedRooms,emojis,proposals:[...site,...classPosts].filter(p=>p.kind!=='announcement'),announcements,reports,userReports,reviewQueue:[...postReviews.map(p=>({...p,reviewType:'post'})),...roomReviews.map(r=>({...r,reviewType:'room'})),...signedEmojiReviews.map(e=>({...e,reviewType:'emoji'}))],joinRequests:rooms.filter(r=>r.status==='pending'||r.can_respond),emojiReviews,error:'',loaded:true,groups:context().groups};
      rememberRelationships(friendRows,rooms);
      if(model.chatSpace==='campus'){if(!approvedRooms.some(r=>r.id===model.activeConversationId&&r.kind==='school'))model.activeConversationId=approvedRooms.find(r=>r.kind==='school'&&r.school_channel==='general')?.id||approvedRooms.find(r=>r.kind==='school')?.id||null;}else if(model.chatSpace==='dms'){if(!approvedRooms.some(r=>r.id===model.activeConversationId&&['class','dm','group'].includes(r.kind)))model.activeConversationId=approvedRooms.find(r=>['class','dm','group'].includes(r.kind))?.id||null;}else if(!model.activeConversationId||!approvedRooms.some(r=>r.id===model.activeConversationId))model.activeConversationId=approvedRooms.find(r=>r.kind==='class'&&r.class_group===classGroup)?.id||approvedRooms.find(r=>r.kind==='class')?.id||approvedRooms[0]?.id||null;
      if(model.chatMain!=='friends'&&model.activeConversationId&&!(model.chatSpace==='campus'&&!model.activeConversationId))model.chatSpace=approvedRooms.find(r=>r.id===model.activeConversationId)?.kind==='school'?'campus':approvedRooms.find(r=>r.id===model.activeConversationId)?.kind==='class'?'school':'dms';
      if(verified()&&!own&&!model.profileModalOpen){model.profileModalOpen=true;model.profileEditTab='identity';model.profileEditDraft={user_id:userId,real_name:context().name||context().session?.user.user_metadata?.full_name||model.admission?.request?.name||'',audience:context().audience,class_group:context().group||context().groups[0],accent:'#512393'};}
      if(model.activeConversationId&&context().session){const roomId=model.activeConversationId;const messages=await signed(await api.messages(roomId));if(token!==generation)return;if(roomId===model.activeConversationId)model.messages=messages;}
      if(token===generation){if(welcomeOnFirstLoad)storage.setItem(firstChatKey,'');model.loading=false;loading=false;changed();if(section==='chat'&&model.chatSpace==='campus'&&spaceState?.profile?.space_onboarded)void pollPresence();}
    } catch(error){if(token===generation){model.error=/schema cache|does not exist|PGRST202/i.test(error.message)?'Community setup is still being installed. Try again shortly.':error.message;model.loading=false;loading=false;changed();}}
    finally{if(token===generation)loading=false;}
  }
  async function action(button) {
    if(!enabled)return;
    const token=generation;
    const action=button.dataset.communityAction,id=button.dataset.id,value=button.dataset.value;
    if(['reply-message','edit-message','delete-message','react-message'].includes(action)){
      requireAccount();const m=model.messages.find(m=>String(m.id)===String(id));if(!m||m.removed_at)throw Error('Message unavailable.');
      if(['edit-message','delete-message'].includes(action)&&m.author_id!==context().session.user.id)throw Error('You can only change your own messages.');
      if(action==='reply-message'){model.replyTo=id;model.replyRoom=model.activeConversationId;}
      if(action==='edit-message'){model.editingMessageId=id;model.editMentionBindings=Object.fromEntries((m.mentioned_ids||[]).map(user=>[mentionLabel(model,user),user]));model.editMessageDraft=editableMessage(m.body,model);}
      if(action==='delete-message')model.deletingMessageId=id;
      if(action==='react-message')model.reactingMessageId=id;
      changed();if(action==='reply-message')document.querySelector('#chat-shell-message')?.focus();if(action==='edit-message')document.querySelector('[data-community-form="message-edit"] textarea')?.focus();return;
    }
    if(action==='toggle-reaction'){await react(id,value,!model.messages.find(m=>String(m.id)===String(id))?.reactions?.find(r=>r.emoji===value)?.mine);return;}
    if(action==='cancel-edit'){model.editingMessageId=null;model.editMessageDraft='';changed();return;}
    if(action==='cancel-delete'){model.deletingMessageId=null;changed();return;}
    if(action==='cancel-reaction'){model.reactingMessageId=null;changed();return;}
    if(action==='cancel-reply'){model.replyTo=null;changed();document.querySelector('#chat-shell-message')?.focus();return;}
    if(action==='mention-person'){requireAccount();const room=model.activeConversationId;model.mentionPeople=await api.mentionDirectory(room);assertCurrent(token);if(room!==model.activeConversationId)return;model.mentionPickerOpen=true;model.mentionRoom=room;model.mentionQuery='';changed();document.querySelector('[data-mention-search]')?.focus();return;}
    if(action==='cancel-mention'){model.mentionPickerOpen=false;changed();return;}
    if(action==='insert-mention'){
      const input=document.querySelector('#chat-shell-message');if(!input||model.mentionRoom!==model.activeConversationId)return;
      if(value==='everyone'&&!developer())throw Error('Only Developers can mention everyone.');
      const current=Object.entries(model.mentionBindings||{}).filter(([name])=>input.value.includes('@'+name)).map(([,user])=>user);if(!developer()&&id&&current.some(user=>user!==id))throw Error('You can mention one person per message.');
      const name=id?mentionLabel(model,id):'everyone';if(id){model.mentionBindings||={};model.mentionBindings[name]=id;}const text=value==='everyone'?'@everyone ':`@${name} `;input.setRangeText(text,input.selectionStart,input.selectionEnd,'end');model.messageDraft=input.value;model.mentionPickerOpen=false;changed();document.querySelector('#chat-shell-message')?.focus();return;
    }
    if(action==='chat-auth-mode'){model.chatAuthMode=value;model.chatSignInOpen=true;changed();return;}
    if(action==='chat-access-settings'){if(!developer())throw Error('Developer access required.');model.chatPanel='chat-access';model.profileUserId=null;changed();return;}
    if(action==='create-chat-invite'){model.newInvite=await spaceApi.createInvite();model.invites=await spaceApi.listInvites();changed();return;}
    if(action==='revoke-chat-invite'){await spaceApi.revokeInvite(id);await load();return;}
    if(action==='review-chat-admission'){await spaceApi.reviewAdmission(id,value==='approve');await load();return;}
    if(action==='respond-conversation'){await api.respondRoom(id,value==='accept');if(value==='accept'){model.activeConversationId=id;model.chatSpace='dms';model.chatMain='thread';}model.success=value==='accept'?'Conversation request accepted.':'Conversation request declined.';await load();return;}
    if(action==='leave-conversation'){await api.leaveRoom(id);model.activeConversationId=null;model.messages=[];model.success='You left the conversation.';await load();return;}
    if(action==='discovery-optin'){await spaceApi.savePreferences({discovery_opt_in:true});await load();model.discoveries=await signed(await spaceApi.discover());changed();return;}
    if(action==='back-schedule'){onNavigate('schedule');return;}
    if(action==='leave-school-onboarding'){modalClose();return;}
    if(action==='close-profile-modal'){modalClose();return;}
    if(action==='profile-edit-tab'){model.profileEditTab=value;const modal=document.querySelector('.profile-management-dialog');modal?.querySelectorAll('[data-community-action="profile-edit-tab"]').forEach(b=>{const active=b.dataset.value===value;b.setAttribute('aria-current',String(active?'page':'false'));b.classList.toggle('active',active);});modal?.querySelectorAll('[data-profile-tab]').forEach(panel=>panel.hidden=panel.dataset.profileTab!==value);return;}
    if(action==='reset-profile-media'){previews.revoke(value);delete model.profileMediaPreviews?.[value];changed();return;}
    if(action==='school-preferences'){model.spaceOnboardingOpen=true;changed();return;}
    if(action==='school-staff'){model.chatPanel='school-staff';model.profileUserId=null;changed();return;}
    if(action==='report-user'){model.reportUserId=id;model.profileUserId=null;changed();return;}if(action==='review-user-report'){await spaceApi.reviewUserReport(id,value);await load();return;}if(action==='school-server-settings'){if(model.spaceState?.authority?.role!=='Developer')throw Error('Developer access is required to change server settings.');model.chatPanel='school-server-settings';model.profileUserId=null;model.editingChannelId=null;changed();return;}
    if(action==='edit-school-channel'||action==='new-school-channel'){if(model.spaceState?.authority?.role!=='Developer')throw Error('Developer access is required to change channels.');model.chatPanel='school-server-settings';model.profileUserId=null;model.editingChannelId=action==='edit-school-channel'?id:null;model.newChannelCategory=action==='new-school-channel'?value||'Conversation':'Conversation';changed();return;}
    if(action==='archive-school-channel'){if(model.spaceState?.authority?.role!=='Developer')throw Error('Developer access is required to change channels.');await spaceApi.setChannelArchived(id,value!=='restore');model.success=value==='restore'?'Channel restored.':'Channel archived. You can restore it from server settings.';await load();return;}
    if(action==='chat-space'&&value==='campus'){model.chatSpace='campus';model.chatMain='thread';model.chatPanel=null;model.profileUserId=null;model.activeConversationId=model.spaceState?.channels?.find(r=>!r.channel_archived&&r.school_channel==='welcome'&&needsSchoolInterests())?.id||model.spaceState?.channels?.find(r=>!r.channel_archived&&r.school_channel==='general')?.id||model.spaceState?.channels?.find(r=>!r.channel_archived)?.id||null;model.messages=[];changed();if(model.spaceState?.profile?.space_onboarded)await pollMessages();else await load();return;}
    if(action==='chat-space'&&value==='dms'){model.chatSpace='dms';model.chatMain='thread';model.chatPanel=null;model.profileUserId=null;model.activeConversationId=model.conversations.find(r=>r.id===model.activeConversationId&&['class','dm','group'].includes(r.kind))?.id||model.conversations.find(r=>['class','dm','group'].includes(r.kind))?.id||null;model.messages=[];changed();if(model.activeConversationId)await pollMessages();return;}
    if(action==='chat-space'){model.chatSpace=value;model.chatMain=value==='friends'?'friends':'thread';model.chatPanel=null;model.profileUserId=null;if(value==='school'){model.activeConversationId=model.conversations.find(r=>r.kind==='class'&&r.class_group===model.classGroup)?.id||model.conversations.find(r=>r.kind==='class')?.id||null;model.messages=[];changed();await pollMessages();}else changed();return;}
    if(action==='friends-view'){model.chatMain='friends';model.chatSpace='friends';changed();return;}
    if(action==='friend-tab'){if(value==='discovery'){model.discoveries=await signed(await spaceApi.discover());assertCurrent(token);}model.friendTab=value;model.chatMain='friends';model.chatSpace='friends';model.profileUserId=null;model.chatPanel=null;changed();return;}
    if(action==='chat-panel'){model.chatPanel=value||null;model.profileUserId=null;model.reportMessageId=null;model.reportUserId=null;changed();if(['moderation','chat-access'].includes(value))await load({quiet:true});return;}
    if(action==='chat-sidebar'){model.chatSidebarOpen=!model.chatSidebarOpen;changed();return;}
    if(action==='open-profile'){model.profileUserId=id;model.chatPanel=null;changed();return;}
    if(action==='clear-emoji'){model.selectedEmojiId=null;changed();return;}
    if(action==='request-notifications'){requireAccount();const enabled=await alerts.toggle();model.success=enabled?'Desktop notifications enabled.':'Desktop notifications off.';changed();return;}
    if(action==='open-friend-dm'){const room=model.conversations.find(r=>r.kind==='dm'&&r.participants?.includes(id));if(room){model.chatMain='thread';model.chatSpace='dms';model.activeConversationId=room.id;model.messages=[];alerts.markRead(room.id);changed();await pollMessages();}else{model.chatPanel='new-chat';model.newChatParticipants=[id];model.newChatKind='dm';model.newChatTitle=model.profiles.find(p=>p.user_id===id)?.display_name||'Direct message';changed();}return;}
    if(action==='section'){onNavigate(value);return;}
    if(action==='sign-in'||action==='login'){if(typeof location!=='undefined'&&location.pathname.endsWith('/chat.html')){model.chatSignInOpen=true;changed();return;}onNavigate('login');return;}
    if(action==='profile'||action==='edit-profile'){model.profileModalOpen=true;model.profileEditTab='identity';model.profileEditDraft={...model.profile};changed();return;}
    if(action==='scope'||action==='qa-scope'){model.qaScope=button.dataset.scope||value;changed();return;}
    if(action==='select-conversation'||action==='conversation'||action==='open-conversation'){const targetRoom=model.conversations.find(r=>r.id===id);model.chatSpace=targetRoom?.kind==='school'?'campus':targetRoom?.kind==='class'?'school':'dms';model.activeConversationId=id;model.chatMain='thread';model.chatSidebarOpen=false;model.messages=[];storage.setItem?.(`school-chat-room:${context().session?.user.id}`,id);alerts.markRead(id);changed();await pollMessages();return;}
    if(action==='select-proposal'||action==='proposal'||action==='open-proposal'){model.selectedProposalId=id;changed();return;}
    if(action==='refresh'){await load();return;}
    if(action==='insert-emoji'){model.selectedEmojiId=id;const input=document.querySelector('[data-community-form="message"] [name="body"]');if(input){const text=value||`:${button.dataset.name}:`;input.setRangeText(text,input.selectionStart,input.selectionEnd,'end');model.messageDraft=input.value;input.focus();}return;}
    if(action==='remove-gif'){model.savedGifs=model.savedGifs.filter(g=>g.url!==value);storage.setItem(GIF_KEY,JSON.stringify(model.savedGifs));changed();return;}
    if(action==='show-gif-form'){model.showGifForm=true;changed();return;}
    if(action==='show-emoji-form'){model.showEmojiForm=true;changed();return;}
    if(action==='cancel-report'){if(model.reportUserId)model.chatPanel=null;model.reportMessageId=null;model.reportUserId=null;changed();return;}
    if(action==='send-gif'){requireAccount();const roomId=model.activeConversationId;if(localGif(value)){const file=new File([await (await fetch(value)).blob()],'saved.gif',{type:'image/gif'});assertCurrent(token);const mediaPath=await api.uploadMedia(file,'chat');assertCurrent(token);if(roomId!==model.activeConversationId)throw Error('The conversation changed. Choose the GIF again.');await api.sendMessage({roomId,body:'',mediaPath});}else{const gif=safeGifURL(value);if(!gif)throw Error('Use a GIF link from media.tenor.com, media.giphy.com or i.giphy.com.');await api.sendMessage({roomId,body:'',gifUrl:gif});}assertCurrent(token);await load();return;}
    if(action==='use-gif'){model.selectedGif=safeGifURL(value);changed();return;}
    if(action==='clear-gif'){model.selectedGif='';changed();return;}
    requireAccount();
    button.disabled=true;
    try {
      if(action==='add-friend')await friendsApi.requestFriend(id);
      else if(action==='accept-friend'||action==='reject-friend')await friendsApi.respondFriend(id,action==='accept-friend');
      else if(action==='remove-friend')await friendsApi.removeFriend(id);
      else if(action==='block-user')await friendsApi.blockUser(id);
      else if(action==='unblock-user')await friendsApi.unblockUser(id);
      else if(action==='vote')await api.votePost(id,value==='yes');
      else if(action==='like')await api.likePost(id,!model.proposals.find(p=>p.id===id)?.my_like);
      else if(action==='review-room')await api.reviewRoom(id,value==='approve');
      else if(action==='review-proposal')await api.reviewPost(id,value==='approve');
      else if(action==='review-emoji')await api.reviewEmoji(id,value==='approve');
      else if(action==='approve'||action==='reject'){const kind=button.dataset.kind,approve=action==='approve';if(kind==='room')await api.reviewRoom(id,approve);else if(kind==='emoji')await api.reviewEmoji(id,approve);else await api.reviewPost(id,approve);}
      else if(action==='decision')await api.setDecision(id,value);
      else if(action==='moderate-report')await api.moderateReport(id,value==='remove');
      else if(action==='pause-user')await api.pauseUser(id,new Date(Date.now()+86400000).toISOString());
      else if(action==='kick-school-member'){await spaceApi.kickMember(id);}
      else if(action==='hide-message'&&model.conversations.find(r=>r.id===model.activeConversationId)?.kind==='school'){await spaceApi.removeMessage(id);}
      else if(action==='hide-message'){await api.reportMessage(id,'Moderator requested removal.');assertCurrent(token);const reports=await api.listReports();assertCurrent(token);const report=reports.find(r=>String(r.message_id)===String(id));if(report)await api.moderateReport(report.id,true);}
      else if(action==='report-message'){model.reportMessageId=id;changed();return;}
      else if(action==='load-older'){const roomId=model.activeConversationId;const older=await signed(await api.messages(roomId,model.messages[0]?.id));assertCurrent(token);if(roomId!==model.activeConversationId)return;const history=document.querySelector('[data-community-messages]'),height=history?.scrollHeight||0,top=history?.scrollTop||0;model.messages=[...older,...model.messages];changed();const updated=document.querySelector('[data-community-messages]');if(updated&&history&&older.length)updated.scrollTop=top+updated.scrollHeight-height;return;}
      else return;
      assertCurrent(token);if(action==='accept-friend')seenFriendStates.set(id,'accepted');model.success=({'add-friend':'Friend request sent.','accept-friend':'Friend request accepted.','reject-friend':'Friend request declined.','remove-friend':'Friend removed.','block-user':'User blocked.','unblock-user':'User unblocked.','hide-message':'Message removed.','kick-school-member':'Member removed from schoolwide chat.'})[action]||'Changes saved.';await load();
    } finally {button.disabled=false;}
  }
  async function submit(form) {
    if(!enabled)throw Error('Community features are not active yet.');
    const token=generation;
    const kind=form.dataset.communityForm,values=new FormData(form);
    const value=name=>String(values.get(name)||'').trim();
    if(kind==='gif'){
      let url=safeGifURL(value('url'));const file=values.get('gifFile');
      if(file?.size){if(file.type!=='image/gif'||file.size>1024*1024)throw Error('Choose a GIF under 1 MB to save on this browser.');const header=new TextDecoder().decode((await file.arrayBuffer()).slice(0,6));if(!['GIF87a','GIF89a'].includes(header))throw Error('This file is not a valid GIF.');url=await new Promise((resolve,reject)=>{const reader=new FileReader();reader.onload=()=>resolve(reader.result);reader.onerror=()=>reject(Error('The GIF could not be read.'));reader.readAsDataURL(file);});}
      if(!url)throw Error('Choose a GIF file or enter a direct Tenor/Giphy GIF link.');
      const next=[{url,name:value('name')||file?.name||'Saved GIF'},...model.savedGifs.filter(g=>g.url!==url)].slice(0,40);
      if(JSON.stringify(next).length>3000000)throw Error('Your GIF shelf is full. Remove a GIF before adding another.');
      if(storage.setItem(GIF_KEY,JSON.stringify(next))===false)throw Error('This browser could not save the GIF. Remove a saved GIF or free some browser storage.');
      model.savedGifs=next;changed();return;
    }
    if(kind==='chat-admission'||kind==='chat-invite'){if(!verified()||!context().online)throw Error('Confirm your email and connect first.');if(kind==='chat-admission')await spaceApi.requestAdmission(value('name'),value('note'));else await spaceApi.redeemInvite(value('token').trim());await load();return;}
    if(kind!=='profile')requireAccount();
    else {if(!api||!context().online||!verified())throw Error('Sign in with a verified account and connect before saving your profile.');}
    if(form.dataset.sending==='true')return;form.dataset.sending='true';const buttons=[...form.querySelectorAll('button')];buttons.forEach(b=>b.disabled=true);
    try {
      if(kind==='profile') {
        let avatarPath=values.has('remove_avatar')?null:model.profile?.avatar_path||null,bannerPath=values.has('remove_banner')?null:model.profile?.banner_path||null;
        for(const [name,mediaKind] of [['avatar','avatar'],['banner','banner']]){const file=values.get(name);if(file?.size){assertCurrent(token);const path=await api.uploadMedia(file,mediaKind);assertCurrent(token);if(name==='avatar')avatarPath=path;else bannerPath=path;}}
        assertCurrent(token);
        saveThemePreference(value('theme_preference')||'system');applyTheme(value('theme_preference')||'system');
        await spaceApi.saveProfile({realName:value('real_name'),displayName:value('display_name'),classGroup:context().audience==='student'?value('class_group')||null:null,audience:context().audience,bio:value('bio'),accent:value('accent')||'#512393',accentEnd:values.has('use_gradient')?value('accent_end')||null:null,avatarPath,bannerPath},{status_text:value('status_text'),status_emoji:value('status_emoji_id')?'':value('status_emoji'),status_emoji_id:value('status_emoji_id')||null,name_color:value('name_color')||'#512393',theme:value('theme_preference')||'system',cosmetic_roles:values.getAll('cosmetic_roles'),personal_tag:value('personal_tag').trim().slice(0,24),status_icon:value('status_icon')||null,featured_badge_id:value('featured_badge_id')||null,discovery_opt_in:values.has('discovery_opt_in')});
        assertCurrent(token);modalClose();
      } else if(kind==='message-edit'){await api.editMessage(value('message_id'),outgoingMessage(value('body'),model.editMentionBindings));assertCurrent(token);model.editingMessageId=null;model.editMessageDraft='';model.success='Message updated.';await pollMessages();changed();return;} else if(kind==='message-delete'){await api.deleteMessage(value('message_id'));assertCurrent(token);model.deletingMessageId=null;model.success='Message deleted.';await pollMessages();changed();return;} else if(kind==='message'){
        const body=outgoingMessage(value('body'),model.mentionBindings),replyTo=model.replyRoom===model.activeConversationId?model.replyTo:null,attachment=values.get('attachment'),roomId=model.activeConversationId,emojiId=model.selectedEmojiId||null,gifUrl=model.selectedGif||null;if(!body&&!gifUrl&&!emojiId&&!attachment?.size)throw Error('Write a message or choose a GIF.');
        let mediaPath=null;if(attachment?.size){mediaPath=await api.uploadMedia(attachment,'chat');assertCurrent(token);}
        if(roomId!==model.activeConversationId)throw Error('The conversation changed. Return to the original chat before sending this attachment.');await api.sendMessage({roomId,body,mediaPath,gifUrl,emojiId,replyTo});assertCurrent(token);model.messageDraft='';model.mentionBindings={};model.replyTo=null;model.selectedGif='';model.selectedEmojiId='';form.reset();model.error='';await pollMessages();changed();document.querySelector('#chat-shell-message')?.focus();return;
      } else if(kind==='space-onboarding'){const interests=values.getAll('cosmetic_roles');if(!interests.length||interests.length>4)throw Error('Choose one to four interests to enter Schoolwide Chat.');await spaceApi.savePreferences({cosmetic_roles:interests,name_color:value('name_color'),space_onboarded:true});model.spaceOnboardingOpen=false;}
      else if(kind==='school-moderator'){await spaceApi.assignModerator(value('user_id'),values.getAll('permissions'),values.getAll('permissions').length>0);}
      else if(kind==='school-server'){if(model.spaceState?.authority?.role!=='Developer')throw Error('Developer access is required to change server details.');const file=values.get('server_icon');let iconPath=values.has('remove_server_icon')?null:model.spaceState?.server?.icon_path||null;if(file?.size){iconPath=await api.uploadMedia(file,'server');assertCurrent(token);}await spaceApi.updateServer({name:value('name').trim(),description:value('description').trim(),iconKey:value('icon_key')||'school',iconPath,joinPolicy:value('join_policy')||null});}
      else if(kind==='school-rate'){await spaceApi.setRateLimit(values.has('enabled'),Number(value('message_limit')),Number(value('message_window_seconds')));}
      else if(kind==='user-report'){await spaceApi.reportUser(value('user_id'),value('category'),value('reason'));model.reportUserId=null;model.chatPanel=null;}
      else if(kind==='school-channel'){if(model.spaceState?.authority?.role!=='Developer')throw Error('Developer access is required to change channels.');const channelId=value('id')||null;await spaceApi.saveChannel({id:channelId,name:value('name').trim(),description:value('description').trim(),category:value('category').trim()||'Conversation',postingPolicy:value('posting_policy')||'members',speakingRoles:values.has('restrict_roles')?['Developer',...values.getAll('speaking_roles')]:null,slowmodeSeconds:Number(value('slowmode_seconds'))});model.editingChannelId=null;}
      else if(kind==='school-badge'){if(model.spaceState?.authority?.role!=='Developer')throw Error('Developer access is required to create badges.');await spaceApi.createBadge({name:value('name').trim(),description:value('description').trim(),iconKey:value('icon_key')||'award',color:value('color')||'#512393'});}
      else if(kind==='school-badge-award'){if(model.spaceState?.authority?.role!=='Developer')throw Error('Developer access is required to award badges.');await spaceApi.awardBadge(value('user_id'),value('badge_id'),true);}
      else if(kind==='conversation'){const kind=value('kind')==='group'?'group':'dm',participants=model.newChatParticipants||values.getAll('members');if(kind==='dm'&&participants.length!==1)throw Error('Choose one person to message.');const person=model.peers.find(p=>p.user_id===participants[0]);model.activeConversationId=await api.requestRoom({kind,title:kind==='dm'?(person?.display_name||person?.real_name||'Direct message'):value('title'),participants});model.chatPanel=null;model.chatMain='thread';model.chatSpace='dms';}
      else if(kind==='proposal')await api.createPost({scope:value('scope')||model.qaScope,title:value('title'),body:value('body'),target:value('target')||'student'});
      else if(kind==='announcement')await api.postDeveloperAnnouncement({title:value('title'),body:value('body'),target:value('target')||'all'});
      else if(kind==='emoji'){const file=values.get('image');if(!file?.size)throw Error('Choose an emoji image.');const mediaPath=await api.uploadMedia(file,'emoji');assertCurrent(token);await (model.chatSpace==='campus'?spaceApi:api).submitEmoji({name:value('name'),mediaPath});}
      else if(kind==='report')await api.reportMessage(value('messageId')||model.reportMessageId,value('reason'));
      else if(kind==='decision'){const decisions={'Not reviewed':'unreviewed','Planned':'planned','In progress':'yes','Implemented':'implemented','Not planned':'no'};await api.setDecision(value('id'),decisions[value('decision')]||value('decision'),value('note'));}
      assertCurrent(token);model.reportMessageId=null;model.success=kind==='conversation'?'Conversation created. Invited members can accept it from Messages.':kind==='user-report'?'Your report was sent privately to the Developer.':kind==='emoji'?'Your emoji was sent for Developer review.':kind==='proposal'&&model.qaScope==='site'?'Your suggestion was sent for Developer review.':'Saved.';
      await load();
    } finally{delete form.dataset.sending;buttons.forEach(b=>b.disabled=false);}
  }
  async function react(id,emoji,active=true){requireAccount();const token=generation;await api.reactMessage(id,emoji,active);assertCurrent(token);model.reactingMessageId=null;await pollMessages();changed();}
  async function pollMessages({fallback=false}={}){if(section!=='chat'||!context().session||!context().online||loading||!model.activeConversationId)return;if(fallback&&model.realtimeStatus==='live'&&Date.now()-lastMessageFetch<30000)return;const token=generation,roomId=model.activeConversationId,key=token+':'+roomId;if(messageRequest?.key===key){messageRequest.again=true;return;}const request={key,again:false};messageRequest=request;try{const messages=await signed(await api.messages(roomId));if(token!==generation||roomId!==model.activeConversationId)return;lastMessageFetch=Date.now();if(JSON.stringify(messages)!==JSON.stringify(model.messages)){model.messages=messages;const history=document.querySelector('[data-community-messages]');if(history){const top=history.scrollTop,atEnd=history.scrollHeight-top-history.clientHeight<100;history.innerHTML=renderMessageList({model,session:context().session,membership:context().membership,roomId});paintIcons();history.scrollTop=atEnd?history.scrollHeight:top;}else changed();}}catch(error){if(token===generation&&roomId===model.activeConversationId&&error.code==='42501'){model.messages=[];model.error=error.message;changed();}}finally{if(messageRequest===request)messageRequest=null;if(request.again&&token===generation&&roomId===model.activeConversationId)void pollMessages();}}
  function rememberRelationships(friends,rooms){
    if(!relationshipsReady){seenFriendStates=new Map(friends.map(f=>[f.id,f.status]));seenInvites=new Set(rooms.filter(r=>r.can_respond).map(r=>r.id));relationshipsReady=true;return;}
    const token=generation;
    const openRequests=()=>{if(token!==generation)return;model.chatSpace='friends';model.chatMain='friends';model.friendTab='pending';model.chatPanel=null;onNavigate('chat');changed();};
    for(const friend of friends){const previous=seenFriendStates.get(friend.id);if(friend.status==='pending'&&friend.requested_by!==userId&&previous!=='pending')onAlert(`${friend.display_name||'A school member'} sent you a friend request.`,{key:'friend:'+friend.id,actionLabel:'View requests',onAction:openRequests});if(friend.status==='accepted'&&previous==='pending')onAlert('Friend request accepted.',{key:'accepted:'+friend.id});}
    for(const room of rooms){if(room.can_respond&&!seenInvites.has(room.id))onAlert('You have a new conversation request.',{key:'invite:'+room.id,actionLabel:'View requests',onAction:()=>{if(token!==generation)return;model.chatSpace='dms';model.chatMain='thread';onNavigate('chat');changed();}});}
    seenFriendStates=new Map(friends.map(f=>[f.id,f.status]));seenInvites=new Set(rooms.filter(r=>r.can_respond).map(r=>r.id));
  }
  async function pollRelationships(){
    if(friendPollBusy||loading||!verified()||!model.loaded||typeof document!=='undefined'&&document.visibilityState!=='visible')return;
    const token=generation;friendPollBusy=true;
    try{const [friends,rooms]=await Promise.all([friendsApi.listFriends(),api.listRooms()]);if(token!==generation)return;rememberRelationships(friends,rooms);const before=JSON.stringify([model.friendRequests.map(f=>[f.id,f.status]),model.joinRequests.map(r=>[r.id,r.my_consent])]);const rows=await signed(friends.map(f=>({...f,user_id:f.other_id,sender_id:f.requested_by})));if(token!==generation)return;model.friends=rows.filter(f=>f.status==='accepted');model.friendRequests=rows.filter(f=>f.status==='pending');model.joinRequests=rooms.filter(r=>r.status==='pending'||r.can_respond);paintUnreadDots(model);model.conversations=rooms.filter(r=>r.status==='approved'&&!r.channel_archived&&(!r.my_consent||r.my_consent==='accepted'));if(before!==JSON.stringify([model.friendRequests.map(f=>[f.id,f.status]),model.joinRequests.map(r=>[r.id,r.my_consent])])){if(model.chatMain==='friends')changed();else{const sidebar=typeof document!=='undefined'&&document.querySelector('.chat-sidebar');if(sidebar){sidebar.outerHTML=renderChatSidebar(model,context().session);paintIcons();}}}
    }catch{}finally{if(token===generation)friendPollBusy=false;}
  }
  async function pollPresence(){if(section!=='chat'||model.chatSpace!=='campus'||!context().online||!verified()||typeof document!=='undefined'&&document.visibilityState!=='visible')return;const token=generation;try{await spaceApi.heartbeat();const members=await signed(await spaceApi.listMembers());if(token!==generation)return;model.spaceState={...model.spaceState,members:members.map(p=>({...p,role:p.authority_role}))};const panel=document.querySelector('.campus-members');if(panel){if(token!==generation)return;panel.outerHTML=renderSchoolMembers(model);}}catch{}}
  return {
    get model(){return model;}, reset,load,action,submit,react,closeModal:modalClose,applyThemePreference(){applyTheme(accountTheme);},
    async syncPreferences(){if(!enabled)return;if(userId!==(context().session?.user.id||null))reset();const token=generation;try{const state=await spaceApi?.getState();if(token===generation&&state?.profile)applyTheme(state.profile.theme,true);}catch{}},
    async change(target){const token=generation;if(target.closest('[data-community-form="conversation"]')&&target.name==='members'){if(target.type==='radio')model.newChatParticipants=[target.value];else{const selected=new Set(model.newChatParticipants||[]);if(target.checked)selected.add(target.value);else selected.delete(target.value);model.newChatParticipants=[...selected];}return;}if(target.closest('[data-community-form="conversation"]')&&target.name==='kind'){model.newChatKind=target.value;model.newChatParticipants=[];changed();return;}if(target.name==='status_emoji_id'&&target.value){target.form.querySelector('[name="status_icon"]').value='';target.form.querySelector('[name="status_emoji"]').value='';}if(target.name==='attachment'){const label=target.closest('form')?.querySelector('[data-attachment-name]');if(label)label.textContent=target.files?.[0]?.name||'';}if(target.closest('[data-community-form="profile"]')){const form=target.form;if(['avatar','banner'].includes(target.name)&&target.files?.[0]){try{model.profileMediaPreviews||={};const url=await previews.update(target.files[0],target.name);if(token!==generation||!url)return;model.profileMediaPreviews[target.name]=url;}catch(error){target.value='';previews.revoke(target.name);delete model.profileMediaPreviews[target.name];const modal=target.closest('.profile-management-dialog');if(modal){let feedback=modal.querySelector('.profile-modal-feedback');if(!feedback){feedback=document.createElement('p');feedback.className='profile-modal-feedback';feedback.setAttribute('role','alert');modal.querySelector('form').before(feedback);}feedback.textContent=error.message;model.profileEditDraft=updateProfilePreview(modal,form,model);}return;}}const root=target.closest('.profile-management-dialog');if(root)model.profileEditDraft=updateProfilePreview(root,form,model);}},
    pollPresence,
    render(nextSection){section=nextSection;if(!enabled)return section==='chat'?pendingView():'<section class="section"><h2>Community features are coming soon.</h2><p>Chat, Q+A and profiles are still being set up. Your schedule and school notices are available now.</p></section>';model.groups=context().groups;model.defaultName=context().name;model.defaultAudience=context().audience;model.defaultGroup=context().group;Object.assign(model,alerts.state());const args={section,model,session:context().session,membership:context().membership,group:model.classGroup||context().group,busy:loading,online:context().online};realtime.watch(section==='chat'&&verified()?context().session?.user.id:null,section==='chat'?model.activeConversationId:null);return section==='chat'&&verified()&&model.admission&&!model.admission.admitted?renderChatAdmission(model):section==='chat'?renderChatShell(args):renderCommunity(args)+(model.profileModalOpen?renderProfileModal(args):'');},
    enter(nextSection){section=nextSection;void load();},
    input(target){if(target.hasAttribute('data-conversation-search')){model.conversationSearch=target.value;const form=target.closest('form');form.querySelector('[data-conversation-people]').innerHTML=renderConversationPeople(model);return;}if(target.matches('[data-community-form="message-edit"] [name="body"]'))model.editMessageDraft=target.value;if(target.hasAttribute('data-mention-search')){model.mentionQuery=target.value;const query=target.value.toLowerCase();target.closest('.chat-mention-picker').querySelectorAll('[data-community-action="insert-mention"]').forEach(b=>b.hidden=!b.textContent.toLowerCase().includes(query));}if(target.closest('[data-community-form="profile"]')){if(target.name==='status_emoji'&&target.value){target.form.querySelector('[name="status_icon"]').value='';target.form.querySelector('[name="status_emoji_id"]').value='';}const modal=target.closest('.profile-management-dialog');if(modal)model.profileEditDraft=updateProfilePreview(modal,target.form,model);}if(target.matches('[data-community-form="message"] [name="body"]'))model.messageDraft=target.value;if(target.hasAttribute('data-chat-search')||target.hasAttribute('data-friend-search')){const kind=target.hasAttribute('data-chat-search')?'chat':'friend',value=target.value.toLowerCase();model[kind==='chat'?'chatSearch':'friendSearch']=target.value;document.querySelectorAll(`[data-search-kind="${kind}"]`).forEach(el=>el.hidden=!el.dataset.searchable.includes(value));}},
    async pollNotifications(){if(!enabled)return;if(!context().session||!context().online)return;if(section==='chat'||alerts.enabled())await Promise.all([alerts.refresh(),section==='chat'?pollRelationships():Promise.resolve()]);},
    poll:()=>pollMessages({fallback:true}),
  };
}
