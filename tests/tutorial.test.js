import test from 'node:test';
import assert from 'node:assert/strict';
import {guides} from '../src/tutorial.js';
import {createCommunityController} from '../src/community-controller.js';
test('first-use guides stay short and cover each primary section',()=>{for(const area of ['launch','schedule','chat','qa','profile','calendar','updates']){assert.ok(guides[area]);assert.ok(guides[area].steps.length<=3);for(const [title,body] of guides[area].steps){assert.ok(title.length<60);assert.ok(body.length<230);}}});
test('inactive community release never calls services or exposes posting forms',async()=>{let calls=0;const controller=createCommunityController({enabled:false,client:{rpc:async()=>{calls++;return {data:[],error:null};},storage:{}},storage:{getItem:()=>null},getContext:()=>({}),onChange:()=>{},onNavigate:()=>{}});await controller.load();await controller.syncPreferences();await controller.action({dataset:{communityAction:'profile'}});assert.equal(calls,0);const html=controller.render('chat');assert.ok(html.includes('coming soon'));assert.ok(!html.includes('data-community-form'));await assert.rejects(()=>controller.submit({}),/not active/);});
