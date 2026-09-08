import {BASE, DEFAULTS, normalizedDomain, allowedPage, cleanSelection, likelyFrench, isAnalysis} from "./policy.js";

// Content scripts never receive access to credentials or issued-result ownership records.
const ready = Promise.all([
  chrome.storage.local.setAccessLevel({accessLevel: "TRUSTED_CONTEXTS"}),
  chrome.storage.session.setAccessLevel({accessLevel: "TRUSTED_CONTEXTS"})
]);
const pending = new Map();
let recognitionCache, recognitionWork, recognitionRevision = 0;
function clearRecognition() { recognitionRevision++; recognitionCache = undefined; recognitionWork = undefined; }
async function recognitionList(config) {
  if (recognitionCache && recognitionCache.code === config.pairingCode && Date.now()-recognitionCache.at < 60000) return recognitionCache.entries;
  if (recognitionWork?.code === config.pairingCode) return recognitionWork.promise;
  const revision = recognitionRevision;
  const promise = (async () => {
    const result = await bridge("/v1/vocabulary",null,config.pairingCode);
    if (!Array.isArray(result) || result.length>500 || !result.every(e => e && typeof e.id === "string" && /^[a-f0-9-]{36}$/i.test(e.id) && typeof e.french === "string" && e.french.length>=2 && e.french.length<=320)) throw new UserFacingError("Не удалось прочитать словарь. Обновите DéjàVu на Mac.");
    const entries = result.map(({id,french})=>({id,french}));
    if (revision !== recognitionRevision) throw new UserFacingError("Подсветка обновляется. Повторите попытку.");
    recognitionCache = {code:config.pairingCode,at:Date.now(),entries};
    return entries;
  })();
  recognitionWork = {code:config.pairingCode,promise};
  try { return await promise; } finally { if (recognitionWork?.promise === promise) recognitionWork=undefined; }
}
let issuedQueue = Promise.resolve();
function withIssuedLock(operation) {
  const work = issuedQueue.then(operation);
  issuedQueue = work.catch(() => {});
  return work;
}
const popupURL = chrome.runtime.getURL("popup.html");
class UserFacingError extends Error {}
const publicError = e => e instanceof UserFacingError ? e.message : "Не удалось выполнить действие. Повторите попытку.";
const error = message => ({ok: false, error: message});
async function settings() {
  await ready;
  const value = await chrome.storage.local.get(["enabled", "blockedDomains", "pairingCode", "accent", "recognitionEnabled"]);
  return {...DEFAULTS, ...value};
}
async function bridge(path, body, pairingCode, signal) {
  if (!/^[a-f0-9]{64}$/.test(pairingCode || "")) throw new UserFacingError("Подключите расширение к DéjàVu на Mac.");
  let response;
  try {
    response = await fetch(BASE + path, {
      method: body ? "POST" : "GET", headers: {Authorization: "Bearer " + pairingCode, ...(body ? {"Content-Type": "application/json"} : {})},
      body: body ? JSON.stringify(body) : undefined,
      credentials: "omit", cache: "no-store", redirect: "error", signal: signal ?? AbortSignal.timeout(25000)
    });
  } catch (e) {
    if (e.name === "AbortError") throw new UserFacingError("Запрос отменён.");
    throw new UserFacingError("Нет ответа от Mac. Откройте DéjàVu и включите подключение в настройках.");
  }
  if (response.status === 401) throw new UserFacingError("Код подключения не принят. Подключите расширение заново.");
  if (response.status === 403) throw new UserFacingError("Укажите ID этого расширения в настройках DéjàVu на Mac.");
  if (response.status === 429) throw new UserFacingError("Слишком много запросов. Попробуйте чуть позже.");
  if (response.status === 404) throw new UserFacingError("Разбор устарел. Выделите текст и разберите его заново.");
  if (!response.ok) throw new UserFacingError("Не удалось выполнить действие. Проверьте подключение ИИ в DéjàVu и повторите.");
  const text = await response.text();
  if (text.length > 1_000_000) throw new UserFacingError("Получен слишком большой ответ.");
  try { return JSON.parse(text); } catch { throw new UserFacingError("Не удалось прочитать ответ от Mac."); }
}
function keyFor(sender, id) { return `${sender.tab.id}:${sender.documentId ?? sender.url}:${id}`; }
async function issuedRecords() {
  const {issued = {}} = await chrome.storage.session.get("issued");
  return Object.fromEntries(Object.entries(issued).filter(([, r]) => Date.now() - r.at < 1800000));
}
async function notifySettings(message = {type: "CONFIG_CHANGED"}) {
  const tabs = await chrome.tabs.query({});
  await Promise.allSettled(tabs.map(t => chrome.tabs.sendMessage(t.id, message)));
}
async function dispatch(message, sender) {
  await ready;
  if (sender.id !== chrome.runtime.id || !message || typeof message.type !== "string") return error("Запрос отклонён.");
  const trusted = sender.url === popupURL;
  const config = await settings();
  if (trusted) {
    switch (message.type) {
      case "STATUS": {
        let connected = false;
        let detail = config.pairingCode ? "Приложение не отвечает" : "Подключите к Mac";
        try { const health = await bridge("/v1/health", null, config.pairingCode); connected = health.status === "ok"; detail = connected ? "Приложение подключено ✓" : detail; } catch (e) { detail = publicError(e); }
        return {ok: true, connected, detail, enabled: config.enabled, recognitionEnabled: config.recognitionEnabled, accent: config.accent, blockedDomains: config.blockedDomains, extensionID: chrome.runtime.id};
      }
      case "PAIR": {
        const code = message.code?.trim();
        const health = await bridge("/v1/health", null, code);
        if (health.status !== "ok") return error("Не удалось подтвердить подключение.");
        for (const controller of pending.values()) controller.abort();
        clearRecognition();
        await chrome.storage.local.set({pairingCode: code});
        await withIssuedLock(() => chrome.storage.session.remove("issued"));
        return {ok: true};
      }
      case "DISCONNECT":
        clearRecognition();
        for (const controller of pending.values()) controller.abort();
        await chrome.storage.local.remove("pairingCode");
        await withIssuedLock(() => chrome.storage.session.remove("issued"));
        await notifySettings();
        return {ok: true};
      case "SET_RECOGNITION":
        if (typeof message.enabled !== "boolean") return error("Проверьте настройку.");
        clearRecognition();
        await chrome.storage.local.set({recognitionEnabled:message.enabled});
        await notifySettings(); return {ok:true};
      case "REFRESH_RECOGNITION":
        clearRecognition(); await notifySettings({type:"VOCABULARY_CHANGED"}); return {ok:true};
      case "SET_ACCENT":
        if (!["lavender", "rose", "sage", "ocean", "apricot"].includes(message.accent)) return error("Выберите цвет из списка.");
        await chrome.storage.local.set({accent: message.accent});
        await notifySettings({type: "APPEARANCE_CHANGED", accent: message.accent}); return {ok: true};
      case "SET_ENABLED":
        if (typeof message.enabled !== "boolean") return error("Проверьте настройку.");
        await chrome.storage.local.set({enabled: message.enabled});
        if (!message.enabled) { clearRecognition(); for (const controller of pending.values()) controller.abort(); chrome.tts.stop(); }
        await notifySettings(); return {ok: true};
      case "SET_DOMAINS": {
        if (!Array.isArray(message.domains) || message.domains.length > 100) return error("Укажите не больше 100 сайтов.");
        const domains = message.domains.map(normalizedDomain);
        if (domains.some(d => !d)) return error("Укажите домены без ссылок и путей, например example.com.");
        await chrome.storage.local.set({blockedDomains: [...new Set(domains)]});
        for (const controller of pending.values()) controller.abort();
        await notifySettings(); return {ok: true};
      }
    }
    return error("Неизвестное действие.");
  }
  if (!sender.tab || sender.frameId !== 0 || !allowedPage(sender.url, config)) return error("Разбор на этой странице выключен.");
  if (message.type === "CONFIG") return {ok: true, enabled: true, paired: !!config.pairingCode, accent: config.accent, recognitionEnabled: config.recognitionEnabled};
  if (["RECOGNITION_LIST", "RECALL"].includes(message.type)) {
    if (!config.recognitionEnabled) return error("Узнавание выражений выключено.");
    const entries = await recognitionList(config);
    let response;
    if (message.type === "RECOGNITION_LIST") response = {ok:true,entries};
    else {
      if (!entries.some(e=>e.id===message.id)) return error("Выражение больше не сохранено. Обновите подсветку.");
      const value = await bridge("/v1/recall",{id:message.id},config.pairingCode);
      if (typeof value.french !== "string" || value.french.length>320 || typeof value.translation !== "string" || value.translation.length>8000) return error("Не удалось прочитать перевод.");
      response = {ok:true,french:value.french,translation:value.translation};
    }
    const latest = await settings();
    if (!latest.recognitionEnabled || latest.pairingCode !== config.pairingCode || !allowedPage(sender.url,latest)) return error("Узнавание выражений выключено.");
    return response;
  }
  if (message.type === "CANDIDATE") {
    const text = cleanSelection(message.text);
    if (!text) return {ok: true, candidate: false};
    const detection = await chrome.i18n.detectLanguage(text);
    return {ok: true, candidate: likelyFrench(text, detection)};
  }
  if (message.type === "CANCEL") {
    pending.get(keyFor(sender, message.requestID))?.abort();
    return {ok: true};
  }
  if (message.type === "ANALYZE") {
    const text = cleanSelection(message.text);
    if (!text || typeof message.requestID !== "string" || message.requestID.length > 100) return error("Выделите французское выражение до 4 000 символов.");
    if (!likelyFrench(text, await chrome.i18n.detectLanguage(text))) return error("Не удалось распознать французский текст.");
    const requestKey = keyFor(sender, message.requestID);
    if (pending.size >= 2 || pending.has(requestKey)) return error("Дождитесь текущего разбора.");
    const controller = new AbortController();
    pending.set(requestKey, controller);
    const timeout = setTimeout(() => controller.abort(), 25000);
    try {
      const result = await bridge("/v1/analyze", {text}, config.pairingCode, controller.signal);
      const latest = await settings();
      if (controller.signal.aborted || latest.pairingCode !== config.pairingCode || !allowedPage(sender.url, latest)) throw new UserFacingError("Запрос отменён.");
      if (!isAnalysis(result.analysis) || typeof result.id !== "string") throw new UserFacingError("Не удалось прочитать разбор.");
      await withIssuedLock(async () => {
      const current = await settings();
      if (controller.signal.aborted || current.pairingCode !== config.pairingCode || !allowedPage(sender.url, current)) throw new UserFacingError("Запрос отменён.");
      const issued = await issuedRecords();
      issued[result.id] = {tab: sender.tab.id, document: sender.documentId ?? sender.url, original: result.analysis.original, at: Date.now()};
      const records = Object.entries(issued).sort((a,b) => b[1].at - a[1].at).slice(0,100);
      await chrome.storage.session.set({issued: Object.fromEntries(records)});
      });
      return {ok: true, ...result};
    } finally { clearTimeout(timeout); pending.delete(requestKey); }
  }
  if (["SAVE", "LISTEN"].includes(message.type)) {
    const records = await issuedRecords();
    const record = records[message.id];
    if (!record || record.tab !== sender.tab.id || record.document !== (sender.documentId ?? sender.url)) return error("Разбор устарел. Получите его заново.");
    if (message.type === "SAVE") {
      const value = await bridge("/v1/save", {id: message.id}, config.pairingCode);
      clearRecognition(); await notifySettings({type:"VOCABULARY_CHANGED"});
      return {ok:true,...value};
    }
    const voices = await chrome.tts.getVoices();
    const voice = voices.find(v => v.lang?.replace("_", "-").toLowerCase() === "fr-fr" && v.remote !== true && !v.extensionId);
    if (!voice) return error("Французский голос недоступен. Загрузите голос Франции в настройках macOS.");
    chrome.tts.stop();
    await chrome.tts.speak(record.original, {voiceName: voice.voiceName, lang: "fr-FR", rate: 0.9});
    return {ok: true};
  }
  if (message.type === "STOP_SPEECH") { chrome.tts.stop(); return {ok: true}; }
  return error("Неизвестное действие.");
}
chrome.runtime.onMessage.addListener((message, sender, respond) => {
  dispatch(message, sender).then(respond).catch(e => respond(error(publicError(e))));
  return true;
});
chrome.tabs.onRemoved.addListener(tabId => {
  for (const [key, controller] of pending) if (key.startsWith(`${tabId}:`)) controller.abort();
});
