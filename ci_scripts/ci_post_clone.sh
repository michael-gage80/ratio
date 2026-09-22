#!/bin/sh
# Xcode Cloud: restores the Firebase client config, which isn't committed.
# Set GOOGLE_SERVICE_INFO_PLIST (secret) in the workflow's environment to the output
# of: base64 -i ratio/GoogleService-Info.plist
set -eu

if [ -z "${GOOGLE_SERVICE_INFO_PLIST:-}" ]; then
  echo "error: GOOGLE_SERVICE_INFO_PLIST is not set, so the build would crash on launch." >&2
  exit 1
fi

echo "$GOOGLE_SERVICE_INFO_PLIST" | base64 --decode > "$CI_PRIMARY_REPOSITORY_PATH/ratio/GoogleService-Info.plist"
plutil -lint "$CI_PRIMARY_REPOSITORY_PATH/ratio/GoogleService-Info.plist"
