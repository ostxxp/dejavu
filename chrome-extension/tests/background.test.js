import test from 'node:test';
import assert from 'node:assert/strict';
const id='a'.repeat(32), code='0'.repeat(64), documentId='example-document';
let sequence=0;
const analysis={original:'tu devrais',translation:'тебе стоит',grammar:[],chunks:[],examples:[]};
async function harness(){
 const local={pairingCode:code},session={},calls=[],levels=[];
 let listener;
 const area=data=>({setAccessLevel:async v=>{levels.push(v.accessLevel)},get:async keys=>Object.fromEntries((Array.isArray(keys)?keys:[keys]).filter(k=>k in data).map(k=>[k,data[k]])),set:async v=>Object.assign(data,v),remove:async key=>{delete data[key]}});
 globalThis.chrome={storage:{local:area(local),session:area(session)},runtime:{id,getURL:p=>`chrome-extension://${id}/${p}`,onMessage:{addListener:f=>{listener=f}}},
 tabs:{query:async()=>[],sendMessage:async()=>{},onRemoved:{addListener:()=>{}}},i18n:{detectLanguage:async()=>({languages:[{language:'fr',percentage:99}]})},
 tts:{getVoices:async()=>[{voiceName:'French',lang:'fr-FR',remote:false}],stop:()=>{},speak:async()=>{}}};
 globalThis.fetch=async(url,options)=>{calls.push({url,options});return new Response(JSON.stringify(url.endsWith('health')?{status:'ok'}:url.endsWith('analyze')?{id:'example-analysis-id',analysis,fromCache:false}:{saved:true}),{status:200})};
 await import(`../background.js?test=${sequence++}`);
 const popup={id,url:`chrome-extension://${id}/popup.html`};
 const page={id,url:'https://french.example/article',tab:{id:1},frameId:0,documentId};
 const send=(message,sender=page)=>new Promise(resolve=>listener(message,sender,resolve));
 return {local,session,calls,levels,popup,page,send};
}
test('Content cannot obtain the pairing code or change configuration',async()=>{
 const h=await harness();
 for(const type of ['STATUS','PREFERENCES','PAIR','SET_ENABLED','SET_DOMAINS','DISCONNECT'])assert.equal((await h.send({type,code,enabled:false,domains:[]})).ok,false);
 const config=await h.send({type:'CONFIG'});assert.equal(config.ok,true);assert.ok(!JSON.stringify(config).includes(code));
 assert.deepEqual(h.levels,['TRUSTED_CONTEXTS','TRUSTED_CONTEXTS']);assert.equal(h.calls.length,0);
});
test('Only selection click action requests AI; results are bound to their document',async()=>{
 const h=await harness();
 assert.equal((await h.send({type:'CANDIDATE',text:'tu devrais'})).candidate,true);assert.equal(h.calls.length,0);
 const result=await h.send({type:'ANALYZE',text:'tu devrais',requestID:'one'});assert.equal(result.ok,true);
 assert.deepEqual(JSON.parse(h.calls[0].options.body),{text:'tu devrais'});assert.equal(h.calls[0].url,'http://127.0.0.1:17389/v1/analyze');
 assert.equal(h.calls[0].options.redirect,'error');
 assert.equal((await h.send({type:'SAVE',id:result.id},{...h.page,documentId:'another'})).ok,false);
 assert.equal((await h.send({type:'SAVE',id:result.id})).ok,true);
 assert.equal((await h.send({type:'LISTEN',id:result.id})).ok,true);
});
test('Disabled domains and child frames cannot request analysis',async()=>{
 const h=await harness();h.local.blockedDomains=['french.example'];
 assert.equal((await h.send({type:'ANALYZE',text:'bonjour',requestID:'one'})).ok,false);
 h.local.blockedDomains=[];
 assert.equal((await h.send({type:'ANALYZE',text:'bonjour',requestID:'one'},{...h.page,frameId:2})).ok,false);
 await h.send({type:'SET_ENABLED',enabled:false},h.popup);
 assert.equal((await h.send({type:'ANALYZE',text:'bonjour',requestID:'one'})).ok,false);assert.equal(h.calls.length,0);
});
test('Pairing stores only a locally validated code, disconnect removes it',async()=>{
 const h=await harness();
 assert.equal((await h.send({type:'PAIR',code:'example-not-a-code'},h.popup)).ok,false);assert.equal(h.calls.length,0);
 assert.equal((await h.send({type:'PAIR',code},h.popup)).ok,true);
 assert.equal(h.local.pairingCode,code);
 assert.equal((await h.send({type:'DISCONNECT'},h.popup)).ok,true);assert.equal(h.local.pairingCode,undefined);
});
test('Network errors do not return remote response bodies',async()=>{
 const h=await harness();globalThis.fetch=async()=>new Response('private server details',{status:500});
 const r=await h.send({type:'ANALYZE',text:'bonjour',requestID:'one'});
 assert.equal(r.ok,false);assert.ok(!r.error.includes('private server details'));
});

