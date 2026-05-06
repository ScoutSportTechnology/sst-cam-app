FROM mingc/android-build-box:latest

ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools"

RUN apt-get update && apt-get install -y --no-install-recommends \
    protobuf-compiler \
    git \
    curl \
    unzip \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

RUN curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to /usr/local/bin

RUN dart pub global activate protoc_plugin
ENV PATH="$PATH:/root/.pub-cache/bin"

RUN yes | sdkmanager --licenses >/dev/null
RUN sdkmanager \
    "platform-tools" \
    "platforms;android-35" \
    "build-tools;35.0.0"

ENV PATH="/root/.local/bin:${PATH}"

WORKDIR /workspace
