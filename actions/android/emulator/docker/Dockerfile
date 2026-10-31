# syntax=docker/dockerfile:1
# Android emulator image for any API level above the Android 14 where budtmo/docker-android stops (35, 36, 36.1...).
# Approach adapted from https://github.com/Hashim-K/android-agent-lab (MIT License, (c) Hashim-K).
# Image android-emulator:api<ANDROID_API>, built by the CI action android/emulator (github-actions repository, folder
# actions/android/emulator/docker) when it is missing, or by hand with docker compose (service android-emulator, profile build).
# This file exists in both places and MUST stay byte-identical (the action labels the image with the hash of its copy).
FROM budtmo/docker-android:emulator_14.0@sha256:1bffbbed5d530284dd355eb73e863411b4a761bc55a00fa1e49fe4a013b6b24a

# API level of the system image (system-images;android-<API>;google_apis;x86_64) and the Android version it is known as
ARG ANDROID_API=36
ARG ANDROID_VERSION=16.0

USER 0

# the licenses are already accepted in the base; channel 0 = stable (36.1 is a minor SDK release of Android 16)
RUN sdkmanager --channel=0 "system-images;android-${ANDROID_API};google_apis;x86_64"

# the launcher of budtmo has a fixed table version -> API level that stops at 14: the wanted one is added
RUN ANDROID_API="${ANDROID_API}" ANDROID_VERSION="${ANDROID_VERSION}" python3 - <<'PY'
import os
from pathlib import Path
path = Path('/home/androidusr/docker-android/cli/src/device/emulator.py')
source = path.read_text()
anchor = '    API_LEVEL = {\n'
assert source.count(anchor) == 1, 'table of the base image changed: review this adapter'
line = '        "%s": "%s",\n' % (os.environ['ANDROID_VERSION'], os.environ['ANDROID_API'])
path.write_text(source.replace(anchor, anchor + line))
for directory in ('emulator', '.android'):
    target = Path('/home/androidusr') / directory
    target.mkdir(exist_ok=True)
    os.chown(target, 1300, 1301)
PY

# Android 16 fills the 550m data partition of budtmo (no room for the APK): 4 GB, sparse on the host
ENV EMULATOR_ANDROID_VERSION=${ANDROID_VERSION} \
    EMULATOR_API_LEVEL=${ANDROID_API} \
    EMULATOR_DATA_PARTITION=4096m

USER 1300:1301
