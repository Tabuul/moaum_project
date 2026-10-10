"use client";
/** V387: the manual's door on every dashboard — a small button in the top bar that opens the person's Quick Operational Manual,
 *  and, on a page that has procedures of its own, a "How to" list of them. The list is the server's answer for this route and
 *  office (the same filter as the manual), kept per route for the session. */
import { useEffect, useState } from "react";
import Link from "next/link";
import type { Procedure } from "@/lib/manual";

const held = new Map<string, Pick<Procedure, "id" | "slug" | "title">[]>();

export function ManualHelp({ route, menu }: { route: string; menu: string | null }) {
  const [items, setItems] = useState<Pick<Procedure, "id" | "slug" | "title">[]>(() => held.get(`${route}|${menu ?? ""}`) ?? []);

  useEffect(() => {
    const key = `${route}|${menu ?? ""}`;
    if (held.has(key)) return;
    let live = true;
    fetch(`/api/bff/api/v1/manual/context?route=${encodeURIComponent(route)}${menu ? `&menu=${encodeURIComponent(menu)}` : ""}`)
      .then((r) => (r.ok ? r.json() : []))
      .then((j: Pick<Procedure, "id" | "slug" | "title">[]) => { const rows = Array.isArray(j) ? j.map((p) => ({ id: p.id, slug: p.slug, title: p.title })) : []; held.set(key, rows); if (live) setItems(rows); })
      .catch(() => { held.set(key, []); if (live) setItems([]); });
    return () => { live = false; };
  }, [route, menu]);

  return (
    <div className="topman">
      {items.length ? (
        <details className="topman__howto">
          <summary className="topsrch" title="How to do what this page does"><span>How to…</span></summary>
          <ul className="topman__menu" role="list">
            {items.map((p) => <li key={p.id}><Link href={`/manual?p=${encodeURIComponent(p.slug)}`}>{p.title}</Link></li>)}
            <li className="topman__all"><Link href="/manual">Quick Operational Manual</Link></li>
          </ul>
        </details>
      ) : null}
      <Link href="/manual" className="topsrch topman__btn" title="Quick Operational Manual" aria-label="Quick Operational Manual">
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <path d="M4 5a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z" /><path d="M8 7h8M8 11h8M8 15h5" />
        </svg>
        <span>Manual</span>
      </Link>
    </div>
  );
}
