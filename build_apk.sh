#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# 无 Gradle 的 APK 构建脚本：六步全包（资源编译 → 链接 → javac → d8 → 对齐 → 签名）
#
#   bash build_apk.sh
#   APP=examples/hello-webview NAME=hello bash build_apk.sh
#
# 所有参数都能用环境变量覆盖，见 docs/01-六步链.md。
# 前置条件见 docs/00-工具链与镜像.md；仅需 Android build-tools + platform + JDK17。
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

TOOLCHAIN=${TOOLCHAIN:-$HOME/.local/share/android-toolchain}
SDK=$TOOLCHAIN/sdk
JHOME=$TOOLCHAIN/jdk17

BT=$(ls -d "$SDK"/build-tools/*/ 2>/dev/null | sort -V | tail -1)
AJAR=$(ls "$SDK"/platforms/android-*/android.jar 2>/dev/null | sort -V | tail -1)

if [ -z "$BT" ] || [ -z "$AJAR" ] || [ ! -x "$JHOME/bin/javac" ]; then
  echo "✗ 工具链不完整，先跑：bash scripts/install-toolchain.sh" >&2
  echo "  期望：$JHOME/bin/javac" >&2
  echo "        $SDK/build-tools/<ver>/aapt2" >&2
  echo "        $SDK/platforms/android-<ver>/android.jar" >&2
  exit 1
fi

# ── 项目参数 ──────────────────────────────────────────────────
APP=${APP:-examples/hello-webview}
OUT=${OUT:-out}
NAME=${NAME:-hello}
VERSION_NAME=${VERSION_NAME:-1.0}
VERSION_CODE=${VERSION_CODE:-1}
MIN_SDK=${MIN_SDK:-21}
TARGET_SDK=${TARGET_SDK:-34}
KS=${KS:-$PWD/release.jks}
KS_ALIAS=${KS_ALIAS:-key}

# ⚠️ 下面两个默认值只用于本地演示。正式发布必须覆盖，且 keystore 绝不入库。
KS_PASS=${KS_PASS:-android}
KEY_PASS=${KEY_PASS:-android}

# ── 环境：ulimit -v 常见 4G，必须「收窄」JVM 堆而不是加大 ──────
export JAVA_HOME="$JHOME"
export PATH="$JHOME/bin:$PATH"
export JAVA_TOOL_OPTIONS="-Xmx700m -Xms64m -XX:MaxMetaspaceSize=192m -XX:CompressedClassSpaceSize=96m -XX:ReservedCodeCacheSize=96m -XX:MaxDirectMemorySize=128m"

# 只清理本脚本自己产生的中间物，不做无保护的 rm -rf "$OUT"
for p in res gen classes dex base.apk aligned.apk; do rm -rf -- "$OUT/$p"; done
mkdir -p "$OUT"/{res,gen,classes,dex}

echo "▸ 1/6  aapt2 compile：编译资源"
"$BT/aapt2" compile --dir "$APP/res" -o "$OUT/res"

echo "▸ 2/6  aapt2 link：链接资源与清单，生成 R.java"
LINK_ARGS=(-o "$OUT/base.apk" -I "$AJAR" --manifest "$APP/AndroidManifest.xml"
  --java "$OUT/gen" --min-sdk-version "$MIN_SDK" --target-sdk-version "$TARGET_SDK"
  --version-code "$VERSION_CODE" --version-name "$VERSION_NAME")
[ -d "$APP/assets" ] && LINK_ARGS+=(-A "$APP/assets")
"$BT/aapt2" link "${LINK_ARGS[@]}" "$OUT"/res/*.flat

echo "▸ 3/6  javac：Java → class"
SRC=()
if [ -d "$APP/java" ]; then
  while IFS= read -r f; do SRC+=("$f"); done < <(find "$APP/java" -name '*.java' | sort)
fi
while IFS= read -r f; do SRC+=("$f"); done < <(find "$OUT/gen" -name '*.java' | sort)
if [ ${#SRC[@]} -gt 0 ]; then
  javac -nowarn -source 8 -target 8 -encoding UTF-8 -bootclasspath "$AJAR" \
        -d "$OUT/classes" "${SRC[@]}"
else
  echo "    没有 Java 源码，跳过"
fi

echo "▸ 4/6  d8：class → classes.dex"
CLS=()
while IFS= read -r f; do CLS+=("$f"); done < <(find "$OUT/classes" -name '*.class' | sort)
if [ ${#CLS[@]} -gt 0 ]; then
  "$BT/d8" --release --lib "$AJAR" --min-api "$MIN_SDK" --output "$OUT/dex" "${CLS[@]}"
else
  echo "    没有 class 文件，跳过"
fi

echo "▸ 5/6  zip + zipalign：合并 dex 并 4 字节对齐"
OUT_ABS=$(cd "$OUT" && pwd)
if [ -f "$OUT/dex/classes.dex" ]; then
  (cd "$OUT/dex" && zip -q -X "$OUT_ABS/base.apk" classes.dex)
fi
"$BT/zipalign" -f -p 4 "$OUT/base.apk" "$OUT/aligned.apk"

echo "▸ 6/6  apksigner：v1 + v2 + v3 签名"
if [ ! -f "$KS" ]; then
  keytool -genkeypair -keystore "$KS" -alias "$KS_ALIAS" -keyalg RSA -keysize 2048 \
    -validity 10950 -storepass "$KS_PASS" -keypass "$KEY_PASS" \
    -dname "CN=Example, OU=Demo, O=Demo, C=CN" >/dev/null 2>&1
  echo "    已生成签名库 $KS（同包名升级必须用同一把，务必自行保管）"
fi
"$BT/apksigner" sign --ks "$KS" --ks-pass "pass:$KS_PASS" --key-pass "pass:$KEY_PASS" \
  --ks-key-alias "$KS_ALIAS" --min-sdk-version "$MIN_SDK" \
  --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true \
  --out "$OUT/$NAME.apk" "$OUT/aligned.apk"
"$BT/apksigner" verify --print-certs "$OUT/$NAME.apk" | head -3

echo
echo "✅ $OUT/$NAME.apk  ($(du -h "$OUT/$NAME.apk" | cut -f1))"
