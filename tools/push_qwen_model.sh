#!/usr/bin/env bash
# Puts the small Qwen model into the Android app's private files folder.
#
# This does NOT add the model to the APK or to GitHub. The model is too big for
# either. It only copies an existing local file onto a connected Android phone.
#
# USE THIS ONLY WITH A DEBUG BUILD OF THE APP INSTALLED.
# A Play Store (release) build will not allow the `run-as` step below.
#
# Run from the project root:
#   ./tools/push_qwen_model.sh
#
# If the phone is not connected, plug it in with USB, unlock it, and tap
# "Allow USB debugging" when Android asks.

set -euo pipefail

PACKAGE="com.helpmum.mamaBot"
MODEL_NAME="Qwen3.5-0.8B_mixed48_h1024.litertlm"
EXPECTED_SIZE="486539264"
EXPECTED_SHA="61c65dbcaa86461184df1b60a82941c5d3e65fb535411d1b2192ccf222e98b35"
SOURCE_FILE="local_models/${MODEL_NAME}"
TEMP_PATH="/data/local/tmp/qwen-model.litertlm"
APP_FILES="/data/user/0/${PACKAGE}/files"

echo "Step 1: checking the model file on this computer..."
if [ ! -f "$SOURCE_FILE" ]; then
  echo "ERROR: $SOURCE_FILE is missing."
  echo "Copy the downloaded .litertlm file into the local_models/ folder first."
  exit 1
fi

ACTUAL_SIZE=$(stat -f%z "$SOURCE_FILE")
if [ "$ACTUAL_SIZE" != "$EXPECTED_SIZE" ]; then
  echo "ERROR: wrong file size ($ACTUAL_SIZE). Expected $EXPECTED_SIZE."
  exit 1
fi

ACTUAL_SHA=$(shasum -a 256 "$SOURCE_FILE" | awk '{print $1}')
if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
  echo "ERROR: the model file is damaged (SHA-256 mismatch)."
  echo "Download it again."
  exit 1
fi
echo "OK: model file is complete and matches the manifest."

echo "Step 2: checking Android connection..."
if ! command -v adb >/dev/null 2>&1; then
  echo "ERROR: adb is not installed or not in your PATH."
  echo "Install Android Studio / platform-tools, then try again."
  exit 1
fi

DEVICES=$(adb devices | sed '1d' | grep -c $'\tdevice' || true)
if [ "$DEVICES" -eq 0 ]; then
  echo "ERROR: no Android phone connected."
  echo "Plug in the phone by USB, unlock it, and allow USB debugging."
  exit 1
fi
echo "OK: phone connected."

echo "Step 3: checking the debug app is installed..."
if ! adb shell pm list packages | grep -q "^package:${PACKAGE}$"; then
  echo "ERROR: $PACKAGE is not installed on this phone."
  echo "Open the project in Android Studio and press Run, or run: flutter install"
  echo "Make sure it is a DEBUG build, not the Play Store build."
  exit 1
fi
echo "OK: debug app installed."

echo "Step 4: copying the model to the phone (this takes a minute)..."
adb push "$SOURCE_FILE" "$TEMP_PATH"
adb shell chmod 644 "$TEMP_PATH"

echo "Step 5: moving it into the app's private files folder..."
# A freshly installed app may not have created its files/ folder yet.
if ! adb shell "run-as ${PACKAGE} mkdir -p ${APP_FILES}"; then
  echo "ERROR: run-as failed. This means the installed app is NOT a debug build."
  echo "Install a debug build (Android Studio Run / flutter install --debug) and retry."
  exit 1
fi
if ! adb shell "run-as ${PACKAGE} cp ${TEMP_PATH} ${APP_FILES}/${MODEL_NAME}"; then
  echo "ERROR: could not copy the model into the app's files folder."
  exit 1
fi

echo "Step 6: verifying..."
adb shell "run-as ${PACKAGE} ls -l ${APP_FILES}/${MODEL_NAME}"
adb shell rm -f "$TEMP_PATH"

echo "DONE. The app will now find the model at:"
echo "  /data/user/0/${PACKAGE}/files/${MODEL_NAME}"
echo "Open the app and start an offline chat."
