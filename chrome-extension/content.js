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
    :host{all:initial} @media(prefers-color-scheme:dark){.card{color:#edf3e9!important;background:#222a24!important;border-color:#465648!important}footer{background:#222a24!important;border-color:#465648!important}header{border-color:#465648!important}button,.bubble{background:#334637!important;color:#e2efdd!important;border-color:#698367!important}.muted,.ipa,.cache,h3{color:#b5c6b8!important}.notice{color:#f3c29c!important}} @media(prefers-reduced-motion:no-preference){.card,.bubble{animation:dejavu-appear .12s ease-out}@keyframes dejavu-appear{from{opacity:0}to{opacity:1}}} *{box-sizing:border-box} .card{font:14px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#232924;background:#fcfcf8;border:1px solid #dce4da;border-radius:16px;box-shadow:0 12px 40px #142e202e;width:400px;max-width:calc(100vw - 24px);max-height:calc(100vh - 24px);overflow:auto;text-align:left;direction:ltr;color-scheme:light dark}
    .bubble{font:600 13px/1.2 -apple-system,BlinkMacSystemFont,sans-serif;border:1px solid #c9d9c8;background:#edf5e9;color:#234c36;padding:9px 13px;border-radius:20px;box-shadow:0 4px 16px #142e2026;cursor:pointer}
    header{display:flex;justify-content:space-between;align-items:center;padding:14px 18px;border-bottom:1px solid #e8ece4}header strong{font:600 19px Georgia,serif}.body{padding:18px}h2{font:500 25px/1.2 Georgia,serif;margin:0 0 7px;overflow-wrap:anywhere}p{margin:8px 0;white-space:pre-wrap;overflow-wrap:anywhere}.ipa,.muted{color:#67746a}.translation{font-size:18px}h3{font-size:13px;margin:17px 0 5px;color:#49634e}.point strong{font-size:13px}footer{position:sticky;bottom:0;padding:12px 16px;display:flex;gap:8px;flex-wrap:wrap;background:#fcfcf8;border-top:1px solid #e8ece4}button{font:500 12px/1.4 -apple-system,BlinkMacSystemFont,sans-serif;border:1px solid #cbd6c7;border-radius:8px;padding:7px 10px;cursor:pointer;color:#234c36;background:#eff4eb}button:hover{background:#e1eddc}button:focus-visible{outline:2px solid #488657;outline-offset:2px}button:disabled{opacity:.55;cursor:default}.close{border:0;background:transparent;font-size:18px;padding:0 4px}.notice{color:#754329;font-size:12px}.cache{font-size:11px;color:#67746a}
  `;
  root.append(style);
  let enabled = false, epoch = 0, timer, anchor, selectedText = "", requestID, response, details = false, saved = false;
  let surface;
  function el(tag, text, cls) {
    const node = document.createElement(tag);
    if (text !== undefined && text !== null) node.textContent = String(text);
    if (cls) node.className = cls;
    return node;
  }
  async function send(message) {
    try { return await chrome.runtime.sendMessage(message); }
    catch { return {ok:false,error:"Расширение обновилось. Перезагрузите страницу."}; }
  }
  function hide() {
    epoch++;
    if (requestID) void send({type:"CANCEL",requestID});
    requestID = undefined; response = undefined; selectedText = "";
    surface?.remove(); surface = undefined;
    host.style.setProperty("display","none","important");
  }
  function mount(node) {
    surface?.remove(); surface = node; root.append(node);
    if (!host.isConnected) document.documentElement.append(host);
    host.style.setProperty("display","block","important");
    position();
  }
  function position() {
    if (!surface || !anchor) return;
    const rect = surface.getBoundingClientRect();
    const viewport = window.visualViewport;
    const width = viewport?.width ?? innerWidth, height = viewport?.height ?? innerHeight;
    const ox = viewport?.offsetLeft ?? 0, oy = viewport?.offsetTop ?? 0;
    const left = Math.max(ox+12, Math.min(anchor.left, ox+width-rect.width-12));
    let top = anchor.bottom+8;
    if (top+rect.height > oy+height-12) top = anchor.top-rect.height-8;
    top = Math.max(oy+12, Math.min(top,oy+height-rect.height-12));
    host.style.setProperty("left",`${left}px`,"important");
    host.style.setProperty("top",`${top}px`,"important");
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
    const {card,body} = shell(); body.append(el("p","Разбираем…"),el("p",text,"muted")); mount(card);
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
    if (text===selectedText && surface) return;
    hide(); selectedText=text; anchor=range.getBoundingClientRect();
    const current=epoch;
    const result=await send({type:"CANDIDATE",text});
    if (current!==epoch || !enabled || !result?.candidate) return;
    mount(button("DéjàVu · Разобрать",analyze,"bubble"));
  }
  async function configure() { hide(); const config=await send({type:"CONFIG"}); enabled=config?.ok===true && config.enabled===true; }
  root.addEventListener("pointerdown",e => {e.preventDefault();e.stopPropagation();});
  document.addEventListener("selectionchange",() => {clearTimeout(timer);timer=setTimeout(selectionChanged,180);});
  document.addEventListener("pointerdown",e => {if (!e.composedPath().includes(host)) hide();},true);
  document.addEventListener("keydown",e => {if (e.key==="Escape") hide();});
  window.addEventListener("scroll",() => { if (!response) hide(); else position(); },true);
  window.addEventListener("resize",position);
  window.addEventListener("pagehide",hide);
  chrome.runtime.onMessage.addListener(message => {if (message.type==="CONFIG_CHANGED") void configure();});
  void configure();
})();
