#!/bin/bash
# Headless archive preparation only. This command never exports or uploads a build.
set -euo pipefail
cd "$(dirname "$0")/.."

archive_mode="${1:---unsigned}"
case "$archive_mode" in
  --unsigned) signing=(CODE_SIGNING_ALLOWED=NO) ;;
  --signed)
    if [[ ! "${GRADEMAXXING_DEVELOPMENT_TEAM:-}" =~ ^[A-Z0-9]{10}$ ]]; then
      echo 'Set GRADEMAXXING_DEVELOPMENT_TEAM to the owning Apple Developer Team ID.' >&2
      exit 1
    fi
    signing=("DEVELOPMENT_TEAM=$GRADEMAXXING_DEVELOPMENT_TEAM" -allowProvisioningUpdates)
    ;;
  *) echo 'Usage: bash scripts/archive.sh [--unsigned|--signed]' >&2; exit 1 ;;
esac

python3 scripts/release-preflight.py
python3 - <<'PY'
import re, subprocess
try:
    version = subprocess.check_output(['xcodebuild', '-version'], text=True, stderr=subprocess.STDOUT)
except subprocess.CalledProcessError:
    raise SystemExit('Full Xcode 26 or later is required. Set DEVELOPER_DIR to the installed Xcode.')
match = re.search(r'^Xcode (\d+)', version)
if not match or int(match[1]) < 26:
    raise SystemExit('Full Xcode 26 or later is required. Set DEVELOPER_DIR to the installed Xcode.')
print(version.strip())
PY

archive_path="$PWD/.build/release/Grademaxxing.xcarchive"
if [[ -e "$archive_path" ]]; then
  echo 'Archive already exists. Move it aside before creating another release archive.' >&2
  exit 1
fi
xcodebuild archive -project Grademaxxing.xcodeproj -scheme Grademaxxing \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$PWD/.build/release/DerivedData" -archivePath "$archive_path" \
  "${signing[@]}"
if [[ "$archive_mode" == --unsigned ]]; then
  python3 scripts/release-preflight.py --archive "$archive_path" --allow-unsigned
else
  python3 scripts/release-preflight.py --archive "$archive_path"
fi
