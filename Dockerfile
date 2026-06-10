# Multi-stage build: compile Dart server to a native binary.
FROM dart:stable AS build

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN dart pub get

COPY . .
RUN dart compile exe bin/server.dart -o server

# Minimal runtime image with SQLite libraries.
FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends libsqlite3-0 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=build /app/server /app/server

# Railway injects PORT at runtime. DB_PATH should point to a mounted volume in prod.
ENV DB_PATH=/data/quickslot.db

EXPOSE 8080

CMD ["/app/server"]
