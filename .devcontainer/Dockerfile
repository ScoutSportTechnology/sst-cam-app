FROM ghcr.io/cirruslabs/flutter:stable

# Android SDK environment (set by base image; extend if needed)
ENV ANDROID_HOME=/opt/android-sdk
ENV PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator"

# System tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    protobuf-compiler \
    just \
    git \
    curl \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Dart protoc plugin
RUN dart pub global activate protoc_plugin

ENV PATH="$PATH:/root/.pub-cache/bin"

# Android SDK components (platform + build tools)
RUN sdkmanager --install \
    "platform-tools" \
    "platforms;android-35" \
    "build-tools;35.0.0" \
    2>/dev/null || true

WORKDIR /workspace
