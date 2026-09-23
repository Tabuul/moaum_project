"use client";

/**
 * dtable(cols, rows) plus what enhanceTables() and fitTables() do to every
 * table after a render (proto/part24.html): the data-l label on each cell
 * for the stacked layout, a search box over eight rows, paging in tens, the
 * count-and-export footer, and stacking when the table does not fit its
 * space — measured, not guessed.
 */
import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";

const PAGE = 10;

/**
 * Print one table cleanly. The app's print stylesheet hides `.shell` (the whole page chrome),
 * so a plain window.print() from inside a panel prints a blank page. Instead we clone the table,
 * unhide every row (print the full list, not just the current page), and print it on its own in a
 * hidden same-origin iframe with its own minimal stylesheet — so the button works everywhere.
 */
function printTable(tableEl: HTMLTableElement | null) {
  if (!tableEl) { window.print(); return; }
  const clone = tableEl.cloneNode(true) as HTMLTableElement;
  clone.classList.remove("tbl--stack");
  clone.removeAttribute("style");
  clone.querySelectorAll("tr[hidden]").forEach((tr) => tr.removeAttribute("hidden"));
  const heading = (tableEl.closest(".card")?.querySelector(".card__title")?.textContent
    ?? tableEl.getAttribute("data-title") ?? document.title ?? "").trim();
  const esc = (s: string) => s.replace(/[&<>]/g, (ch) => (ch === "&" ? "&amp;" : ch === "<" ? "&lt;" : "&gt;"));
  const when = new Date().toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" });
  const css = `
    * { box-sizing: border-box; }
    body { margin: 24px; font: 12px/1.4 -apple-system, Segoe UI, Roboto, sans-serif; color: #16273a; }
    h1 { font-size: 15px; margin: 0 0 2px; }
    .meta { color: #6b7784; font-size: 11px; margin: 0 0 14px; }
    table { width: 100%; border-collapse: collapse; }
    th, td { text-align: left; padding: 6px 10px; border-bottom: 1px solid #dfe4ea; vertical-align: top; }
    th { font-size: 10px; letter-spacing: .04em; text-transform: uppercase; color: #5d6b79; border-bottom: 1.5px solid #16273a; }
    td.num, th.num { text-align: right; } td.mid, th.mid { text-align: center; }
    .sub2 { color: #6b7784; font-size: 11px; }
    a { color: inherit; text-decoration: none; }
    button, .btn, input, .srch__x { display: none !important; }
    @page { margin: 14mm; }
  `;
  const html = `<!doctype html><html><head><meta charset="utf-8"><title>${esc(heading)}</title><style>${css}</style></head>`
    + `<body>${heading ? `<h1>${esc(heading)}</h1>` : ""}<div class="meta">Rev. Fr. Moses Orshio Adasu University, Makurdi · printed ${when}</div>${clone.outerHTML}</body></html>`;
  const f = document.createElement("iframe");
  f.style.position = "fixed"; f.style.right = "0"; f.style.bottom = "0"; f.style.width = "0"; f.style.height = "0"; f.style.border = "0";
  document.body.appendChild(f);
  const doc = f.contentWindow?.document;
  if (!doc) { document.body.removeChild(f); window.print(); return; }
  const go = () => {
    try { f.contentWindow?.focus(); f.contentWindow?.print(); } catch { /* pop-up blocked; nothing to do */ }
    window.setTimeout(() => { try { document.body.removeChild(f); } catch { /* already gone */ } }, 60000);
  };
  doc.open(); doc.write(html); doc.close();
  window.setTimeout(go, 120);
}

export interface DTableProps {
  /** "Header" or "Header|num" / "Header|mid" */
  cols: string[];
  rows: ReactNode[][];
  /** the searchable text of each row; defaults to nothing, which disables search */
  texts?: string[];
  title?: string;
  /** a table that is a control, not a list to keep — inside a dialog, say — carries no Print button */
  noPrint?: boolean;
}

