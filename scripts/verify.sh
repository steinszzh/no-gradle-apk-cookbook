#!/usr/bin/env bash
# 验收一个手工打出的 APK：签名 / 清单 / 包内容。
#   bash scripts/verify.sh out/hello.apk
set -euo pipefail

APK=${1:-out/hello.apk}
T=${TOOLCHAIN:-$HOME/.local/share/android-toolchain}
BT=$(ls -d "$T"/sdk/build-tools/*/ 2>/dev/null | sort -V | tail -1)

[ -f "$APK" ] || { echo "✗ 找不到 $APK" >&2; exit 1; }
[ -n "$BT" ] || { echo "✗ 找不到 build-tools" >&2; exit 1; }

export JAVA_HOME="$T/jdk17"
export PATH="$JAVA_HOME/bin:$PATH"
export JAVA_TOOL_OPTIONS="-Xmx700m -Xms64m -XX:MaxMetaspaceSize=192m"

echo "── 1/3 签名校验 ──────────────────────────────"
"$BT/apksigner" verify --verbose "$APK" | head -8

echo "── 2/3 清单与版本 ────────────────────────────"
"$BT/aapt2" dump badging "$APK" | grep -E "^(package|sdkVersion|targetSdkVersion|application-label|launchable-activity)" | head -8

echo "── 3/3 关键条目 ──────────────────────────────"
unzip -l "$APK" | grep -E "classes\.dex|resources\.arsc|AndroidManifest\.xml|assets/index\.html" || true

echo
echo "✅ $APK 验证通过（$(du -h "$APK" | cut -f1)）"
