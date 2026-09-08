import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
function popup(saved) {
 const nodes=new Map(),health=[];
 class Element {
  constructor(){this.children=[];this.dataset={};this.style={setProperty(){}};this.events={};this.checked=false;this.value='';}
  append(...items){this.children.push(...items)} setAttribute(){} addEventListener(name,fn){this.events[name]=fn}
 }
 const get=id=>{if(!nodes.has(id))nodes.set(id,new Element());return nodes.get(id)};
 const context={document:{getElementById:get,createElement:()=>new Element(),createTextNode:t=>t,documentElement:new Element()},window:{addEventListener(){}},URL,
 chrome:{runtime:{id:'example',sendMessage:async m=>{
  if(m.type==='PREFERENCES')return {ok:true,enabled:true,recognitionEnabled:saved.enabled,accent:'rose',blockedDomains:[],extensionID:'example'};
  if(m.type==='STATUS'){const old=saved.enabled;return new Promise(resolve=>health.push(()=>resolve({ok:true,connected:true,detail:'Подключено',enabled:true,recognitionEnabled:old,accent:'rose',blockedDomains:[]})))}
  if(m.type==='SET_RECOGNITION'){saved.enabled=m.enabled;return {ok:true}}
 }},tabs:{query:async()=>[]}}};
 vm.createContext(context);
 for(const file of ['presentation.js','popup.js'])vm.runInContext(readFileSync(new URL('../'+file,import.meta.url),'utf8'),context);
 return {get,health,flush:async()=>{for(let i=0;i<12;i++)await Promise.resolve()}};
}
test('Recognition survives delayed health replies and reopening the popup',async()=>{
 const saved={enabled:false},first=popup(saved);await first.flush();
 assert.equal(first.get('recognition').checked,false);
 first.get('recognition').checked=true;await first.get('recognition').events.change();
 assert.equal(saved.enabled,true);
 first.health.shift()();await first.flush();
 assert.equal(first.get('recognition').checked,true);
 const reopened=popup(saved);await reopened.flush();
 assert.equal(reopened.get('recognition').checked,true); // Does not wait for Mac health.
 reopened.get('recognition').checked=false;await reopened.get('recognition').events.change();
 reopened.health.shift()();await reopened.flush();assert.equal(reopened.get('recognition').checked,false);
 assert.equal(saved.enabled,false);
});
