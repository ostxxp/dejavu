import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';

function harness(parts) {
 const jobs=new Map(),highlights=new Map();let serial=0,mutation;
 class Element {
  constructor(){this.events={};this.children=[];this.style={setProperty(){}};}
  setAttribute(){} append(...nodes){for(const node of nodes){node.parentElement=this;this.children.push(node)}}
  remove(){if(this.parentElement)this.parentElement.children=this.parentElement.children.filter(n=>n!==this)}
  addEventListener(name,fn){this.events[name]=fn} attachShadow(){return this.shadow=new Element()}
 }
 const blocks=new Map();
 const nodes=parts.map(({text,block='p',excluded=false})=>{
  if(!blocks.has(block))blocks.set(block,{});
  return {textContent:text,isConnected:true,parentElement:{closest:s=>s.startsWith('input')?(excluded?{}:null):blocks.get(block)}};
 });
 const document=new Element();document.body=new Element();document.documentElement=new Element();
 document.createElement=()=>new Element();
 document.createTreeWalker=()=>{let i=0;return {nextNode:()=>nodes[i++]}};
 document.createRange=()=>({setStart(node,offset){this.startContainer=node;this.startOffset=offset},setEnd(node,offset){this.endContainer=node;this.endOffset=offset},getClientRects:()=>[{left:0,top:0,right:100,bottom:20,width:100,height:20}]});
 const window=new Element();window.getSelection=()=>({isCollapsed:true});
 const context={document,window,CSS:{highlights},Highlight:class{constructor(...ranges){this.ranges=ranges}},crypto:{randomUUID:()=> 'test'},NodeFilter:{SHOW_TEXT:4},
  MutationObserver:class{constructor(fn){mutation=fn}observe(){}disconnect(){}},
  setTimeout:fn=>{jobs.set(++serial,fn);return serial},clearTimeout:id=>jobs.delete(id)};
 vm.createContext(context);
 for(const name of ['recognition-policy.js','recognition.js'])vm.runInContext(readFileSync(new URL('../'+name,import.meta.url),'utf8'),context);
 const engine=context.createDejavuRecognition({onMatch(){}});
 const flush=()=>{for(let count=0;jobs.size&&count<100;count++){const [id,fn]=jobs.entries().next().value;jobs.delete(id);fn()}assert.equal(jobs.size,0)};
 const start=()=>engine.start([{id:'one',french:'tu devrais'}],{accent:'#123456',soft:'#eeeeee',ink:'#111111'});
 return {engine,start,flush,highlights,document,jobs,mutation:()=>mutation()};
}
test('Scanner spans inline text but never joins excluded controls or separate blocks',()=>{
 const h=harness([{text:'tu'},{text:' '},{text:'devrais'},{text:'tu ',block:'second'},{text:'secret',block:'second',excluded:true},{text:'devrais',block:'second'},{text:'tu ',block:'third'},{text:'devrais',block:'fourth'}]);
 h.start();h.flush();assert.equal([...h.highlights.values()][0].ranges.length,1);
 assert.ok(h.document.documentElement.children.some(e=>e.shadow));
 h.engine.stop();assert.equal(h.highlights.size,0);assert.equal(h.document.documentElement.children.length,0);
});
test('Scanner cancels pending scans and coalesces mutations without a continuous loop',()=>{
 const h=harness([{text:'tu devrais'}]);h.start();h.engine.stop();h.flush();assert.equal(h.highlights.size,0);
 h.start();h.flush();for(let i=0;i<100;i++)h.mutation();assert.equal(h.jobs.size,1);h.flush();assert.equal(h.highlights.size,1);
 h.document.hidden=true;h.document.events.visibilitychange();assert.equal(h.highlights.size,0);
 h.document.hidden=false;h.document.events.visibilitychange();h.flush();assert.equal(h.highlights.size,1);
 h.engine.stop();
});
