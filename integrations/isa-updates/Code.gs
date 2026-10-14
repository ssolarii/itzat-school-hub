/** ISA Updates -> private Supabase notice drafts. Never place a service-role key here. */
function isaConfig_() {
  const p=PropertiesService.getScriptProperties();
  const config={courseId:p.getProperty('ISA_COURSE_ID'),url:p.getProperty('SUPABASE_URL'),key:p.getProperty('SUPABASE_PUBLISHABLE_KEY'),token:p.getProperty('ISA_SYNC_TOKEN')};
  if(!config.courseId||!config.url||!config.key||!config.token)throw new Error('Set the four required Script Properties first.');
  if(!/^https:\/\/[a-z0-9]+\.supabase\.co$/.test(config.url)||!/^\d+$/.test(config.courseId))throw new Error('Use the Supabase project URL and numeric Classroom course ID.');
  if(config.key.startsWith('sb_secret_'))throw new Error('Use a publishable key, never a secret or service-role key.');
  if(config.key.split('.').length===3){const payload=JSON.parse(Utilities.newBlob(Utilities.base64DecodeWebSafe(config.key.split('.')[1])).getDataAsString());if(payload.role!=='anon')throw new Error('Only a public anon key is allowed.');}else if(!config.key.startsWith('sb_publishable_'))throw new Error('Use the Supabase publishable key.');
  return config;
}
function findISAUpdatesCourse() {
  let pageToken;const matches=[];
  do {const page=Classroom.Courses.list({pageSize:100,pageToken:pageToken});(page.courses||[]).filter(c=>c.name.toLowerCase().trim()==='isa updates').forEach(c=>matches.push({name:c.name,id:c.id}));pageToken=page.nextPageToken;} while(pageToken);
  console.log(JSON.stringify(matches));return matches;
}
function isaPost_(post) {
  const text=String(post.text||'').trim(),link=String(post.alternateLink||'');
  if(link&&!/^https:\/\/classroom\.google\.com\//.test(link))throw new Error('Unexpected Classroom link.');
  const body=(text||'An announcement with attachments was shared in Classroom.')+(link?'\n\nOriginal Classroom post: '+link:'');
  if(body.length>10000)throw new Error('A Classroom post exceeds the notice limit; review it manually before continuing.');
  return {id:String(post.id),updated_at:post.updateTime||post.creationTime,title:(text.split('\n').find(line=>line.trim())||'ISA Updates').slice(0,160),body:body};
}
function isaRead_(config,cutoff) {
  let pageToken,finished=false,pages=0;const items=[];
  do {
    const page=Classroom.Courses.Announcements.list(config.courseId,{pageSize:100,orderBy:'updateTime desc',announcementStates:['PUBLISHED'],pageToken:pageToken});
    for(const post of page.announcements||[]){const updated=Date.parse(post.updateTime||post.creationTime);if(!Number.isFinite(updated))throw new Error('A post has no valid update time.');if(updated<cutoff){finished=true;break;}items.push(isaPost_(post));}
    pageToken=page.nextPageToken;pages++;
    if(pages>=50&&pageToken&&!finished)throw new Error('Too many pages. Reduce the initial lookback or import older posts separately.');
  } while(pageToken&&!finished);
  return items;
}
function previewISAUpdates() {
  const config=isaConfig_(),items=isaRead_(config,Date.now()-30*86400000);
  // Preview never logs post text, tokens, account identities or attachments.
  console.log(JSON.stringify({courseId:config.courseId,posts:items.length,willPublishPublicly:false}));return items.length;
}
function isaSend_(config,items) {
  for(let attempt=0;attempt<4;attempt++) {
    const response=UrlFetchApp.fetch(config.url+'/rest/v1/rpc/import_isa_updates',{method:'post',contentType:'application/json',headers:{apikey:config.key},payload:JSON.stringify({p_token:config.token,p_course:config.courseId,p_items:items}),muteHttpExceptions:true});
    const status=response.getResponseCode();
    if(status>=200&&status<300)return JSON.parse(response.getContentText());
    if([408,429,500,502,503,504].includes(status)&&attempt<3){Utilities.sleep(1000*Math.pow(2,attempt));continue;}
    throw new Error('Supabase import failed (HTTP '+status+'). The sync cursor was not advanced.');
  }
}
function syncISAUpdates() {
  const lock=LockService.getScriptLock();if(!lock.tryLock(1000))return;
  try {
    const config=isaConfig_(),properties=PropertiesService.getScriptProperties(),started=Date.now(),cursorKey='ISA_LAST_SUCCESS:'+config.courseId;
    const previous=Date.parse(properties.getProperty(cursorKey)||'');
    const cutoff=Number.isFinite(previous)?previous-5*60000:started-30*86400000;
    const items=isaRead_(config,cutoff);let imported=0;
    for(let offset=0;offset<items.length;offset+=50){const result=isaSend_(config,items.slice(offset,offset+50));imported+=Number(result.imported||0);}
    properties.setProperty(cursorKey,new Date(started).toISOString());
    console.log(JSON.stringify({postsSeen:items.length,draftsImported:imported,lastSuccess:new Date(started).toISOString()}));
  } finally {lock.releaseLock();}
}
function installISASyncTrigger() {
  isaConfig_();
  ScriptApp.getProjectTriggers().filter(t=>t.getHandlerFunction()==='syncISAUpdates').forEach(t=>ScriptApp.deleteTrigger(t));
  ScriptApp.newTrigger('syncISAUpdates').timeBased().everyMinutes(5).create();
}
function stopISASyncTrigger() {ScriptApp.getProjectTriggers().filter(t=>t.getHandlerFunction()==='syncISAUpdates').forEach(t=>ScriptApp.deleteTrigger(t));}
