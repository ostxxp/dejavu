const $=id=>document.getElementById(id);
const send=message=>chrome.runtime.sendMessage(message);
let activeDomain;
async function run(action) {
  $("message").textContent="";
  try {await action();} catch {$("message").textContent="Не удалось выполнить действие. Откройте расширение заново.";}
}
async function refresh() {
  $("status").textContent="Проверяем подключение…";
  const result=await send({type:"STATUS"});
  if (!result?.ok) {$("status").textContent=result?.error??"Подключение недоступно";return;}
  $("status").textContent=result.detail;
  $("enabled").checked=result.enabled;
  $("domains").value=result.blockedDomains.join("\n");
  $("extension-id").textContent=result.extensionID;
  if (!result.connected) $("pairing").open=true;
}
$("enabled").addEventListener("change",()=>run(async()=>{const r=await send({type:"SET_ENABLED",enabled:$("enabled").checked});if(!r?.ok)$("message").textContent=r?.error;}));
$("recheck").addEventListener("click",()=>run(refresh));
$("connect").addEventListener("click",()=>run(async()=>{
  $("connect").disabled=true;
  try {const result=await send({type:"PAIR",code:$("code").value});$("code").value="";if(!result?.ok){$("message").textContent=result?.error;return;}await refresh();$("pairing").open=false;}
  finally {$("connect").disabled=false;}
}));
$("disconnect").addEventListener("click",()=>run(async()=>{$("code").value="";await send({type:"DISCONNECT"});await refresh();}));
async function saveDomains(){const domains=$("domains").value.split("\n").map(s=>s.trim()).filter(Boolean);const r=await send({type:"SET_DOMAINS",domains});$("message").textContent=r?.ok?"Список сохранён":r?.error;}
$("save-domains").addEventListener("click",()=>run(saveDomains));
$("block-current").addEventListener("click",()=>run(async()=>{if(!activeDomain)return;const rows=$("domains").value.split("\n").filter(Boolean);if(!rows.includes(activeDomain))rows.push(activeDomain);$("domains").value=rows.join("\n");await saveDomains();}));
window.addEventListener("pagehide",()=>{$("code").value="";});
void run(async()=>{
  $("extension-id").textContent=chrome.runtime.id;
  const [tab]=await chrome.tabs.query({active:true,currentWindow:true});
  try {const url=new URL(tab?.url);if(["http:","https:"].includes(url.protocol))activeDomain=url.hostname;}catch{}
  $("block-current").disabled=!activeDomain;
  await refresh();
});
