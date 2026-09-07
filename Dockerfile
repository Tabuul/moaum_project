# ══════════════════════════════════════════════════════════════════════
#  MOAUMPP portal service.
#
#  A Dockerfile rather than a buildpack, for one reason: the migrations
#  are psql scripts and the service runs them before it serves. The image
#  therefore has to carry the postgresql client, which is not something a
#  Node buildpack will decide to include on its own.
# ══════════════════════════════════════════════════════════════════════
FROM node:22-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends postgresql-client ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# the migrations, the read-only verification, and the runner
COPY db/V*.sql db/verify.sql db/migrate.sh ./db/
RUN chmod +x ./db/migrate.sh

# the service and the page it serves
COPY web/ ./web/
COPY public/ ./public/
COPY package.json ./

# nothing is installed: the service has no dependencies
ENV NODE_ENV=production
EXPOSE 8080

# Railway sets PORT. The migrations run as a pre-deploy command (see
# railway.json), not here, so a crash-looping container cannot run them
# over and over.
CMD ["node", "web/server.js"]
