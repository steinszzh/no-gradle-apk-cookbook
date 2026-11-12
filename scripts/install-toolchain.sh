#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# 一次性安装用户级 Android 构建工具链（不需要 root / Android Studio / Gradle）
# 幂等：三件套齐全就直接跳过；缺失才下载。约 690MB，装完长期复用。
#
#   bash scripts/install-toolchain.sh
#   APK_PROXY=http://127.0.0.1:7890 bash scripts/install-toolchain.sh   # 慢网络
#
# 镜像：腾讯 AndroidSDK（dl.google.com 不可达时）+ 清华 TUNA Adoptium。
# 详见 docs/00-工具链与镜像.md
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

T=${TOOLCHAIN:-$HOME/.local/share/android-toolchain}
DL="$T/dl"
B=https://mirrors.cloud.tencent.com/AndroidSDK
JDK_URL=https://mirrors.tuna.tsinghua.edu.cn/Adoptium/17/jdk/x64/linux/OpenJDK17U-jdk_x64_linux_hotspot_17.0.21_9.tar.gz
JDK_TGZ=OpenJDK17U-jdk_x64_linux_hotspot_17.0.21_9.tar.gz

CURL=(curl -fL --retry 5 --retry-delay 3 --speed-time 60 --speed-limit 3000 -C -)
[ -n "${APK_PROXY:-}" ] && CURL+=(-x "$APK_PROXY")

fetch() {
  [ -s "$2" ] && { echo "[skip] $(basename "$2") 已下载"; return; }
  echo "[get ] $(basename "$2")"
  "${CURL[@]}" -o "$2" "$1"
}

need_bt=0; need_pf=0; need_jdk=0
[ -x "$T/sdk/build-tools/34.0.0/aapt2" ] || need_bt=1
[ -f "$T/sdk/platforms/android-35/android.jar" ] || need_pf=1
[ -x "$T/jdk17/bin/javac" ] || need_jdk=1
if [ "$need_bt$need_pf$need_jdk" = "000" ]; then
  echo "✅ 工具链已就绪：$T（无需下载）"
  "$T/jdk17/bin/javac" -version
  exit 0
fi

mkdir -p "$DL" "$T/sdk/build-tools" "$T/sdk/platforms"

if [ "$need_bt" = 1 ]; then
  fetch "$B/build-tools_r34-linux.zip" "$DL/build-tools.zip"
  mkdir -p "$DL/bt" && unzip -q -o "$DL/build-tools.zip" -d "$DL/bt"
  # 镜像包顶层目录名是 android-14，需改成版本号，否则 sdkmanager 认不出
  rm -rf "$T/sdk/build-tools/34.0.0"
  mv "$DL/bt/android-14" "$T/sdk/build-tools/34.0.0"
fi

if [ "$need_pf" = 1 ]; then
  fetch "$B/platform-35_r02.zip" "$DL/platform.zip"
  mkdir -p "$DL/pf" && unzip -q -o "$DL/platform.zip" -d "$DL/pf"
  rm -rf "$T/sdk/platforms/android-35"
  mv "$DL/pf/android-35" "$T/sdk/platforms/android-35"
fi

if [ "$need_jdk" = 1 ]; then
  fetch "$JDK_URL" "$DL/$JDK_TGZ"
  # tar 会刷一屏 Cannot utime（元数据权限），属正常，文件完整
  mkdir -p "$DL/jdk" && tar xzf "$DL/$JDK_TGZ" -C "$DL/jdk" --strip-components=1 2>/dev/null || true
  rm -rf "$T/jdk17" && mv "$DL/jdk" "$T/jdk17"
fi

echo "✅ 工具链已就绪：$T"
"$T/jdk17/bin/javac" -version
echo "   提示：把工具链放在固定用户目录，别放进按日期命名的工作区，否则每次都要重下 690MB。"
