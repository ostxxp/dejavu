(() => {
  "use strict";
  if (window.top !== window) return;
  const host = document.createElement("div");
  host.setAttribute("data-dejavu", "");
  host.style.setProperty("all", "initial", "important");
  for (const [key,value] of Object.entries({position:"fixed",zIndex:"2147483647",display:"none",margin:"0",padding:"0",border:"0",background:"transparent",colorScheme:"light dark"})) {
    host.style.setProperty(key.replace(/[A-Z]/g, c => "-" + c.toLowerCase()), value, "important");
  }
  const root = host.attachShadow({mode: "closed"});
  const style = document.createElement("style");
  style.textContent = `
    :host{all:initial}*{box-sizing:border-box}
    .card,.bubble{font:14px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:var(--ink);background:#fdfcfe;border:1px solid color-mix(in srgb,var(--accent) 25%,transparent);box-shadow:0 14px 44px #21132b25,0 2px 8px #21132b0d;transform-origin:var(--origin-x,24px) var(--origin-y,top)}
    .card{border-radius:22px;width:400px;max-width:calc(100vw - 24px);max-height:calc(100vh - 24px);overflow:auto;overscroll-behavior:contain;text-align:left;direction:ltr;color:#302c38;color-scheme:light dark}
    .bubble{font-weight:600;font-size:13px;border-radius:24px;padding:10px 16px;cursor:pointer;background:var(--soft)}
    header{display:flex;justify-content:space-between;align-items:center;padding:14px 18px;background:linear-gradient(120deg,var(--soft),transparent);border-bottom:1px solid #8882}header strong{font:600 19px Georgia,serif;color:var(--ink)}.body{padding:18px}h2{font:500 25px/1.2 Georgia,serif;margin:0 0 7px;overflow-wrap:anywhere}p{margin:8px 0;white-space:pre-wrap;overflow-wrap:anywhere}.ipa,.muted{color:#726b7d}.translation{font-size:18px}h3{font-size:13px;margin:17px 0 5px;color:var(--ink)}.point strong{font-size:13px}footer{position:sticky;bottom:0;padding:12px 16px;display:flex;gap:8px;flex-wrap:wrap;background:#fdfcfe;border-top:1px solid #8882}button{font:500 12px/1.4 -apple-system,BlinkMacSystemFont,sans-serif;border:1px solid color-mix(in srgb,var(--accent) 30%,transparent);border-radius:11px;padding:8px 11px;cursor:pointer;color:var(--ink);background:var(--soft)}button:hover{filter:brightness(.96)}button:focus-visible{outline:2px solid var(--accent);outline-offset:2px}button:disabled{opacity:.55;cursor:default}.close{border:0;background:transparent;font-size:20px;padding:0 4px}.notice{color:#754329;font-size:12px}.cache{font-size:11px;color:#726b7d}.spark{display:inline-block;color:var(--accent);font-size:26px;margin-right:8px}
    @media(prefers-reduced-motion:no-preference){.enter{animation:dejavu-open .25s cubic-bezier(.2,.8,.2,1) both}@keyframes dejavu-open{from{opacity:0;transform:translateY(var(--rise,6px)) scale(.94)}to{opacity:1;transform:none}}button{transition:filter .15s,background .15s}button:active{filter:brightness(.9)}.spark{animation:float 2.4s ease-in-out infinite}@keyframes float{50%{transform:translateY(-3px) rotate(12deg)}}}
    @media(prefers-color-scheme:dark){.card,footer{color:#f3eff8;background:#24222b}header{background:color-mix(in srgb,var(--accent) 20%,#24222b)}button,.bubble{background:color-mix(in srgb,var(--accent) 30%,#24222b);color:#f3eff8}header strong,h3{color:color-mix(in srgb,var(--accent) 40%,#fff)}.muted,.ipa,.cache{color:#c1b8ce}.notice{color:#f3c29c}}
  `;
  root.append(style);
  let enabled = false, epoch = 0, timer, anchor, selectedText = "", requestID, response, details = false, saved = false;
  let surface, anchoredRange, frameID, clipParents = [];
  const {palette, place} = globalThis.DejavuPresentation;
  let accent = palette("lavender");
  const highlightName = "dejavu-selection-" + crypto.randomUUID();
  const selectionStyle = document.createElement("style");
  function applyAccent(key) {
    accent = palette(key);
    for (const name of ["accent", "soft", "ink"]) host.style.setProperty(`--${name}`, accent[name]);
    selectionStyle.textContent = `::highlight(${highlightName}){background-color:${accent.soft};color:${accent.ink}}::selection{background-color:${accent.soft};color:${accent.ink}}`;
  }
  applyAccent("lavender");
  const resizeObserver = new ResizeObserver(() => schedulePosition());
  function highlight() {
    if (!anchoredRange) return;
    if (CSS.highlights && typeof Highlight !== "undefined") CSS.highlights.set(highlightName,new Highlight(anchoredRange));
    document.documentElement.append(selectionStyle);
  }
  function schedulePosition() {
    if (surface && !frameID) frameID = requestAnimationFrame(() => {frameID = undefined; position();});
  }
  function el(tag, text, cls) {
    const node = document.createElement(tag);
    if (text !== undefined && text !== null) node.textContent = String(text);
    if (cls) node.className = cls;
    if (cls === "spark") node.setAttribute("aria-hidden", "true");
    return node;
  }
  async function send(message) {
    try { return await chrome.runtime.sendMessage(message); }
    catch { return {ok:false,error:"Расширение обновилось. Перезагрузите страницу."}; }
  }
  function hide() {
    epoch++;
    clearTimeout(timer);
    if (frameID) cancelAnimationFrame(frameID);
    frameID = undefined;
    resizeObserver.disconnect();
    CSS.highlights?.delete(highlightName); selectionStyle.remove();
    anchoredRange = undefined; anchor = undefined; clipParents = [];
    if (requestID) void send({type:"CANCEL",requestID});
    requestID = undefined; response = undefined; selectedText = "";
    surface?.remove(); surface = undefined;
    host.style.setProperty("display","none","important");
  }
  function mount(node) {
    const entering = !surface || surface.classList.contains("bubble");
    surface?.remove(); surface = node; root.append(node);
    if (entering) node.classList.add("enter");
    if (!host.isConnected) document.documentElement.append(host);
    host.style.setProperty("display","block","important");
    resizeObserver.disconnect();
    resizeObserver.observe(node);
    if (document.body) resizeObserver.observe(document.body);
    if (anchoredRange?.commonAncestorContainer.parentElement) resizeObserver.observe(anchoredRange.commonAncestorContainer.parentElement);
    position();
  }
  function position() {
    if (!surface || !anchoredRange) return;
    if (!anchoredRange.startContainer.isConnected || !anchoredRange.endContainer.isConnected || anchoredRange.collapsed) {hide(); return;}
    const viewport = window.visualViewport;
    const width = viewport?.width ?? innerWidth, height = viewport?.height ?? innerHeight;
    const ox = viewport?.offsetLeft ?? 0, oy = viewport?.offsetTop ?? 0;
    surface.style.maxWidth = `${Math.max(1,width-24)}px`;
    surface.style.maxHeight = `${Math.max(1,height-24)}px`;
    let bounds = {left:ox, top:oy, right:ox+width, bottom:oy+height};
    for (const parent of clipParents) {
      const r = parent.getBoundingClientRect();
      bounds = {left:Math.max(bounds.left,r.left),top:Math.max(bounds.top,r.top),right:Math.min(bounds.right,r.right),bottom:Math.min(bounds.bottom,r.bottom)};
    }
    const visible = [...anchoredRange.getClientRects()].filter(r => r.width>0 && r.height>0 && r.bottom>bounds.top && r.top<bounds.bottom && r.right>bounds.left && r.left<bounds.right);
    const last = visible.at(-1);
    host.style.setProperty("visibility",last ? "visible" : "hidden","important");
    if (!last) return;
    anchor = {left:Math.max(last.left,bounds.left),right:Math.min(last.right,bounds.right),top:Math.max(last.top,bounds.top),bottom:Math.min(last.bottom,bounds.bottom)};
    // offset sizes exclude the entrance transform, avoiding placement jumps during animation.
    const result = place(anchor,{width:surface.offsetWidth,height:surface.offsetHeight},{left:ox,top:oy,width,height});
    host.style.setProperty("left",`${result.left}px`,"important");
    host.style.setProperty("top",`${result.top}px`,"important");
    host.style.setProperty("--origin-x",`${result.originX}px`);
    host.style.setProperty("--origin-y",result.below?"top":"bottom");
    host.style.setProperty("--rise",result.below?"-6px":"6px");
  }
  function button(text, action, cls) {
    const node = el("button",text,cls); node.type="button";
    node.addEventListener("click",event => { if (!event.isTrusted) return; event.stopPropagation(); action(node); });
    return node;
  }
  function shell() {
    const card = el("section",undefined,"card"); card.setAttribute("role","dialog"); card.setAttribute("aria-label","Разбор французского — DéjàVu");
    const header = el("header"); header.append(el("strong","DéjàVu"),button("×",hide,"close"));
    header.lastChild.setAttribute("aria-label","Закрыть разбор");
    const body = el("div",undefined,"body"); body.setAttribute("aria-live","polite");
    card.append(header,body); return {card,body};
  }
  async function analyze() {
    const text = selectedText;
    if (!text) return;
    const current = ++epoch;
    requestID = crypto.randomUUID();
    const {card,body} = shell(); body.append(el("span","✦","spark"),el("p","Разбираем…"),el("p",text,"muted")); mount(card);
    const value = await send({type:"ANALYZE",text,requestID});
    if (current !== epoch) return;
    requestID = undefined;
    if (!value?.ok) {
      body.replaceChildren(el("p",value?.error ?? "Не удалось получить ответ.","notice"),button("Повторить",analyze)); position(); return;
    }
    response=value; details=false; saved=false; render();
  }
  function render() {
    if (!response) return;
    const a=response.analysis;
    const {card,body}=shell();
    if (response.fromCache) body.append(el("p","Недавний ответ · без нового запроса","cache"));
    body.append(el("h2",a.original));
    if (a.ipa) body.append(el("p",a.ipa,"ipa"));
    body.append(el("p",a.translation,"translation"));
    if (a.verbForm) body.append(el("p",[a.verbForm.infinitive,a.verbForm.tense,a.verbForm.person].filter(Boolean).join(" · "),"muted"));
    if (details) {
      for (const [key,label] of Object.entries({lemma:"Начальная форма",partOfSpeech:"Часть речи",gender:"Род",article:"Артикль",plural:"Множественное число",difficulty:"Уровень"})) {
        if (a[key]) body.append(el("p",`${label}: ${a[key]}`,"muted"));
      }
    }
    function points(items,title) {
      if (!items?.length) return;
      body.append(el("h3",title));
      for (const point of items) { const row=el("div",undefined,"point"); row.append(el("strong",point.title),el("p",point.explanation)); body.append(row); }
    }
    points(details ? a.grammar : a.grammar.slice(0,2),"Как это устроено");
    if (details) points(a.chunks,"Полезные конструкции");
    if (a.examples.length) {
      body.append(el("h3","Примеры"));
      for (const example of (details ? a.examples : a.examples.slice(0,1))) body.append(el("p",example.fr),el("p",example.translation,"muted"));
    }
    if (details && a.naturalnessNotes) body.append(el("p",a.naturalnessNotes,"muted"));
    const notice=el("p","","notice"); body.append(notice);
    const footer=el("footer");
    footer.append(button("Прослушать",async () => { const r=await send({type:"LISTEN",id:response.id}); notice.textContent=r?.ok ? "" : r?.error; }),
      button(saved ? "Сохранено" : "Сохранить",async node => {
        node.disabled=true; const id=response.id;
        const r=await send({type:"SAVE",id});
        if (response?.id !== id) return;
        if (r?.ok) { saved=true; node.textContent="Сохранено"; } else { node.disabled=false; notice.textContent=r?.error; }
      }),button(details ? "Свернуть" : "Подробнее",() => {details=!details;render();}));
    if (saved) footer.children[1].disabled=true;
    card.append(footer); mount(card);
  }
  const excluded="input,textarea,select,[contenteditable]:not([contenteditable='false']),[role='textbox'],pre,code,script,style";
  function blockedNode(node) { const element=node?.nodeType===Node.ELEMENT_NODE ? node : node?.parentElement; return !!element?.closest(excluded); }
  async function selectionChanged() {
    if (!enabled) return;
    const selection=window.getSelection();
    if (!selection || selection.isCollapsed || !selection.rangeCount || blockedNode(selection.anchorNode) || blockedNode(selection.focusNode) || blockedNode(document.activeElement)) { hide(); return; }
    const range=selection.getRangeAt(0);
    const text=selection.toString().trim();
    if (!text || text.length>8000 || [...text].length>4000 || range.cloneContents().querySelector(excluded)) { hide(); return; }
    if (text===selectedText && surface && anchoredRange &&
        range.startContainer===anchoredRange.startContainer && range.startOffset===anchoredRange.startOffset &&
        range.endContainer===anchoredRange.endContainer && range.endOffset===anchoredRange.endOffset) return;
    hide(); selectedText=text; anchoredRange=range.cloneRange();
    let parent=anchoredRange.commonAncestorContainer;
    if (parent.nodeType!==Node.ELEMENT_NODE) parent=parent.parentElement;
    for (;parent && parent!==document.body;parent=parent.parentElement) {
      const css=getComputedStyle(parent);
      if (/(auto|scroll|hidden|clip)/.test(css.overflow+css.overflowX+css.overflowY)) clipParents.push(parent);
    }
    const current=epoch;
    const result=await send({type:"CANDIDATE",text});
    if (current!==epoch || !enabled || !result?.candidate) return;
    highlight();
    mount(button("✦ DéjàVu · Разобрать",analyze,"bubble"));
  }
  async function configure() {
    hide();
    const config=await send({type:"CONFIG"}); enabled=config?.ok===true && config.enabled===true;
    applyAccent(config?.accent);
    if (!enabled) hide();
  }
  root.addEventListener("pointerdown",e => {e.preventDefault();e.stopPropagation();});
  document.addEventListener("selectionchange",() => {clearTimeout(timer);timer=setTimeout(selectionChanged,180);});
  document.addEventListener("pointerdown",e => {if (!e.composedPath().includes(host)) hide();},true);
  document.addEventListener("keydown",e => {if (e.key==="Escape") hide();});
  window.addEventListener("scroll",schedulePosition,{capture:true,passive:true});
  window.addEventListener("resize",schedulePosition,{passive:true});
  window.visualViewport?.addEventListener("resize",schedulePosition,{passive:true});
  window.visualViewport?.addEventListener("scroll",schedulePosition,{passive:true});
  document.addEventListener("visibilitychange",() => { if (document.hidden) hide(); });
  window.addEventListener("pagehide",hide);
  chrome.runtime.onMessage.addListener(message => {
    if (message.type==="CONFIG_CHANGED") void configure();
    if (message.type==="APPEARANCE_CHANGED") applyAccent(message.accent);
  });
  void configure();
})();
