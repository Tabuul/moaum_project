"use client";

/**
 * What this browser searched for, most recent first (proto/part22's "Recent
 * searches", "Yours, this session"). It is kept on the computer that did the
 * searching and nowhere else — the University's own record of who looked a
 * person up is the audit trail, not this list.
 *
 * An external store rather than component state: the search screen reads it
 * during render and adds to it after one, and React subscribes to the change.
 */
import { useSyncExternalStore } from "react";

const KEY = "moaum_recent_searches";
const KEEP = 6;
const NONE: string[] = [];

const listeners = new Set<() => void>();
const cache = { held: NONE, loaded: false };

function read(): string[] {
  try {
    const raw = window.localStorage.getItem(KEY);
    const parsed: unknown = raw ? JSON.parse(raw) : [];
    if (!Array.isArray(parsed)) return NONE;
    return parsed.filter((x): x is string => typeof x === "string").slice(0, KEEP);
  } catch {
    return NONE;
  }
}

function snapshot(): string[] {
  if (!cache.loaded) {
    cache.held = read();
    cache.loaded = true;
  }
  return cache.held;
}

function serverSnapshot(): string[] {
  return NONE;
}

function subscribe(notify: () => void): () => void {
  listeners.add(notify);
  return () => {
    listeners.delete(notify);
  };
}

/** Put a term at the top of the list, keeping the last six. */
export function rememberSearch(term: string): void {
  const wanted = term.trim();
  if (!wanted) return;
  const held = snapshot();
  const next = [wanted, ...held.filter((r) => r !== wanted)].slice(0, KEEP);
  if (next.length === held.length && next.every((r, i) => r === held[i])) return;
  cache.held = next;
  try {
    window.localStorage.setItem(KEY, JSON.stringify(next));
  } catch {
    /* a browser that keeps nothing is not an error */
  }
  listeners.forEach((notify) => notify());
}

export function useRecentSearches(): string[] {
  return useSyncExternalStore(subscribe, snapshot, serverSnapshot);
}
