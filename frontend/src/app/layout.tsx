import type { Metadata } from "next";
import "./globals.css";
import { ToastHost } from "@/components/proto/Toast";

/* IBM Plex is shipped with the portal (app/fonts.css → public/fonts), so neither the build nor a browser in
   Makurdi ever calls Google Fonts — a build once failed on the CI runner for want of that fetch. */
export const metadata: Metadata = {
  title: "MOAUM Portal",
  description: "MOAUM Unified University Portal — Rev. Fr. Moses Orshio Adasu University, Makurdi",
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
        <div id="app">{children}</div>
        {/* the one notification host, for every page — the shell's screens and the standalone ones alike */}
        <ToastHost />
      </body>
    </html>
  );
}
