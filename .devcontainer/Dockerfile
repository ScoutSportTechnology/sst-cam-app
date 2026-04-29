FROM ghcr.io/cirruslabs/flutter:stable

# Android SDK env — base image installs SDK at /opt/android-sdk-linux
ENV ANDROID_HOME=/opt/android-sdk-linux
ENV ANDROID_SDK_ROOT=/opt/android-sdk-linux
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

# Android SDK components — accept licenses non-interactively, fail loudly
RUN yes | sdkmanager --licenses >/dev/null
RUN sdkmanager \
    "platform-tools" \
    "platforms;android-35" \
    "build-tools;35.0.0" \
    "emulator" \
    "system-images;android-37.0;google_apis_playstore_ps16k;x86_64"

ENV PATH="/root/.local/bin:${PATH}"

WORKDIR /workspace
