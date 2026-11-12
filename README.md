# no-gradle-apk-cookbook

> 在受限 Linux 上，用 6 个命令行工具打出可安装的签名 APK —— 不需要 Android Studio、Gradle、AndroidX 或 root。

**A reproducible, browser-free pipeline for building WebView-shell APKs on a constrained Linux box.** 全程 `aapt2 → javac → d8 → zipalign → apksigner`，一条脚本跑完，产物通常只有几百 KB。

这份教程不是「又一份手工打包命令清单」。它解决的是另一类问题：**机器没有 javac、没有 Android Studio、`dl.google.com` 不可达、`ulimit -v` 只有 4G、连浏览器都跑不起来**时，怎样把工具链装好、把坑绕过去、把一个真的能装到手机上的 WebView 应用做出来并验证。

## 30 分钟跑通

```bash
git clone https://github.com/steinszzh/no-gradle-apk-cookbook.git
cd no-gradle-apk-cookbook

bash scripts/install-toolchain.sh      # 首次约 690MB，装完长期复用；已有则秒过
bash build_apk.sh                      # 六步链，产出 out/hello.apk
bash scripts/verify.sh out/hello.apk   # 验签 / 清单 / 包内容
adb install out/hello.apk              # 可选：装到手机
```

本机实测输出：

```
✅ out/hello.apk  (44K)
Verifies
Verified using v1 scheme (JAR signing): true
Verified using v2 scheme (APK Signature Scheme v2): true
Verified using v3 scheme (APK Signature Scheme v3): true
package: name='dev.example.helloweb' versionCode='1' versionName='1.0'
sdkVersion:'21'  targetSdkVersion:'34'
```

示例应用是零权限、零第三方 SDK 的 WebView 壳，页面完全来自 `assets/`，带一个经 `JavascriptInterface` 桥持久化到 SharedPreferences 的计数器。前端逻辑用 jsdom 跑了 12 条断言（见 `tests/smoke.js`），**不需要浏览器**。

## 为什么又有这个

「无 Gradle 手工打包」不空白，把链路写成教程的也有。下表是 2026-11-12 的调研快照，star 只用于说明分量，不代表优劣：

| 项目 | 形态 | 覆盖 | 与本项目差别 |
|---|---|---|---|
| `Promastergame/tinyapk-lab` 26★ | 英文 / 俄文完整教程 | `manual-build/` 有分步 README、SKILL.md、R8 指南、两个可玩 demo | 最完整的同类；但主打极小 APK、纯 Java SurfaceView 游戏、Windows `build.ps1`，用 `ecj`，不涉及 WebView 与受限 Linux |
| `skanti/Android-Manual-Build-Command-Line` 89★ | 英文示例 | Makefile 命令行构建 | 2017 年停更，仍是 aapt/dx 时代 |
| `ajinasokan/apkc` 86★ | 工具 | Go CLI 封装 `doctor/create/build/run` | 成品构建器，不教每步在干什么 |
| `azmaveth/termux-android-hello` 15★ | 英文教程 | Termux 上 `setup.sh` + `build.sh` | 用 `dx` 不用 `d8`（JDK21 兼容），Hello World 级 |
| `lxw112190/lw.Web2Android` 123★ | 中文工具 | Web → APK 成品工具 | 开箱即用，但不讲链路与环境坑 |
| `CSN8079/campus-ledger` 的 `docs/安卓打包指南.md` | 中文项目内文档 | WebView 壳、8 步表、四个踩过的坑 | 中文侧最像，但绑在记账本项目里，不通用 |
| `CB2Git/ManualBuildApk` 0★ | 中文 Demo | Windows 7 步命令 | 2023 年，简版，无脚本无后处理 |
| Android 官方「从命令行构建您的应用」 | 官方文档（有中文） | `aapt2 --proto-format` + `bundletool` | **讲的是 AAB 路径，不是手工打出可安装签名 APK** |
| **本项目** | **中文独立教程** | 六步链 + 环境坑 + WebView 真机适配 + 可复现工具链 + 排错表 | 面向受限 Linux 与 WebView 壳的完整产线 |

真正没有公开记录的几处，是本教程的核心：`ulimit -v 4G` 下要**收窄** JVM 堆（网上同类内存文章都在教加大 Gradle 堆，方向相反）、镜像源按文件名直连取包、工具链固化跨会话复用、以及 WebView 壳在真机上的一整套适配清单。

## 文档

| 章节 | 内容 |
|---|---|
| [00 · 工具链与镜像](docs/00-工具链与镜像.md) | 三件套、腾讯 / TUNA 镜像、固定目录、幂等安装 |
| [01 · 六步链](docs/01-六步链.md) | 每步的输入、输出、命令与关键参数；为什么顺序不能乱 |
| [02 · 环境坑](docs/02-环境坑.md) | JVM 堆、无 javac、无外网、lambda 编译、无浏览器验证 |
| [03 · WebView 壳适配](docs/03-WebView壳适配.md) | manifest、深色、字体缩放、持久化桥、返回键、图标 |
| [04 · 音频与素材](docs/04-音频与素材.md) | 内置发音替代系统 TTS、ffmpeg 裁静音、体积优化 |
| [05 · 验签与交付](docs/05-验签与交付.md) | 验签三段检查、安装、升级覆盖规则 |
| [06 · 排错速查](docs/06-排错速查.md) | 报错 → 原因 → 修法速查表 |

## 适用与不适用

**适合**：把本地 HTML / 单页小应用封成 APK；学习 APK 到底由什么组成；CI 或无图形环境里做极简构建；需要零依赖、零权限、几百 KB 产物的工具型应用。

**不适合**：需要 AndroidX / Jetpack / Compose / 第三方 SDK、多 module、AAB 上架、NDK、多渠道打包的项目。这些请老实用 Gradle —— 手工链的价值在于透明和轻量，不在于替代构建系统。

## 安全须知

- `build_apk.sh` 的 `KS_PASS` / `KEY_PASS` 默认值 `android` **只用于本地演示**。正式发布必须显式覆盖，并用自己的 keystore。
- `release.jks`、`*.apk`、`out/` 已在 `.gitignore` 中，**签名密钥绝不入库**。同包名升级必须用同一把 keystore，丢了只能卸载重装。
- 示例页面与文案均为本仓库自创，不含任何第三方内容。

## 授权

代码与文档 MIT，见 [LICENSE](LICENSE)。`aapt2` / `d8` / `zipalign` / `apksigner` 属 Android SDK Build Tools，本仓库不分发，请从官方或镜像获取并遵守其许可。
