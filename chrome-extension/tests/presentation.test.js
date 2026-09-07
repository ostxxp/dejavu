import test from 'node:test';
import assert from 'node:assert/strict';
import '../presentation.js';
const {place,palette}=globalThis.DejavuPresentation;
test('Card follows fresh range coordinates and flips at the bottom edge',()=>{
 const viewport={left:0,top:0,width:1000,height:800},size={width:400,height:300};
 const start=place({left:100,right:200,top:300,bottom:320},size,viewport);
 const scrolled=place({left:100,right:200,top:200,bottom:220},size,viewport);
 assert.equal(start.top-scrolled.top,100);assert.equal(start.below,true);
 const bottom=place({left:800,right:900,top:740,bottom:760},size,viewport);
 assert.equal(bottom.below,false);assert.equal(bottom.top,430);assert.equal(bottom.left,588);
});
test('Small and zoomed viewports keep origin and card inside visible area',()=>{
 const v={left:60,top:100,width:340,height:420};
 const r=place({left:350,right:390,top:160,bottom:180},{width:316,height:396},v);
 assert.equal(r.left,72);assert.equal(r.top,112);assert.ok(r.originX<=298);
});
test('Untrusted persisted theme names never become CSS values',()=>{
 for(const value of ['__proto__','constructor','red;display:none',null,undefined])assert.equal(palette(value),palette('lavender'));
 assert.equal(palette('rose').accent,'#b5486e');
});
