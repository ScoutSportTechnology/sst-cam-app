# Stage 1: pull mediamtx binary from official image (pinned to v1.18.2)
FROM bluenviron/mediamtx:1.18.2 AS mediamtx-bin

# Stage 2: final runtime image.
# The sample video is no longer generated here — docker-compose mounts the
# canonical repo video (lib/mock/emulator/mock-video.mp4) onto /srv/sample.mp4
# so the container serves the exact bytes the app bundles.
FROM alpine:3.21

RUN apk add --no-cache ffmpeg python3 supervisor wget netcat-openbsd

COPY --from=mediamtx-bin /mediamtx /usr/local/bin/mediamtx

COPY mediamtx.yml /etc/mediamtx/mediamtx.yml
COPY supervisord.conf /etc/supervisord.conf
COPY download_server.py /srv/download_server.py
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8554 8080

# Probe BOTH planes: HTTP download (8080) and RTSP preview (8554). A dead
# mediamtx/ffmpeg must fail the check even if the HTTP server is still up.
HEALTHCHECK --interval=10s --timeout=5s --start-period=15s --retries=3 \
    CMD wget -qO- http://localhost:8080/health && nc -z localhost 8554 || exit 1

ENTRYPOINT ["/entrypoint.sh"]

