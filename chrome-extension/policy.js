export const BASE = "http://127.0.0.1:17389";
export const DEFAULTS = {enabled: true, blockedDomains: []};
export function normalizedDomain(value) {
  const domain = String(value).trim().toLowerCase().replace(/^\.+|\.+$/g, "");
  if (!domain || domain.length > 253 || /[\s/:?#@]/.test(domain)) return null;
  try { const host = new URL("https://" + domain).hostname; return host || null; } catch { return null; }
}
export function allowedPage(url, settings) {
  try {
    const page = new URL(url);
    return settings.enabled && ["https:", "http:"].includes(page.protocol) &&
      !(page.hostname === "127.0.0.1" && page.port === "17389") &&
      !settings.blockedDomains.some(d => page.hostname === d || page.hostname.endsWith("." + d));
  } catch { return false; }
}
export function cleanSelection(value) {
  if (typeof value !== "string" || value.length > 8000) return null;
  const text = value.trim();
  if (!text || [...text].length > 4000 || !/[a-zàâäéèêëîïôöùûüÿçœæ]/i.test(text)) return null;
  if (/[{}<>]|[\u0000-\u0008\u000b-\u001f]/.test(text) || /(?:\w+:\/\/|www\.|\S+@\S+\.\S+|\d{6,}|-----BEGIN|\b(?:sk-|github_pat_|gh[pousr]_|Bearer\s))/i.test(text)) return null;
  if (/\b(?:const|function|import|SELECT)\s|(?:password|mot de passe|api[_ -]?key|token|secret)\s*[:=]/i.test(text)) return null;
  return text;
}
export function likelyFrench(text, detection) {
  const known = /^(?:du tout|leurs?|en route|tu devrais|bonjour|bonsoir|salut|merci|au revoir|s'il vous plaît|s’il vous plaît|garent|devoir|ça va)$/i;
  return known.test(text) || detection?.languages?.some(l => l.language === "fr" && l.percentage >= 60) === true;
}
export function isAnalysis(value) {
  return value && typeof value.original === "string" && value.original.length <= 8000 &&
    typeof value.translation === "string" && ["grammar", "chunks", "examples"].every(k => Array.isArray(value[k])) &&
    value.grammar.length <= 4 && value.chunks.length <= 4 && value.examples.length <= 2;
}
