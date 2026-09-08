export const BASE = "http://127.0.0.1:17389";
export const DEFAULTS = {enabled: true, blockedDomains: [], accent: "lavender", recognitionEnabled: false};
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
  // Language detection is unreliable for isolated words and short phrases.
  const shortSelection = text.length <= 80 && text.trim().split(/\s+/).length <= 5;
  return shortSelection || known.test(text) || detection?.languages?.some(l => l.language === "fr" && l.percentage >= 60) === true;
}
export function isAnalysis(value) {
  const object = v => v !== null && typeof v === "object" && !Array.isArray(v);
  const text = (v, limit = 8000) => typeof v === "string" && v.length <= limit;
  if (!object(value) || !text(value.original) || !value.original.trim() ||
      !text(value.translation) || !value.translation.trim()) return false;
  for (const key of ["grammar", "chunks"]) {
    if (!Array.isArray(value[key]) || value[key].length > 4 ||
        !value[key].every(p => object(p) && text(p.title) && text(p.explanation))) return false;
  }
  if (!Array.isArray(value.examples) || value.examples.length > 2 ||
      !value.examples.every(p => object(p) && text(p.fr) && text(p.translation))) return false;
  for (const key of ["ipa", "lemma", "partOfSpeech", "gender", "article", "plural", "difficulty", "naturalnessNotes"]) {
    if (value[key] != null && !text(value[key])) return false;
  }
  return value.verbForm == null || (object(value.verbForm) &&
    ["infinitive", "tense", "person"].every(k => text(value.verbForm[k])));
}
