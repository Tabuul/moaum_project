# ══════════════════════════════════════════════════════════════════════
#  moaum-portal — the Next.js frontend.
#
#  Built from the REPOSITORY ROOT (docker build -f frontend/Dockerfile .)
#  so that every service in this repository is built the same way.
#  Next's standalone output is a self-contained server: node, the
#  compiled pages, and only the modules they import. No devDependencies,
#  no source, no build cache in the image that serves.
# ══════════════════════════════════════════════════════════════════════
FROM node:22-alpine AS deps
WORKDIR /app
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci --no-audit --no-fund

FROM node:22-alpine AS build
WORKDIR /app
ENV NEXT_TELEMETRY_DISABLED=1
COPY --from=deps /app/node_modules ./node_modules
COPY frontend/ ./
# IBM Plex is fetched here, at build time, and served from this image —
# the portal never calls Google Fonts from a browser.
RUN npm run build

# ── runtime ───────────────────────────────────────────────────────────
FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
# "::" listens on both stacks; Railway's private network is IPv6.
ENV HOSTNAME="::"
ENV PORT=3000

RUN addgroup -S portal && adduser -S portal -G portal
COPY --from=build --chown=portal:portal /app/public ./public
COPY --from=build --chown=portal:portal /app/.next/standalone ./
COPY --from=build --chown=portal:portal /app/.next/static ./.next/static
USER portal

EXPOSE 3000
CMD ["node", "server.js"]
