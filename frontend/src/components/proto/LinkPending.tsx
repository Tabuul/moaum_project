"use client";

/**
 * A button-styled link (LinkBtn) says it is opening the next screen: from the click until the router has the new screen
 * (Next's own link status, useLinkStatus), the link reads data-busy and aria-busy — the busy buttons' spinner and the waiting
 * cursor (prototype.css: .btn[data-busy]) — so "Open", "View details" or "Continue application" never looks as if the click
 * did nothing. Rendered inside the link and never seen itself; a link whose screen was already prefetched is not pending.
 */
import { useEffect, useRef } from "react";
import { useLinkStatus } from "next/link";

export function LinkPending() {
  const { pending } = useLinkStatus();
  const mark = useRef<HTMLSpanElement>(null);
  useEffect(() => {
    const link = mark.current?.closest("a");
    if (!link) return;
    if (pending) {
      link.setAttribute("data-busy", "");
      link.setAttribute("aria-busy", "true");
    } else {
      link.removeAttribute("data-busy");
      link.removeAttribute("aria-busy");
    }
  }, [pending]);
  return <span ref={mark} hidden />;
}
