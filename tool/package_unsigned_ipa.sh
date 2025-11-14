#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-build/ios/iphoneos/Runner.app}"
OUT_DIR="${2:-build/ios/ipa}"
IPA_NAME="${3:-Runner.ipa}"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "App bundle not found at ${APP_PATH}." >&2
  exit 1
fi

rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}/Payload"
cp -R "${APP_PATH}" "${OUT_DIR}/Payload/Runner.app"

pushd "${OUT_DIR}" >/dev/null
/usr/bin/zip -qry "${IPA_NAME}" Payload
popd >/dev/null

rm -rf "${OUT_DIR}/Payload"

DSYM_SRC="${APP_PATH}.dSYM"
if [[ -d "${DSYM_SRC}" ]]; then
  cp -R "${DSYM_SRC}" "${OUT_DIR}/Runner.app.dSYM"
fi
