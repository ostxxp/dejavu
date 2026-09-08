import test from 'node:test';
import assert from 'node:assert/strict';
import '../recognition-policy.js';
const {index,matches}=globalThis.DejavuRecognitionPolicy;
const dict=index([{id:'1',french:'tu devrais'},{id:'2',french:'l’amour'},{id:'3',french:'été'},{id:'4',french:'bonjour'},{id:'5',french:'bonjour mon ami'}]);
test('Recognition matches phrases, case, apostrophes and combining accents with original offsets',()=>{
 const text="TU\u00a0devrais connaître l'amour en e\u0301te\u0301.";
 const found=matches(text,dict);
 assert.deepEqual(found.map(f=>f.id),['1','2','3']);
 assert.equal(text.slice(found[2].start,found[2].end),'e\u0301te\u0301');
});
test('Recognition respects word boundaries, sentence breaks and longest matching phrases',()=>{
 assert.equal(matches('rebonjour tu. Devrais',dict).length,0);
 const found=matches('Bonjour mon ami, bonjour !',dict);
 assert.deepEqual(found.map(f=>f.id),['5','4']);
 assert.equal(matches('bonjour '.repeat(1000),dict).length,80);
});
