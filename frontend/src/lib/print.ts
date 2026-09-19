/**
 * Print one part of the page reliably. The app's print stylesheet hides the whole
 * shell (`.shell`) so the page chrome does not print; the side effect is that a
 * plain window.print() from a button inside the shell prints a blank page. This
 * clones the target element into a hidden, same-origin iframe that carries the
 * app's own stylesheets — so it looks right — but is NOT inside `.shell`, so it
 * prints. Anything marked `.no-print` (toolbars, buttons) is dropped.
 */
export function printNode(el: HTMLElement | null, heading?: string): void {
  if (typeof window === "undefined") return;
  if (!el) { window.print(); return; }

  const clone = el.cloneNode(true) as HTMLElement;
  clone.querySelectorAll(".no-print, button, .tfoot__x, .tsrch").forEach((n) => n.remove());
  clone.querySelectorAll("tr[hidden]").forEach((tr) => tr.removeAttribute("hidden"));

  // carry the app's stylesheets so the clone keeps its look
  const heads: string[] = [];
  document.querySelectorAll('link[rel="stylesheet"], style').forEach((n) => { heads.push(n.outerHTML); });

  const esc = (s: string) => s.replace(/[&<>]/g, (ch) => (ch === "&" ? "&amp;" : ch === "<" ? "&lt;" : "&gt;"));
  const when = new Date().toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" });
  const title = (heading ?? document.title ?? "").trim();
  const html = `<!doctype html><html><head><meta charset="utf-8"><title>${esc(title)}</title>${heads.join("")}`
    + `<style>body{margin:16mm;background:#fff}@page{margin:14mm}.no-print{display:none!important}</style></head>`
    + `<body>${title ? `<h2 style="font:600 15px/1.3 system-ui,Segoe UI,sans-serif;color:#16273a;margin:0 0 2px">${esc(title)}</h2>` : ""}`
    + `<div style="font:11px system-ui,Segoe UI,sans-serif;color:#6b7784;margin:0 0 14px">Rev. Fr. Moses Orshio Adasu University, Makurdi · printed ${when}</div>`
    + `${clone.outerHTML}</body></html>`;

  const f = document.createElement("iframe");
  f.style.position = "fixed"; f.style.right = "0"; f.style.bottom = "0"; f.style.width = "0"; f.style.height = "0"; f.style.border = "0";
  document.body.appendChild(f);
  const doc = f.contentWindow?.document;
  if (!doc) { document.body.removeChild(f); window.print(); return; }
  doc.open(); doc.write(html); doc.close();
  // give the stylesheets a moment to attach, then print and clean up
  window.setTimeout(() => {
    try { f.contentWindow?.focus(); f.contentWindow?.print(); } catch { /* nothing to do */ }
    window.setTimeout(() => { try { document.body.removeChild(f); } catch { /* already gone */ } }, 60000);
  }, 300);
}
