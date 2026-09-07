// Shared by isolated content scripts and the popup; contains no page or credential data.
(() => {
  const palettes = Object.freeze({
    lavender: {title:"Лаванда", accent:"#7357ba", soft:"#eee7fa", ink:"#493178"},
    rose: {title:"Роза", accent:"#b5486e", soft:"#fae4ed", ink:"#782947"},
    sage: {title:"Шалфей", accent:"#3b7a5c", soft:"#e3f2e9", ink:"#25543d"},
    ocean: {title:"Океан", accent:"#316eb0", soft:"#e2effb", ink:"#234d79"},
    apricot: {title:"Абрикос", accent:"#ad5c2b", soft:"#fcebdc", ink:"#76401e"}
  });
  function palette(key) { return Object.hasOwn(palettes, key) ? palettes[key] : palettes.lavender; }
  function place(anchor, size, viewport) {
    const {left:x, top:y, width:w, height:h} = viewport;
    const clamp = (v, min, max) => Math.max(min, Math.min(v, Math.max(min,max)));
    const left = clamp(anchor.left, x+12, x+w-size.width-12);
    const below = anchor.bottom+10+size.height <= y+h-12 || anchor.top-y < size.height+22;
    const top = clamp(below ? anchor.bottom+10 : anchor.top-size.height-10, y+12, y+h-size.height-12);
    return {left, top, below, originX:clamp((anchor.left+anchor.right)/2-left, 18, size.width-18)};
  }
  globalThis.DejavuPresentation = Object.freeze({palettes, palette, place});
})();
