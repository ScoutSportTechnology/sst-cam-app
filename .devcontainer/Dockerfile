FROM ghcr.io/cirruslabs/flutter:stable

# Android SDK env — base image installs SDK at /opt/android-sdk-linux
ENV ANDROID_HOME=/opt/android-sdk-linux
ENV ANDROID_SDK_ROOT=/opt/android-sdk-linux
ENV PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools"

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
    "build-tools;35.0.0"

# Node.js (required for Claude Code)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Claude Code
RUN curl -fsSL https://claude.ai/install.sh | bash
#RUN curl -fsSL https://claude.ai/install.sh | bash # Install Claude CLI if needed
ENV PATH="/root/.local/bin:${PATH}"

WORKDIR /workspace
