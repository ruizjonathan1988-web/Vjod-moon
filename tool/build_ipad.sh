#!/usr/bin/env bash
# VJOD for the iPad: an unsigned .ipa (vjod-ipad.ipa). AltStore, or Xcode with
# a free Apple account, signs it on the user's side (renewed every 7 days).
# Used by perso-apk.yml (release ipad-latest) and ipad-essai.yml.
#
# VERSION   : VJOD version (4.5), written as the app version.
# BUILD_NUM : build number, rises with every build so AltStore sees the update.
set -euo pipefail
: "${VERSION:?}" "${BUILD_NUM:?}"

# VJOD's name, its own bundle id, and no capability a free account refuses
# (push, CarPlay, multicast): RunnerSideload.entitlements is empty.
cat > ios/Flutter/Local.xcconfig <<XC
MOONFIN_BUNDLE_IDENTIFIER = org.vjod.ipad
MOONFIN_BUNDLE_DISPLAY_NAME = VJOD
MOONFIN_ENTITLEMENTS = Runner/RunnerSideload.entitlements
MOONFIN_DEVELOPMENT_TEAM =
XC
plutil -replace CFBundleName -string VJOD ios/Runner/Info.plist
# Permission prompts in French, under VJOD's name.
for key in NSLocalNetworkUsageDescription:"VJOD utilise le réseau local pour trouver vos serveurs." \
           NSMicrophoneUsageDescription:"VJOD utilise le micro pour la recherche vocale." \
           NSSpeechRecognitionUsageDescription:"VJOD utilise la reconnaissance vocale pour la recherche." \
           NSPhotoLibraryUsageDescription:"VJOD accède à vos photos seulement si vous choisissez une image." \
           NSCameraUsageDescription:"VJOD utilise l'appareil photo seulement si vous prenez une image." \
           NSLocationWhenInUseUsageDescription:"VJOD ne suit pas votre position." \
           NSLocationAlwaysAndWhenInUseUsageDescription:"VJOD ne suit pas votre position."; do
  plutil -replace "${key%%:*}" -string "${key#*:}" ios/Runner/Info.plist
done

flutter clean
flutter pub get

# pod install needs the bundled game cores to exist first (see build.yml).
chmod +x ios/game_host/fetch_cores.sh ios/game_host/wrap_frameworks.sh
./ios/game_host/fetch_cores.sh
./ios/game_host/wrap_frameworks.sh

flutter build ipa --release --no-codesign \
  --build-name "$VERSION" --build-number "$BUILD_NUM" \
  --dart-define=DISTRIBUTION_CHANNEL=ios_unsigned \
  --dart-define=VJOD_BUILD="$(TZ=Europe/Paris date +%Y-%m-%dT%H:%M)" \
  --dart-define=VJOD_COMMIT="${GITHUB_SHA::7}"

APP_PATH=$(find build/ios/archive -type d -path '*/Products/Applications/*.app' | head -1)
TMP=$(mktemp -d)
mkdir -p "$TMP/Payload"
cp -R "$APP_PATH" "$TMP/Payload/"
(cd "$TMP" && zip -qry "$OLDPWD/vjod-ipad.ipa" Payload)
cp "$APP_PATH/Info.plist" vjod-ipad-Info.plist
rm -rf "$TMP"
ls -la vjod-ipad.ipa
