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

ENV PATH="$PATH:/home/vscode/.pub-cache/bin"

RUN yes | sdkmanager --licenses >/dev/null
RUN sdkmanager \
    "platform-tools" \
    "platforms;android-35" \
    "build-tools;35.0.0"


ARG USER_UID=1000
ARG USER_GID=1000

RUN if getent group ${USER_GID} >/dev/null 2>&1; then \
      groupmod -n vscode $(getent group ${USER_GID} | cut -d: -f1); \
    else \
      groupadd --gid ${USER_GID} vscode; \
    fi \
  && if getent passwd ${USER_UID} >/dev/null 2>&1; then \
      usermod -l vscode -d /home/vscode -m $(getent passwd ${USER_UID} | cut -d: -f1); \
    else \
      useradd --uid ${USER_UID} --gid ${USER_GID} -m --shell /bin/bash vscode; \
    fi

ENV PATH="/root/.local/bin:${PATH}"

RUN mkdir -p /home/vscode/.claude && chown -R vscode:vscode /home/vscode/.claude

WORKDIR /workspace
RUN chown vscode:vscode /workspace
RUN chown vscode:vscode /opt/android-sdk
RUN chown -R vscode:vscode /opt/flutter

USER vscode