test('Disabling during a response rejects late results even if transport ignores abort',async()=>{
 const h=await harness();let finish;
 globalThis.fetch=async()=>new Promise(resolve=>{finish=resolve});
 const work=h.send({type:'ANALYZE',text:'bonjour',requestID:'one'});
 while(!finish)await new Promise(resolve=>setTimeout(resolve,1));
 await h.send({type:'SET_ENABLED',enabled:false},h.popup);
 finish(new Response(JSON.stringify({id:'late-id',analysis}),{status:200}));
 assert.equal((await work).ok,false);assert.equal(h.session.issued,undefined);
});

test('Concurrent analyses keep ownership records for both documents',async()=>{
 const h=await harness();let n=0;
 globalThis.fetch=async()=>new Response(JSON.stringify({id:`result-${++n}`,analysis}),{status:200});
 const other={...h.page,tab:{id:2},documentId:'second-document'};
 const results=await Promise.all([h.send({type:'ANALYZE',text:'bonjour',requestID:'one'}),h.send({type:'ANALYZE',text:'merci',requestID:'two'},other)]);
 assert.ok(results.every(r=>r.ok));
 assert.equal(Object.keys(h.session.issued).length,2);
 assert.equal(h.session.issued[results[0].id].tab,1);
 assert.equal(h.session.issued[results[1].id].tab,2);
});

test('Language detection failure still allows an explicit short phrase without leaking errors',async()=>{
 const h=await harness();chrome.i18n.detectLanguage=async()=>{throw new Error('example internal details')};
 const result=await h.send({type:'CANDIDATE',text:'mon mari'});
 assert.equal(result.ok,true);assert.equal(result.candidate,true);assert.equal(h.calls.length,0);
 assert.ok(!JSON.stringify(result).includes('internal details'));
 assert.equal((await h.send({type:'ANALYZE',text:'mon mari',requestID:'short'})).ok,true);
});

test('Only popup can persist an allowed accent and content gets no credentials',async()=>{
 const h=await harness();
 assert.equal((await h.send({type:'SET_ACCENT',accent:'rose'})).ok,false);
 assert.equal((await h.send({type:'SET_ACCENT',accent:'url(example)'},h.popup)).ok,false);
 assert.equal((await h.send({type:'SET_ACCENT',accent:'rose'},h.popup)).ok,true);
 assert.equal(h.local.accent,'rose');
 const config=await h.send({type:'CONFIG'});assert.equal(config.accent,'rose');
 assert.equal(config.pairingCode,undefined);assert.equal(h.calls.length,0);
});

test('Recognition is opt-in, excludes notes and reveals only a known saved ID without AI',async()=>{
 const h=await harness(),savedID='11111111-1111-1111-1111-111111111111';
 assert.equal((await h.send({type:'RECOGNITION_LIST'})).ok,false);assert.equal(h.calls.length,0);
 assert.equal((await h.send({type:'SET_RECOGNITION',enabled:true})).ok,false);
 await h.send({type:'SET_RECOGNITION',enabled:true},h.popup);
 const paths=[];
 globalThis.fetch=async(url)=>{paths.push(url);return new Response(JSON.stringify(url.endsWith('/vocabulary')?[{id:savedID,french:'bonjour',notes:'example private note'}]:{french:'bonjour',translation:'привет'}),{status:200})};
 const list=await h.send({type:'RECOGNITION_LIST'});
 assert.deepEqual(list.entries,[{id:savedID,french:'bonjour'}]);
 assert.equal((await h.send({type:'RECALL',id:'unknown'})).ok,false);
 assert.equal((await h.send({type:'RECALL',id:savedID})).translation,'привет');
 assert.equal(paths.length,2);assert.ok(paths.every(p=>!p.endsWith('/analyze')));
 await h.send({type:'SET_RECOGNITION',enabled:false},h.popup);
 assert.equal((await h.send({type:'RECALL',id:savedID})).ok,false);
});

test('Disabling recognition rejects an in-flight vocabulary response',async()=>{
 const h=await harness();await h.send({type:'SET_RECOGNITION',enabled:true},h.popup);
 let finish;globalThis.fetch=()=>new Promise(resolve=>{finish=resolve});
 const request=h.send({type:'RECOGNITION_LIST'});
 while(!finish)await new Promise(resolve=>setTimeout(resolve,1));
 await h.send({type:'SET_RECOGNITION',enabled:false},h.popup);
 finish(new Response('[]',{status:200}));
 assert.equal((await request).ok,false);
});

test('Popup preferences read persisted recognition without contacting the Mac',async()=>{
 const h=await harness();
 await h.send({type:'SET_RECOGNITION',enabled:true},h.popup);
 const result=await h.send({type:'PREFERENCES'},h.popup);
 assert.equal(result.recognitionEnabled,true);
 assert.equal(result.pairingCode,undefined);
 assert.equal(h.calls.length,0);
});
