(() => {
  const wordPattern = /[\p{L}\p{M}\p{N}]+(?:['’][\p{L}\p{M}\p{N}]+)*/gu;
  const key = text => text.normalize('NFC').replaceAll('’',"'").toLocaleLowerCase('fr');
  function words(text) { return [...text.matchAll(wordPattern)].map(m=>({key:key(m[0]),start:m.index,end:m.index+m[0].length})); }
  function index(entries) {
    const result=new Map();
    for(const entry of entries.slice(0,500)) {
      if(typeof entry?.id!=='string'||typeof entry?.french!=='string'||entry.french.length>320)continue;
      const tokens=words(entry.french);if(!tokens.length||tokens.length>24)continue;
      const first=tokens[0].key;
      if(!result.has(first))result.set(first,[]);
      result.get(first).push({entry,tokens:tokens.map(t=>t.key)});
    }
    for(const rows of result.values())rows.sort((a,b)=>b.tokens.length-a.tokens.length);
    return result;
  }
  function matches(text, dictionary, limit=80) {
    const tokens=words(text), result=[];
    for(let i=0;i<tokens.length && result.length<limit;i++) {
      for(const candidate of dictionary.get(tokens[i].key)??[]) {
        const n=candidate.tokens.length;
        if(i+n>tokens.length)continue;
        if(!candidate.tokens.every((t,j)=>tokens[i+j].key===t))continue;
        let continuous=true;
        for(let j=1;j<n;j++)if(!/^[\s\u00a0‐‑–-]*$/u.test(text.slice(tokens[i+j-1].end,tokens[i+j].start)))continuous=false;
        if(!continuous)continue;
        result.push({start:tokens[i].start,end:tokens[i+n-1].end,...candidate.entry});i+=n-1;break;
      }
    }
    return result;
  }
  globalThis.DejavuRecognitionPolicy=Object.freeze({index,matches});
})();
