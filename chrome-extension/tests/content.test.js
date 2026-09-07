import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';

// Minimal DOM doubles exercise the real content-script lifecycle, not AI output.
function harness() {
 const frames=new Map(), timers=new Map(), messages=[], highlights=new Map();
 let sequence=0, observer, receiver, geometry={left:100,right:210,top:300,bottom:325,width:110,height:25};
 class Element {
  constructor(tag='div') {this.tag=tag;this.nodeType=1;this.children=[];this.events={};this.style={setProperty(k,v){this[k]=v}};this.isConnected=false;this.className='';this.offsetWidth=400;this.offsetHeight=240;this.classList={contains:n=>this.className.split(' ').includes(n),add:n=>{this.className+=' '+n}};}
  setAttribute(){} append(...nodes){for(const n of nodes){n.parentElement=this;n.isConnected=true;this.children.push(n)}}
  remove(){if(this.parentElement)this.parentElement.children=this.parentElement.children.filter(n=>n!==this)}
  addEventListener(type,callback){(this.events[type]??=[]).push(callback)}
  fire(type,event={}){for(const f of this.events[type]??[])f(event)}
  attachShadow(){return this.shadow=new Element('shadow')}
  closest(){return null} querySelector(){return null}
  getBoundingClientRect(){return geometry}
 }
 const document=new Element('document');document.documentElement=new Element('html');document.body=new Element('body');document.documentElement.append(document.body);
 document.createElement=tag=>new Element(tag);
 const parent=new Element('p');document.body.append(parent);
 const node={nodeType:3,parentElement:parent,isConnected:true};
 const range={startContainer:node,endContainer:node,commonAncestorContainer:node,startOffset:0,endOffset:10,collapsed:false,cloneContents:()=>new Element(),cloneRange(){return {...this}},getClientRects:()=>[geometry]};
 const selection={anchorNode:node,focusNode:node,isCollapsed:false,rangeCount:1,getRangeAt:()=>range,toString:()=> 'tu devrais'};
 const window=new Element('window');window.top=window;window.getSelection=()=>selection;
 const context={window,document,Node:{ELEMENT_NODE:1},CSS:{highlights},Highlight:class{},crypto:{randomUUID:()=>String(++sequence)},
 chrome:{runtime:{sendMessage:async message=>{messages.push(message);return message.type==='CONFIG'?{ok:true,enabled:true,accent:'lavender'}:{ok:true,candidate:true}},onMessage:{addListener:f=>{receiver=f}}}},
 ResizeObserver:class {constructor(f){observer=f}observe(){}disconnect(){}},getComputedStyle:()=>({overflow:'visible',overflowX:'visible',overflowY:'visible'}),
 innerWidth:1000,innerHeight:800,setTimeout:f=>{const id=++sequence;timers.set(id,f);return id},clearTimeout:id=>timers.delete(id),requestAnimationFrame:f=>{const id=++sequence;frames.set(id,f);return id},cancelAnimationFrame:id=>frames.delete(id)};
 vm.createContext(context);
 for(const file of ['presentation.js','content.js'])vm.runInContext(readFileSync(new URL('../'+file,import.meta.url),'utf8'),context);
 const flush=async()=>{await Promise.resolve();for(const [id,f] of [...timers]){timers.delete(id);await f()}await Promise.resolve()};
 return {document,window,node,range,frames,highlights,messages,receiver:message=>receiver(message),observer:()=>observer(),flush,
  geometry:value=>{geometry={...geometry,...value}},host:()=>document.documentElement.children.find(n=>n.shadow),
  frame:()=>{for(const [id,f] of [...frames]){frames.delete(id);f()}}};
}
test('Selection stays anchored during scroll, batches frames, restores after leaving viewport, and cleans up',async()=>{
 const h=harness();await h.flush();h.document.fire('selectionchange');await h.flush();
 const host=h.host();assert.ok(host);assert.equal(h.highlights.size,1);assert.equal(host.style.top,'335px');
 h.geometry({top:200,bottom:225});for(let i=0;i<50;i++)h.window.fire('scroll');
 assert.equal(h.frames.size,1);h.frame();assert.equal(host.style.top,'235px');
 h.geometry({top:-60,bottom:-35});h.window.fire('scroll');h.frame();assert.equal(host.style.visibility,'hidden');
 h.geometry({top:200,bottom:225});h.window.fire('scroll');h.frame();assert.equal(host.style.visibility,'visible');
 h.document.fire('keydown',{key:'Escape'});assert.equal(h.highlights.size,0);assert.equal(host.style.display,'none');assert.equal(h.frames.size,0);
 assert.equal(h.messages.filter(m=>m.type==='ANALYZE').length,0);
});
test('Theme changes recolor open highlight; detached text cannot leave an orphan popup',async()=>{
 const h=harness();await h.flush();h.document.fire('selectionchange');await h.flush();
 const host=h.host();h.receiver({type:'APPEARANCE_CHANGED',accent:'rose'});assert.equal(host.style['--accent'],'#b5486e');assert.equal(h.highlights.size,1);
 h.node.isConnected=false;h.observer();h.frame();assert.equal(host.style.display,'none');assert.equal(h.highlights.size,0);
});
