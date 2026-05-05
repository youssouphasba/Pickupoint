#!/usr/bin/env bash
set -euo pipefail

IPA_PATH="${1:-}"
if [ -z "$IPA_PATH" ]; then
  IPA_PATH="$(find "${CM_BUILD_DIR:-.}" -path "*/build/ios/ipa/*.ipa" -type f | head -n 1 || true)"
fi

if [ -z "$IPA_PATH" ] || [ ! -f "$IPA_PATH" ]; then
  echo "Aucun IPA trouvé pour le scan iOS." >&2
  exit 1
fi

SCAN_DIR="${TMPDIR:-/tmp}/denkma-ios-review-scan"
rm -rf "$SCAN_DIR"
mkdir -p "$SCAN_DIR"
unzip -q "$IPA_PATH" -d "$SCAN_DIR"

APP_DIR="$(find "$SCAN_DIR/Payload" -maxdepth 1 -name "*.app" -type d | head -n 1 || true)"
if [ -z "$APP_DIR" ]; then
  echo "Aucun .app trouvé dans l'IPA." >&2
  exit 1
fi

REPORT_DIR="${CM_BUILD_DIR:-.}/ios-review-scan"
mkdir -p "$REPORT_DIR"
REPORT="$REPORT_DIR/report.txt"
: > "$REPORT"

echo "IPA: $IPA_PATH" | tee -a "$REPORT"
echo "App: $APP_DIR" | tee -a "$REPORT"
echo "" | tee -a "$REPORT"

find_binaries() {
  find "$APP_DIR" \( -perm -111 -o -name "*.dylib" \) -type f
}

HARD_PATTERNS=(
  "UIWebView"
  "LSApplicationWorkspace"
  "MGCopyAnswer"
  "MobileGestalt"
  "App-Prefs:"
  "prefs:"
  "/System/Library/PrivateFrameworks"
  "setAllowsAnyHTTPSCertificate"
  "allowsAnyHTTPSCertificateForHost"
)

SOFT_PATTERNS=(
  "PKPushRegistry"
  "PushKit"
  "CTCallCenter"
  "CTCall"
  "CallKit"
  "performSelector"
  "NSClassFromString"
)

hard_hits=0

echo "=== Frameworks embarqués ===" | tee -a "$REPORT"
find "$APP_DIR/Frameworks" -maxdepth 2 -type f 2>/dev/null | sed "s#^$APP_DIR/##" | tee -a "$REPORT" || true
echo "" | tee -a "$REPORT"

while IFS= read -r binary; do
  name="${binary#$APP_DIR/}"
  echo "=== Binaire: $name ===" | tee -a "$REPORT"

  if command -v otool >/dev/null 2>&1; then
    echo "-- Linked libraries" | tee -a "$REPORT"
    otool -L "$binary" 2>/dev/null | tee -a "$REPORT" || true
    echo "-- Objective-C structures" | tee -a "$REPORT"
    otool -ov "$binary" 2>/dev/null | grep -E "(__OBJC|class_ro_t|name|baseMethods|baseProtocols|ivarLayout|method_list_t|^[[:space:]]*0x)" | head -n 250 | tee -a "$REPORT" || true
  fi

  for pattern in "${HARD_PATTERNS[@]}"; do
    if strings "$binary" 2>/dev/null | grep -F "$pattern" >/dev/null; then
      hard_hits=$((hard_hits + 1))
      echo "ERREUR API interdite probable: $pattern dans $name" | tee -a "$REPORT"
      strings "$binary" 2>/dev/null | grep -F "$pattern" | head -n 20 | tee -a "$REPORT"
    fi
  done

  for pattern in "${SOFT_PATTERNS[@]}"; do
    if strings "$binary" 2>/dev/null | grep -F "$pattern" >/dev/null; then
      echo "Signal à vérifier: $pattern dans $name" | tee -a "$REPORT"
      strings "$binary" 2>/dev/null | grep -F "$pattern" | head -n 10 | tee -a "$REPORT"
    fi
  done
  echo "" | tee -a "$REPORT"
done < <(find_binaries)

if [ -f "$APP_DIR/Frameworks/WebRTC.framework/WebRTC" ]; then
  WEBRTC="$APP_DIR/Frameworks/WebRTC.framework/WebRTC"
  echo "=== Focus WebRTC.framework ===" | tee -a "$REPORT"
  strings "$WEBRTC" | grep -Ei "WebRTC|RTCPeer|RTC[A-Z]|PushKit|PKPush|CallKit|CTCall|UIWebView|LSApplicationWorkspace|MobileGestalt|MGCopyAnswer|App-Prefs|prefs:" | head -n 300 | tee -a "$REPORT" || true
fi

echo "Rapport écrit dans: $REPORT"

if [ "$hard_hits" -gt 0 ]; then
  echo "Scan iOS échoué: $hard_hits référence(s) fortement suspecte(s) détectée(s)." >&2
  exit 1
fi

echo "Scan iOS terminé: aucun motif fortement interdit détecté."
