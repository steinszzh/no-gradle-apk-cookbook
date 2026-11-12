# 03 · WebView 壳适配

把网页塞进 APK 很容易，让它在各种国产 ROM 上**看起来正常、点得动、数据留得住**才是难点。本章逐条对应 `examples/hello-webview/` 里的实现。

## 最小工程结构

```
app/src/main/
├── AndroidManifest.xml
├── java/dev/example/helloweb/MainActivity.java
├── res/
│   ├── values/colors.xml
│   ├── values/styles.xml
│   └── mipmap-{m,h,xh,xxh,xxxh}dpi/ic_launcher.png
└── assets/
    └── index.html          # 前端全部放这里，可带 css/js/audio 子目录
```

`assets/` 里的文件原样进 APK，用 `file:///android_asset/index.html` 加载。页面里引用相对路径的 `app.css` / `app.js` 会自动跟着走，**不要写绝对路径**。

## 1 · Manifest 必备项

| 属性 | 值 | 为什么 |
|---|---|---|
| `android:exported` | `true` | targetSdk 34 起，带 intent-filter 的组件必须显式声明，否则安装后打不开 |
| `android:configChanges` | `orientation\|screenSize\|keyboardHidden\|uiMode` | 避免旋转 / 深色模式切换时 Activity 重建导致页面刷新 |
| `android:windowSoftInputMode` | `adjustResize` | 软键盘弹起时布局可用，不遮输入框 |
| `android:screenOrientation` | `portrait` | 阅读 / 工具类应用锁竖屏，省掉一整套横屏布局 |
| `android:theme` | 自定义 `AppTheme` | 控制启动背景与系统栏颜色 |

示例应用**零权限**：不申请 `INTERNET`，页面完全离线。需要联网时再加，但那也会带来明文流量限制等新问题。

## 2 · 启动白闪与系统栏

冷启动那一帧由 `windowBackground` 决定，默认是白色。把它设成页面主色就消失了：

```xml
<style name="AppTheme" parent="@android:style/Theme.Material.NoActionBar">
    <item name="android:windowBackground">@color/bg</item>
    <item name="android:statusBarColor">@color/bg</item>
    <item name="android:navigationBarColor">@color/bg</item>
</style>
```

Java 里同步设一次，保证代码创建 WebView 时颜色一致。

⚠️ **深色背景不要加 `SYSTEM_UI_FLAG_LIGHT_STATUS_BAR`** —— 那个 flag 是让状态栏图标变深色（配浅底用的），深色底上会看不见图标。浅色设计才加，并且 API 23+ 才可用。

## 3 · 系统强制深色把页面反色

Android 10+ 的 Force Dark、Android 13+ 的 algorithmic darkening 会自动把浅色页面反色，表现为「UI 发灰 / 颜色全变」。两套 API 都要关：

```java
if (Build.VERSION.SDK_INT >= 33) {
    s.setAlgorithmicDarkeningAllowed(false);
} else if (Build.VERSION.SDK_INT >= 29) {
    s.setForceDark(WebSettings.FORCE_DARK_OFF);
}
```

页面里再补一句 `<meta name="color-scheme" content="only light">`（深色设计则写 `dark`），双保险。示例用的是深色设计，写的是 `dark`。

## 4 · 字体缩放把布局撑爆

```java
s.setTextZoom(100);
```

用户把系统字体调到「超大」时，WebView 默认会跟着放大，rem / em 布局直接散架。工具类应用固定 100 更可控；做无障碍阅读类应用则相反，要保留缩放并单独适配。

## 5 · `file://` 下的持久化不可靠

`localStorage` 在 `file://` origin 上，部分 ROM 的实现会清空或不落地。**别指望它**，桥到 `SharedPreferences`：

```java
web.addJavascriptInterface(new Store(this), "NativeStore");

static class Store {
    @JavascriptInterface public String get(String k) { ... }
    @JavascriptInterface public void set(String k, String v) { ... }
}
```

方法必须标 `@JavascriptInterface`，否则 JS 看不到。前端做三级兜底：桥 → `localStorage` → 内存，每层都 `try/catch`：

```js
get: function (k) {
  try { if (window.NativeStore) return window.NativeStore.get(k); } catch (e) {}
  try { return localStorage.getItem(k) || ''; } catch (e) { return ''; }
}
```

## 6 · 返回键

```java
web.evaluateJavascript("window.__back && window.__back()", new ValueCallback<String>() {
    @Override public void onReceiveValue(String value) {
        if (!"\"1\"".equals(value)) MainActivity.this.finish();
    }
});
```

坑在返回值：`evaluateJavascript` 返回的是 JSON 形式，字符串 `"1"` 拿到手是 **带一层引号的 `"\"1\""`**。写成 `"1".equals(value)` 永远为 false，页面里的面板 / 弹窗就永远关不掉，按返回直接退出应用。

页面侧约定：`__back()` 消费了事件就返回 `'1'`，否则返回 `'0'`。

## 7 · 图标

用 PIL 之类按 4 倍超采样画好再 LANCZOS 缩小到五档，避免边缘锯齿：

| 密度 | 尺寸 |
|---|---|
| mdpi | 48 |
| hdpi | 72 |
| xhdpi | 96 |
| xxhdpi | 144 |
| xxxhdpi | 192 |

文件名统一 `ic_launcher.png`，放 `res/mipmap-*/`，Manifest 里写 `@mipmap/ic_launcher`。需要圆形图标再各加一份 `ic_launcher_round.png`。

## 8 · 其他

- 页面加 `viewport-fit=cover` + `env(safe-area-inset-*)`，避开刘海与手势区。
- 系统栏高度是**物理像素**，CSS 里是逻辑像素，直接写进 CSS 变量会被乘以 density；要除以 `getResources().getDisplayMetrics().density`。
- 音频 / 视频自动播放要 `s.setMediaPlaybackRequiresUserGesture(false)`，见 [04 · 音频与素材](04-音频与素材.md)。
