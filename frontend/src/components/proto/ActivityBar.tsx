"use client";

/**
 * The thin bar along the top of every page while something the person asked for is still loading: an act sent to the API,
 * a sign-in or sign-out, the next screen after a link. It is installed once, in the root layout, and installs the one
 * watch over the page's requests (lib/activity) that the buttons read as well. The bar is there exactly while a request is
 * in flight and goes the moment the last one settles; it says nothing about how far along a request is (there is no such
 * figure to give), it only runs. A request answered at once does not flash it: the stylesheet lets it appear only after a
 * short moment. Background polls, prefetches and the examination room never show it.
 */
import { useEffect, useSyncExternalStore } from "react";
import { inFlight, installActivity, subscribe } from "@/lib/activity";

export function ActivityBar() {
  useEffect(() => { installActivity(); }, []);
  const loading = useSyncExternalStore(subscribe, () => inFlight() > 0, () => false);
  return loading ? <div className="actbar" aria-hidden="true" /> : null;
}
