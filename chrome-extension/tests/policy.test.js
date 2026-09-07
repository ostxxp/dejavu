import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {allowedPage,cleanSelection,likelyFrench,normalizedDomain,isAnalysis} from '../policy.js';

test('Only HTTP pages outside excluded domains are eligible',()=>{
 const config={enabled:true,blockedDomains:['example.com']};
 assert.equal(allowedPage('https://sub.example.com/path',config),false);
 assert.equal(allowedPage('https://notexample.com',config),true);
 for(const url of ['file:///private','chrome://settings','https://example.com','http://127.0.0.1:17389/v1/health'])assert.equal(allowedPage(url,config),false);
 assert.equal(allowedPage('https://french.example',{...config,enabled:false}),false);
 assert.equal(normalizedDomain(' ÉXAMPLE.com '),'xn--xample-9ua.com');
 assert.equal(normalizedDomain('https://example.com/path'),null);
});
test('Short useful expressions work without forcing all text to French',()=>{
 for(const text of ['du tout','leurs','en route','tu devrais','garent'])assert.equal(likelyFrench(text,{languages:[]}),true);
 assert.equal(likelyFrench('Good morning',{languages:[{language:'en',percentage:99}]}),false);
 assert.equal(likelyFrench('Nous apprenons ensemble.',{languages:[{language:'fr',percentage:95}]}),true);
});
test('Selection limits reject nontext, code, URLs and credential-shaped input',()=>{
 for(const value of [null,{},'', '12345', 'https://example.com','const value = {}','mon mot de passe: placeholder', 'bonjour test@example.com','a'.repeat(4001)])assert.equal(cleanSelection(value),null);
 assert.equal(cleanSelection('  tu devrais  '),'tu devrais');
});
test('Manifest isolates worker networking and does not expose resources or external messages',async()=>{
 const m=JSON.parse(await readFile(new URL('../manifest.json',import.meta.url)));
 assert.equal(m.manifest_version,3);assert.deepEqual(m.host_permissions,['http://127.0.0.1/*']);
 assert.equal(m.externally_connectable,undefined);assert.equal(m.web_accessible_resources,undefined);
 assert.equal(m.content_scripts[0].all_frames,false);
 assert.ok(!m.permissions.includes('debugger'));assert.ok(!m.permissions.includes('cookies'));
 const content=await readFile(new URL('../content.js',import.meta.url),'utf8');
 assert.ok(!/innerHTML|outerHTML|insertAdjacentHTML|eval\(/.test(content));
 assert.ok(content.includes('event.isTrusted'));
 assert.ok(!content.includes('pairingCode'));
 assert.equal(isAnalysis({original:'bonjour',translation:'привет',grammar:[],chunks:[],examples:[]}),true);
});

test('Malformed nested analysis is rejected before rendering',()=>{
 const good={original:'bonjour',translation:'привет',grammar:[],chunks:[],examples:[]};
 for(const extra of [{grammar:[null]},{chunks:[{title:{},explanation:'x'}]},{examples:[{fr:'bonjour',translation:42}]},{verbForm:{infinitive:'être'}},{ipa:{}},{original:''}])assert.equal(isAnalysis({...good,...extra}),false);
 assert.equal(isAnalysis({...good,grammar:[{title:'Приветствие',explanation:'Нейтральное.'}]}),true);
});
