# ══════════════════════════════════════════════════════════════════════
#  moaum-api — the Spring Boot service.
#
#  Built from the REPOSITORY ROOT (docker build -f api/Dockerfile .; on
#  Railway, RAILWAY_DOCKERFILE_PATH=api/Dockerfile with no root directory), so
#  that the runtime image can carry db/ as well: this service owns the
#  schema, and Railway runs `bash db/migrate.sh` from inside this image as
#  the pre-deploy command before a new version is allowed to serve.
#
#  Two stages: Maven builds the jar; a JRE image runs it. The runtime
#  image carries the postgresql client for the migrations and nothing else.
# ══════════════════════════════════════════════════════════════════════
FROM eclipse-temurin:21-jdk AS build
WORKDIR /build

# dependencies first, so a source change does not re-download the world
COPY api/mvnw api/pom.xml ./
COPY api/.mvn .mvn
RUN chmod +x mvnw && ./mvnw -B -ntp -q dependency:go-offline || true

COPY api/src src
RUN ./mvnw -B -ntp -q -DskipTests package \
 && mv target/portal-api-*.jar target/app.jar

# ── runtime ───────────────────────────────────────────────────────────
FROM eclipse-temurin:21-jre

RUN apt-get update \
 && apt-get install -y --no-install-recommends postgresql-client ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# the migrations, the read-only verification, and the runner (pre-deploy)
COPY db/V*.sql db/verify.sql db/migrate.sh db/demo.sql db/demo.sh ./db/
RUN chmod +x ./db/migrate.sh ./db/demo.sh

COPY --from=build /build/target/app.jar ./app.jar

# The JVM sizes itself to the container rather than to the host.
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75 -XX:+UseSerialGC -Djava.security.egd=file:/dev/./urandom"
ENV PORT=8081
EXPOSE 8081

# Railway sets PORT; the service reads it. The migrations run as a
# pre-deploy command (api/railway.json), never at container start.
CMD ["java", "-jar", "app.jar"]
