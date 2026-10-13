"use client";

/** V425: the student's portal notices — delivered on the dashboard the moment they are queued; each is marked read when opened */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { Btn, Panel, PBody, Pil } from "@/components/proto/ui";

export interface PortalNotice { id: string; subject: string; body: string; priority: string; template_key: string | null; created_at: string; read_at: string | null }

function when(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleDateString("en-GB", { day: "numeric", month: "short" }) + ", " + d.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });
}

export function NotificationsList({ notices, unread, base = "/api/bff/api/v1/me/notifications" }: { notices: PortalNotice[]; unread: number; base?: string }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [open, setOpen] = useState<string | null>(null);

  async function mark(path: string, reason: string) {
    setBusy(true);
    try {
      await fetch(`${base}${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: "{}" });
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <Panel title="Notifications" right={unread ? <span className="row row--inline row--tight"><Pil kind="info">{unread} unread</Pil><Btn kind="ghost" size="sm" disabled={busy} onClick={() => void mark("/read-all", "All notifications read")}>Mark all read</Btn></span> : <Pil kind="grey">All read</Pil>}>
      {notices.length ? (
        <div className="card__body" style={{ gap: 0, padding: 0 }}>
          {notices.map((n, i) => (
            <div key={n.id} className="row row--top" style={{ padding: "var(--s-3) var(--s-4)", gap: "var(--s-3)", borderBottom: i < notices.length - 1 ? "1px solid var(--line-2)" : undefined, cursor: "pointer", background: n.read_at ? undefined : "var(--sky-bg, transparent)" }}
              onClick={() => { setOpen(open === n.id ? null : n.id); if (!n.read_at) void mark(`/${n.id}/read`, "Notification read"); }}>
              <span className="dot" style={{ background: n.read_at ? "var(--line-2)" : n.priority === "CRITICAL" || n.priority === "HIGH" ? "var(--red)" : "var(--sky)", marginTop: 7 }} />
              <div className="grow">
                <div className={n.read_at ? "" : "b600"}>{n.subject}</div>
                <div className="sub2" style={{ lineHeight: 1.5, whiteSpace: open === n.id ? "pre-wrap" : undefined, overflow: open === n.id ? undefined : "hidden", textOverflow: "ellipsis", display: open === n.id ? undefined : "-webkit-box", WebkitLineClamp: open === n.id ? undefined : 2, WebkitBoxOrient: "vertical" }}>{n.body}</div>
              </div>
              <span className="sub2" style={{ whiteSpace: "nowrap" }}>{when(n.created_at)}</span>
            </div>
          ))}
        </div>
      ) : <PBody><div className="sub2">Nothing for you yet. Important portal events — a window opening, a payment confirmed, a result published — appear here the moment they happen.</div></PBody>}
    </Panel>
  );
}
