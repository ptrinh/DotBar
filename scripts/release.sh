#!/bin/zsh
# Release DotBar: build (Developer ID, hardened runtime) -> notarize -> staple -> zip -> GitHub Release -> update Homebrew cask.
# Usage: scripts/release.sh 0.1.0
# Credentials come from the environment (or an untracked .release.env next to this repo root):
#   SIGN_ID      "Developer ID Application: Name (TEAMID)"
#   TEAM_ID      Apple team id
#   ASC_KEY      path to App Store Connect API key (.p8)
#   ASC_KEY_ID   key id
#   ASC_ISSUER   issuer id
# Optional: TAP_DIR (default ../homebrew-tap), NOTARIZE=0 to skip notarization.
set -euo pipefail
VERSION="${1:?usage: release.sh <version>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -f "$ROOT/.release.env" ]] && source "$ROOT/.release.env"
: "${SIGN_ID:?set SIGN_ID}" "${TEAM_ID:?set TEAM_ID}"
if [[ "${NOTARIZE:-1}" == "1" ]]; then : "${ASC_KEY:?set ASC_KEY}" "${ASC_KEY_ID:?set ASC_KEY_ID}" "${ASC_ISSUER:?set ASC_ISSUER}"; fi
TAP_DIR="${TAP_DIR:-$ROOT/../homebrew-tap}"
REPO="ptrinh/DotBar"
OUT="$ROOT/dist"; APP="$OUT/DotBar.app"; ZIP="$OUT/DotBar-$VERSION.zip"

cd "$ROOT"
echo "==> Version $VERSION"
sed -i '' -E "s/MARKETING_VERSION: \"[0-9.]+\"/MARKETING_VERSION: \"$VERSION\"/" project.yml
BUILD_NO=$(git rev-list --count HEAD)
sed -i '' -E "s/CURRENT_PROJECT_VERSION: \"[0-9]+\"/CURRENT_PROJECT_VERSION: \"$BUILD_NO\"/" project.yml
xcodegen generate >/dev/null

echo "==> Building Release"
rm -rf "$OUT" build/Build/Products/Release; mkdir -p "$OUT"
xcodebuild -project DotBar.xcodeproj -scheme DotBar -configuration Release -derivedDataPath build \
  CODE_SIGN_IDENTITY="$SIGN_ID" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$TEAM_ID" \
  ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
  build 2>&1 | grep -E "error:|BUILD" || true
cp -R build/Build/Products/Release/DotBar.app "$APP"
codesign --verify --deep --strict "$APP"
codesign -dv "$APP" 2>&1 | grep -E "Authority=Developer ID|flags=.*runtime" | head -2

if [[ "${NOTARIZE:-1}" == "1" ]]; then
  echo "==> Notarizing"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --key "$ASC_KEY" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER" --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
fi
ditto -c -k --keepParent "$APP" "$ZIP"
spctl -a -vv "$APP" 2>&1 | head -1 || true
SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')
echo "==> $ZIP  sha256=$SHA"

echo "==> Commit + tag + GitHub release"
git add project.yml && git commit -qm "Release v$VERSION" || true
git tag -f "v$VERSION" && git push -q origin main --tags
gh release create "v$VERSION" "$ZIP" --repo "$REPO" --title "DotBar $VERSION" --generate-notes 2>/dev/null \
  || gh release upload "v$VERSION" "$ZIP" --repo "$REPO" --clobber

echo "==> Homebrew cask"
[[ -d "$TAP_DIR/.git" ]] || git clone -q "https://github.com/ptrinh/homebrew-tap.git" "$TAP_DIR"
( cd "$TAP_DIR" && git pull -q --rebase )
cat > "$TAP_DIR/Casks/dotbar.rb" <<CASK
cask "dotbar" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/ptrinh/DotBar/releases/download/v#{version}/DotBar-#{version}.zip"
  name "DotBar"
  desc "Custom text and colored status dots for the macOS menu bar"
  homepage "https://github.com/ptrinh/DotBar"

  depends_on macos: :sonoma

  app "DotBar.app"

  zap trash: [
    "~/Library/Application Support/DotBar",
    "~/Library/Preferences/com.ptrinh.DotBar.plist",
  ]
end
CASK
( cd "$TAP_DIR" && git add Casks/dotbar.rb && git commit -qm "dotbar $VERSION" && git push -q )
echo "==> Done. Install: brew install --cask ptrinh/tap/dotbar"
# Local convenience: if the brew-installed app is present, upgrade and relaunch it.
if [[ -d /Applications/DotBar.app ]] && command -v brew >/dev/null; then
  brew update >/dev/null 2>&1 || true
  brew upgrade --cask dotbar >/dev/null 2>&1 && { pkill -x DotBar || true; sleep 1; open /Applications/DotBar.app; echo "==> Relaunched /Applications/DotBar.app $(defaults read /Applications/DotBar.app/Contents/Info.plist CFBundleShortVersionString)"; }
fi
