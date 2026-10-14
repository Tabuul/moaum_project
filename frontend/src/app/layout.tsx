import type { Metadata, Viewport } from "next";
import "./globals.css";
import { ToastHost } from "@/components/proto/Toast";
import { ActivityBar } from "@/components/proto/ActivityBar";

/* IBM Plex is shipped with the portal (app/fonts.css → public/fonts), so neither the build nor a browser in
   Makurdi ever calls Google Fonts — a build once failed on the CI runner for want of that fetch. */
export const metadata: Metadata = {
  title: "MOAUM Portal",
  description: "MOAUM Unified University Portal — Rev. Fr. Moses Orshio Adasu University, Makurdi",
};

/* the phone's frame: the page may reach under a notch (the top bar and the drawer keep clear of it with the safe-area
   insets), and the browser's own bar takes the University's navy. Zoom is never disabled. */
export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  themeColor: "#0B3345",
};

/* The page is the prototype's page: #app holds the shell, and the shell is
   rendered by each screen with its own title (components/proto/Shell). */
/* the display density the person chose (components/proto/AccountMenu), read from its cookie before the page paints so it
   opens at that density without a flicker; Compact when nothing is chosen. The attribute is set here, outside React, hence
   suppressHydrationWarning on <html> only. */
const DENSITY = `try{var m=document.cookie.match(/(?:^|; )moaum_density=(normal|compact|very)(?:;|$)/);if(m)document.documentElement.setAttribute("data-density",m[1])}catch(e){}`;

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: DENSITY }} />
      </head>
      <body>
        {/* the one watch over what the person asked for and is waiting for: the bar along the top while it loads, and
            every button's busy state (lib/activity) */}
        <ActivityBar />
        <div id="app">{children}</div>
        {/* the one notification host, for every page — the shell's screens and the standalone ones alike */}
        <ToastHost />
      </body>
    </html>
  );
}
