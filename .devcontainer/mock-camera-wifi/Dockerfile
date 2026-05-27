# Stage 1: pull mediamtx binary from official image (pinned to v1.18.2)
FROM bluenviron/mediamtx:1.18.2 AS mediamtx-bin

# Stage 2: generate the looping sample video (H.264 baseline, 640x360, 15 fps, 10 s)
# Using a separate Alpine+ffmpeg stage keeps the build cache efficient — the video
# is only regenerated when this stage changes, not on every code change.
FROM alpine:3.21 AS video-gen
RUN apk add --no-cache ffmpeg
RUN ffmpeg -f lavfi -i "testsrc2=size=640x360:rate=15" \
    -t 10 \
    -c:v libx264 -profile:v baseline -level 3.0 \
    -b:v 500k \
    -an \
    -movflags +faststart \
    /tmp/sample.mp4

# Stage 3: final runtime image
FROM alpine:3.21

RUN apk add --no-cache ffmpeg python3 supervisor wget netcat-openbsd

COPY --from=mediamtx-bin /mediamtx /usr/local/bin/mediamtx
COPY --from=video-gen /tmp/sample.mp4 /srv/sample.mp4

COPY mediamtx.yml /etc/mediamtx/mediamtx.yml
COPY supervisord.conf /etc/supervisord.conf
COPY download_server.py /srv/download_server.py
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8554 8080

HEALTHCHECK --interval=10s --timeout=5s --start-period=15s --retries=3 \
    CMD wget -qO- http://localhost:8080/health || exit 1

ENTRYPOINT ["/entrypoint.sh"]

