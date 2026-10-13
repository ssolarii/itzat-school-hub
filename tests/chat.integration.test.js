import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const enabled=process.env.ISA_INTEGRATION==='1',cfg=JSON.parse(readFileSync(new URL('../school-config.json',import.meta.url),'utf8'));
const request=(path,body)=>fetch(cfg.url+path,{method:body?'POST':'GET',headers:{apikey:cfg.publishableKey,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined,signal:AbortSignal.timeout(10000)});
test('live guests can read approved site posts but cannot read chat profiles or messages',{skip:!enabled},async()=>{assert.equal((await request('/rest/v1/rpc/community_list_posts',{p_scope:'site',p_class_group:null,p_pending:false})).status,200);for(const path of ['/rest/v1/community_profiles?select=user_id','/rest/v1/community_messages?select=id,body'])assert.ok([401,403].includes((await request(path)).status));});
test('live anonymous accounts cannot redeem invites, join chats or read admissions',{skip:!enabled},async()=>{for(const [rpc,body] of [['community_admission_state',{}],['community_list_rooms',{p_pending:false}],['community_admission_requests',{}]])assert.ok([401,403].includes((await request('/rest/v1/rpc/'+rpc,body)).status));});
