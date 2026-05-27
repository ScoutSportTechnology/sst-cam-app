# Inspired by: https://blog.devops.dev/developing-flutter-applications-inside-a-devcontainer-4b13de5369e2

# --- Builder Stage ---
FROM --platform=linux/amd64 debian:bookworm-slim AS builder

# Avoid warnings by switching to noninteractive
ARG DEBIAN_FRONTEND=noninteractive

ENV ANDROID_SDK_ROOT=/android-sdk
ENV ANDROID_NDK_VERSION=28.2.13676358
ENV ANDROID_PLATFORM_VERSION=android-36
ENV ANDROID_BUILD_TOOLS_VERSION=34.0.0
ENV FLUTTER_SDK_ROOT=/flutter
ENV FLUTTER_SDK_VERSION=3.41.9-stable

RUN apt-get update \
    && apt-get -y install --no-install-recommends \
    wget \
    unzip \
    xz-utils \
    openjdk-17-jdk \
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

# Download and install Android Command Line Tools
RUN mkdir -p ${ANDROID_SDK_ROOT}/cmdline-tools \
    && wget -O commandlinetools.zip "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip" \
    && unzip commandlinetools.zip -d ${ANDROID_SDK_ROOT}/cmdline-tools \
    && mv ${ANDROID_SDK_ROOT}/cmdline-tools/cmdline-tools ${ANDROID_SDK_ROOT}/cmdline-tools/latest \
    && rm commandlinetools.zip

# Accept Android SDK licenses and install necessary components
RUN yes | ${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager --licenses && \
    ${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager "build-tools;${ANDROID_BUILD_TOOLS_VERSION}" "ndk;${ANDROID_NDK_VERSION}" "platform-tools" "platforms;${ANDROID_PLATFORM_VERSION}"

# Download and install Flutter
RUN mkdir -p ${FLUTTER_SDK_ROOT} \
    && wget -O flutter.tar.xz "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_SDK_VERSION}.tar.xz" \
    && tar xf flutter.tar.xz -C ${FLUTTER_SDK_ROOT} --strip-components=1 \
    && rm flutter.tar.xz

# --- Final Stage ---
FROM --platform=linux/amd64 debian:bookworm-slim AS final

ARG USER_UID=1000
ARG USER_GID=$USER_UID

ENV ANDROID_SDK_ROOT=/home/vscode/android-sdk
ENV FLUTTER_SDK_ROOT=/home/vscode/flutter
ENV PATH=$PATH:${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin
ENV PATH=$PATH:${ANDROID_SDK_ROOT}/platform-tools
ENV PATH=$PATH:${FLUTTER_SDK_ROOT}/bin

RUN dpkg --add-architecture amd64 \
    && apt-get update \
    && apt-get -y install --no-install-recommends \
    curl \
    git \
    unzip \
    xz-utils \
    zip \
    openjdk-17-jdk \
    libglu1-mesa \
    libc6:amd64 \
    socat \
    openssh-client \
    sudo \
    python3 \
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user
RUN groupadd --gid ${USER_GID} vscode \
    && useradd --uid ${USER_UID} --gid ${USER_GID} -m vscode \
    && echo vscode ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/vscode \
    && chmod 0440 /etc/sudoers.d/vscode

USER vscode

# Copy SDKs from the builder stage to the user's home directory
COPY --from=builder --chown=vscode:vscode /android-sdk ${ANDROID_SDK_ROOT}
COPY --from=builder --chown=vscode:vscode /flutter ${FLUTTER_SDK_ROOT}

# Set claude config directory permissions
RUN mkdir -p /home/vscode/.claude && chown -R vscode:vscode /home/vscode/.claude