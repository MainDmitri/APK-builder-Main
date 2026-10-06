# syntax=docker/dockerfile:1.7
#
# AppBuilder Engine — build worker image:
#   Node.js 24 LTS (npm / yarn / pnpm via corepack), JDK 17, Gradle 9.3.1,
#   Android SDK (platform 36, build-tools 36.0.0: aapt2, zipalign, apksigner),
#   librsvg (SVG icons) and the compiled engine (HTTP API + CLI).
#
# Build from the repository root (the image needs packages/ and engine/):
#   docker build -f engine/Dockerfile -t appbuilder-engine .
# Run:
#   docker run -d -p 8080:8080 -e ENGINE_TOKEN=change-me -v appbuilder-data:/data appbuilder-engine

ARG DART_VERSION=3.13.5

FROM dart:${DART_VERSION} AS engine-build
WORKDIR /src
COPY packages/appbuilder_core/pubspec.yaml packages/appbuilder_core/
COPY engine/pubspec.yaml engine/pubspec.lock engine/
RUN cd engine && dart pub get
COPY packages/appbuilder_core packages/appbuilder_core
COPY engine engine
RUN cd engine && dart pub get --offline && dart compile exe bin/engine.dart -o /out/appbuilder-engine

FROM eclipse-temurin:17-jdk-noble

ARG NODE_VERSION=24.21.0
ARG PNPM_VERSION=10.34.6
ARG YARN_VERSION=1.22.22
ARG GRADLE_VERSION=9.3.1
ARG CMDLINE_TOOLS_VERSION=11076708
ARG ANDROID_PLATFORM=36
ARG ANDROID_BUILD_TOOLS=36.0.0

ENV ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    GRADLE_USER_HOME=/opt/gradle-home \
    COREPACK_HOME=/opt/corepack \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
    APPBUILDER_DATA=/data \
    APPBUILDER_TEMPLATES=/opt/appbuilder/templates \
    PORT=8080 \
    PATH=/opt/node/bin:/opt/gradle/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:$PATH

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip xz-utils git util-linux procps librsvg2-bin fonts-dejavu-core \
 && rm -rf /var/lib/apt/lists/*

# Node.js LTS + corepack (yarn, pnpm)
RUN set -eux; \
    file="node-v${NODE_VERSION}-linux-x64.tar.xz"; \
    curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/${file}"; \
    curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt" | grep " ${file}\$" | sha256sum -c -; \
    mkdir -p /opt/node; \
    tar -xJf "${file}" -C /opt/node --strip-components=1; \
    rm "${file}"; \
    corepack enable; \
    corepack install -g "pnpm@${PNPM_VERSION}" "yarn@${YARN_VERSION}"; \
    node --version; npm --version; pnpm --version; yarn --version

# Gradle
RUN set -eux; \
    curl -fsSL -o /tmp/gradle.zip "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip"; \
    echo "$(curl -fsSL "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip.sha256")  /tmp/gradle.zip" | sha256sum -c -; \
    unzip -q /tmp/gradle.zip -d /opt; \
    mv "/opt/gradle-${GRADLE_VERSION}" /opt/gradle; \
    rm /tmp/gradle.zip

# Android SDK: command-line tools, platform, build-tools (aapt2, zipalign, apksigner)
RUN set -eux; \
    mkdir -p "${ANDROID_HOME}/cmdline-tools"; \
    curl -fsSL -o /tmp/cmdline-tools.zip "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip"; \
    unzip -q /tmp/cmdline-tools.zip -d /tmp/cmdline-tools; \
    mv /tmp/cmdline-tools/cmdline-tools "${ANDROID_HOME}/cmdline-tools/latest"; \
    rm -rf /tmp/cmdline-tools /tmp/cmdline-tools.zip; \
    yes | sdkmanager --licenses > /dev/null; \
    sdkmanager --install "platform-tools" "platforms;android-${ANDROID_PLATFORM}" "build-tools;${ANDROID_BUILD_TOOLS}"; \
    test -x "${ANDROID_HOME}/build-tools/${ANDROID_BUILD_TOOLS}/zipalign"; \
    test -x "${ANDROID_HOME}/build-tools/${ANDROID_BUILD_TOOLS}/apksigner"

RUN useradd --create-home --shell /bin/bash appbuilder \
 && mkdir -p /data "${GRADLE_USER_HOME}" "${COREPACK_HOME}" \
 && chown -R appbuilder:appbuilder /data "${GRADLE_USER_HOME}" "${COREPACK_HOME}" "${ANDROID_HOME}"

COPY --from=engine-build /out/appbuilder-engine /usr/local/bin/appbuilder-engine
COPY engine/templates /opt/appbuilder/templates
COPY engine/samples /opt/appbuilder/samples

USER appbuilder
WORKDIR /data

# Warm-up: build a web and a native sample once, so the Android Gradle Plugin,
# Kotlin, AndroidX and Compose artifacts are cached inside the image.
RUN appbuilder-engine doctor \
 && appbuilder-engine selftest --samples /opt/appbuilder/samples --only static-notes --only native-compose --out /tmp/warmup \
 && rm -rf /tmp/warmup /data/*

EXPOSE 8080
VOLUME ["/data"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s CMD curl -fs "http://127.0.0.1:${PORT}/health" > /dev/null || exit 1
ENTRYPOINT ["appbuilder-engine"]
CMD ["serve"]
