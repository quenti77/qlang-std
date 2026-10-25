# One image for the three processes (web, worker, scheduler): the command decides which one runs.
#   docker build -f examples/deploy/Dockerfile -t myapp .
FROM debian:bookworm-slim
ARG QLANG_VERSION=0.55.0
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL https://raw.githubusercontent.com/quenti77/qlang/main/install.sh \
    | QLANG_INSTALL_DIR=/usr/local/bin sh -s -- --version "${QLANG_VERSION}"
RUN useradd --system --create-home --home-dir /app app && mkdir /data && chown app /data
WORKDIR /app
COPY --chown=app:app . /app
USER app
ENV QLANG_LOG_FORMAT=json
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s CMD curl -fs http://127.0.0.1:8080/health/live || exit 1
# `--bind 0.0.0.0` is needed in a container; a proxy in front terminates TLS
CMD ["qlang", "serve", "examples/deploy/main.q", "--bind", "0.0.0.0", "--port", "8080", "--workers", "2", "--compress"]
