#!/bin/zsh
# Mac App Store build: sandboxed archive -> signed .pkg (export) or direct upload to App Store Connect.
# Usage: scripts/appstore.sh <version> [upload]
# Needs .release.env (TEAM_ID, ASC_KEY, ASC_KEY_ID, ASC_ISSUER). Manual signing: "Apple Distribution" cert +
# the "DotBar Mac App Store" provisioning profile (created via the ASC API), pkg signed with the
# Mac Installer Distribution cert. The app record for uk.trinh.DotBar must exist in App Store Connect before `upload`.
set -euo pipefail
VERSION="${1:?usage: appstore.sh <version> [upload]}"; MODE="${2:-export}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
[[ -f .release.env ]] && source .release.env
: "${TEAM_ID:?}" "${ASC_KEY:?}" "${ASC_KEY_ID:?}" "${ASC_ISSUER:?}"
MAS_PROFILE="${MAS_PROFILE:-DotBar Mac App Store uk}"
INSTALLER_CERT="${INSTALLER_CERT:-3rd Party Mac Developer Installer}"
OUT="$ROOT/dist/appstore"; ARCHIVE="$OUT/DotBar.xcarchive"
BUILD_NO=$(git rev-list --count HEAD)
rm -rf "$OUT"; mkdir -p "$OUT"
sed -i '' -E "s/MARKETING_VERSION: \"[0-9.]+\"/MARKETING_VERSION: \"$VERSION\"/; s/CURRENT_PROJECT_VERSION: \"[0-9]+\"/CURRENT_PROJECT_VERSION: \"$BUILD_NO\"/" project.yml
xcodegen generate >/dev/null

echo "==> Archive (sandboxed, Apple Distribution)"
xcodebuild -project DotBar.xcodeproj -scheme DotBar -configuration Release \
  -archivePath "$ARCHIVE" -derivedDataPath build/appstore \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER" \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_IDENTITY="Apple Distribution" \
  PROVISIONING_PROFILE_SPECIFIER="$MAS_PROFILE" \
  CODE_SIGN_ENTITLEMENTS="DotBar/Resources/DotBar-AppStore.entitlements" ENABLE_APP_SANDBOX=YES \
  ENABLE_HARDENED_RUNTIME=NO \
  archive 2>&1 | grep -E "error:|warning: .*(sign|entitle)|ARCHIVE" || true
[[ -d "$ARCHIVE" ]] || { echo "archive failed"; exit 1; }

DEST="export"; [[ "$MODE" == "upload" ]] && DEST="upload"
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$DEST</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Apple Distribution</string>
  <key>installerSigningCertificate</key><string>$INSTALLER_CERT</string>
  <key>provisioningProfiles</key><dict><key>uk.trinh.DotBar</key><string>$MAS_PROFILE</string></dict>
  <key>uploadSymbols</key><true/>
</dict></plist>
PLIST
echo "==> Export ($DEST)"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OUT/ExportOptions.plist" -exportPath "$OUT" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER" \
  2>&1 | grep -vE "^\s*$" | tail -8
ls -la "$OUT"/*.pkg 2>/dev/null || true
APP="$ARCHIVE/Products/Applications/DotBar.app"
echo "==> Entitlements in archive:"; codesign -d --entitlements :- "$APP" 2>/dev/null | grep -E "app-sandbox|network|files|calendars" | sed 's/^\s*//'
