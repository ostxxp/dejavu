(() => {
  const excluded="input,textarea,select,button,a,[contenteditable]:not([contenteditable='false']),[role='textbox'],[role='button'],[hidden],[aria-hidden='true'],[inert],pre,code,script,style,noscript,svg,canvas,[data-dejavu]";
  globalThis.createDejavuRecognition = ({onMatch}) => {
    let dictionary, generation=0, idle, timer, hits=[], cursor=0;
    const name='dejavu-known-'+crypto.randomUUID();
    const style=document.createElement('style');
    const dock=document.createElement('div');dock.setAttribute('data-dejavu','');
    for(const [key,value] of Object.entries({all:'initial',position:'fixed',right:'18px',bottom:'18px',zIndex:'2147483646'}))dock.style.setProperty(key.replace(/[A-Z]/g,c=>'-'+c.toLowerCase()),value,'important');
    const root=dock.attachShadow({mode:'closed'}),dockStyle=document.createElement('style'),next=document.createElement('button');
    next.type='button';root.append(dockStyle,next);
    next.addEventListener('click',event=>{
      if(!event.isTrusted||!hits.length)return;
      const hit=hits[cursor++%hits.length];
      window.getSelection()?.removeAllRanges();
      hit.range.startContainer.parentElement?.scrollIntoView({block:'center',behavior:'instant'});
      onMatch(hit);
    });
    const observer=new MutationObserver(()=>{if(!timer)timer=setTimeout(()=>{timer=undefined;scan()},1000)});
    function accent(colors) { dockStyle.textContent=`button{font:500 12px/1.4 system-ui;padding:10px 14px;border-radius:22px;border:1px solid ${colors.accent};background:${colors.soft};color:${colors.ink};box-shadow:0 3px 14px #0002;cursor:pointer}button:focus-visible{outline:3px solid ${colors.accent};outline-offset:3px}`; style.textContent=`::highlight(${name}){background-color:${colors.soft};text-decoration:underline;text-decoration-color:${colors.accent};text-decoration-thickness:2px}`; }
    function cancelScan(){generation++;if(idle!==undefined){if(window.cancelIdleCallback)cancelIdleCallback(idle);else clearTimeout(idle)}idle=undefined;}
    function stop(){cancelScan();clearTimeout(timer);timer=undefined;dictionary=undefined;hits=[];observer.disconnect();CSS.highlights?.delete(name);style.remove();dock.remove();cursor=0;}
    function later(fn){idle=window.requestIdleCallback?requestIdleCallback(fn,{timeout:250}):setTimeout(fn,16)}
    function scan(){
      cancelScan();hits=[];dock.remove();CSS.highlights?.delete(name);
      if(!dictionary||!document.body||document.hidden)return;
      const current=generation, groups=[];
      let previousBlock, currentGroup;
      const walker=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT);
      let total=0,count=0;
      function finish(){
        if(current!==generation)return;
        for(const group of groups) {
          if(hits.length>=80)break;
          for(const match of DejavuRecognitionPolicy.matches(group.text,dictionary,80-hits.length)) {
            const start=group.nodes.find(n=>n.end>match.start),end=group.nodes.find(n=>n.end>=match.end);
            if(!start||!end||!start.node.isConnected||!end.node.isConnected)continue;
            const range=document.createRange();range.setStart(start.node,match.start-start.start);range.setEnd(end.node,match.end-end.start);
            if([...range.getClientRects()].some(r=>r.width&&r.height))hits.push({...match,range});
          }
        }
        dock.remove();cursor=0;
        if(hits.length){
          CSS.highlights.set(name,new Highlight(...hits.map(h=>h.range)));
          next.textContent=`✦ Знакомые фразы: ${hits.length} · Вспомнить`;
          document.documentElement.append(dock);
        }
      }
      function step(){
        if(current!==generation)return;
        for(let n=0;n<50;n++) {
          const node=walker.nextNode();
          if(!node||count>=1500||total>=80000){finish();return}
          count++;
          const parent=node.parentElement;
          if(!parent||parent.closest(excluded)){previousBlock=undefined;continue;}
          // Collect inline spans together, but never join separate paragraphs or controls.
          const block=parent.closest('p,li,blockquote,h1,h2,h3,h4,h5,h6,td,th,div,section,article')??parent;
          if(previousBlock!==block){currentGroup={text:'',nodes:[]};groups.push(currentGroup);previousBlock=block;}
          const group=currentGroup,text=node.textContent.slice(0,Math.min(4000,80000-total));
          const start=group.text.length;group.text+=text;group.nodes.push({node,start,end:group.text.length});total+=text.length;
        }
        later(step);
      }
      later(step);
    }
    function start(entries,colors){
      stop();accent(colors);
      if(!CSS.highlights||typeof Highlight==='undefined')return;
      dictionary=DejavuRecognitionPolicy.index(entries);
      document.documentElement.append(style);
      observer.observe(document.body,{childList:true,subtree:true,characterData:true});
      scan();
    }
    document.addEventListener('click',event=>{
      if(!event.isTrusted||event.defaultPrevented||!dictionary||event.target?.closest?.(excluded))return;
      if(!window.getSelection()?.isCollapsed)return;
      const hit=hits.find(h=>h.range.startContainer.isConnected&&[...h.range.getClientRects()].some(r=>event.clientX>=r.left&&event.clientX<=r.right&&event.clientY>=r.top&&event.clientY<=r.bottom));
      if(hit)onMatch(hit);
    });
    document.addEventListener('visibilitychange',()=>{if(document.hidden){cancelScan();hits=[];dock.remove();CSS.highlights?.delete(name)}else if(dictionary)scan()});
    window.addEventListener('pagehide',stop);
    return {start,stop,accent};
  };
})();