export function DTable({ cols, rows, texts, title, noPrint }: DTableProps) {
  const cls = cols.map((c) => c.split("|")[1] || "");
  const labels = cols.map((c) => c.split("|")[0]);
  const [q, setQ] = useState("");
  const [page, setPage] = useState(0);
  const [size, setSize] = useState<number>(PAGE); // rows per page; 0 = all
  const wrap = useRef<HTMLDivElement>(null);
  const table = useRef<HTMLTableElement>(null);

  const searchable = rows.length > 8 && !!texts;
  const terms = q.toLowerCase().trim().split(/\s+/).filter(Boolean);
  const match = useMemo(() => {
    const out: number[] = [];
    rows.forEach((_, i) => {
      const hay = (texts?.[i] ?? "").toLowerCase();
      if (terms.every((t) => hay.includes(t))) out.push(i);
    });
    return out;
  }, [rows, texts, terms]);

  const total = match.length;
  const per = size === 0 ? Math.max(total, 1) : size;
  const pages = Math.max(1, Math.ceil(total / per));
  const p = Math.min(page, pages - 1);
  const from = total ? p * per + 1 : 0;
  const to = Math.min(total, (p + 1) * per);
  const shown = new Set(match.slice(from - 1 < 0 ? 0 : from - 1, to));

  useEffect(() => {
    const fit = () => {
      const tb = table.current;
      const w = wrap.current;
      if (!tb || !w) return;
      tb.classList.remove("tbl--stack");
      if (tb.scrollWidth > w.clientWidth + 1) tb.classList.add("tbl--stack");
    };
    fit();
    const ro = typeof ResizeObserver !== "undefined" && wrap.current ? new ResizeObserver(fit) : null;
    if (ro && wrap.current) ro.observe(wrap.current);
    window.addEventListener("resize", fit);
    return () => {
      ro?.disconnect();
      window.removeEventListener("resize", fit);
    };
  }, [rows, shown.size]);

  const window5 = (() => {
    const want = [0, 1, p - 2, p - 1, p, p + 1, p + 2, pages - 2, pages - 1];
    const list = [...new Set(want.filter((x) => x >= 0 && x < pages))].sort((a, b) => a - b);
    return list;
  })();

  return (
    <>
      {searchable && (
        <div className="tsrch">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
            <circle cx="11" cy="11" r="7" />
            <path d="M20 20l-3.5-3.5" />
          </svg>
          <input
            value={q}
            onChange={(e) => {
              setQ(e.target.value);
              setPage(0);
            }}
            placeholder={`Search these ${rows.length} rows…`}
            aria-label="Search this table"
            autoComplete="off"
            spellCheck={false}
          />
          {q && (
            <button className="srch__x" onClick={() => setQ("")}>
              Clear
            </button>
          )}
        </div>
      )}
      <div className="tablewrap" ref={wrap}>
        <table className="tbl--data" ref={table} data-title={title}>
          <thead>
            <tr>
              {labels.map((l, i) => (
                <th key={i} className={cls[i]}>
                  {l}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((r, ri) => (
              <tr key={ri} hidden={!shown.has(ri)}>
                {r.map((cell, ci) => (
                  <td key={ci} className={cls[ci]} data-l={labels[ci] || undefined}>
                    {cell}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <div className="tfoot">
        {rows.length > 10 ? (
          <label className="tfoot__n" style={{ display: "flex", gap: 6, alignItems: "center" }}>
            Rows
            <select className="ctl" style={{ width: "auto", padding: "2px 6px" }} value={size} onChange={(e) => { setSize(Number(e.target.value)); setPage(0); }} aria-label="Rows per page">
              {[10, 25, 50, 100].map((n) => <option key={n} value={n}>{n}</option>)}
              <option value={0}>All</option>
            </select>
          </label>
        ) : null}
        {q && !total ? (
          <div className="tfoot__n">
            Nothing matches <b>{q}</b> in these {rows.length} rows.{" "}
            <button className="srch__x" onClick={() => setQ("")}>
              Clear
            </button>
          </div>
        ) : pages > 1 ? (
          <>
            <div className="tfoot__n">
              Showing <b className="tnum">{from}&ndash;{to}</b> of <b className="tnum">{total}</b>
            </div>
            <div className="pg">
              <button className="pg__b" disabled={p === 0} onClick={() => setPage(p - 1)} aria-label="Previous page">
                &larr;
              </button>
              {window5.map((n, i) => (
                <span key={n}>
                  {i > 0 && n - window5[i - 1] > 1 ? <span className="pg__gap">&hellip;</span> : null}
                  <button className={`pg__b${n === p ? " is-on" : ""}`} onClick={() => setPage(n)}>
                    {n + 1}
                  </button>
                </span>
              ))}
              <button className="pg__b" disabled={p === pages - 1} onClick={() => setPage(p + 1)} aria-label="Next page">
                &rarr;
              </button>
            </div>
          </>
        ) : (
          <div className="tfoot__n">
            <b className="tnum">{total}</b> {total === 1 ? "row" : "rows"}
            {q ? (
              <>
                {" "}
                matching <b>{q}</b>, of {rows.length}
              </>
            ) : null}
          </div>
        )}
        {noPrint ? null : <button className="btn btn--ghost btn--sm tfoot__x" title="Print this table" onClick={() => printTable(table.current)}>
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M6 9V2h12v7M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2M6 14h12v8H6z" />
          </svg>
          Print
        </button>}
      </div>
    </>
  );
}
