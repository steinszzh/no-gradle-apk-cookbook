package dev.example.helloweb;

import android.app.Activity;
import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.os.Build;
import android.os.Bundle;
import android.webkit.JavascriptInterface;
import android.webkit.ValueCallback;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

/**
 * 最小 WebView 壳：零第三方依赖、零权限，页面全部来自 assets/。
 * 这里集中处理了真机上最容易翻车的几处适配，逐条见 docs/03-WebView壳适配.md。
 */
public class MainActivity extends Activity {

    private WebView web;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // 深色底色：windowBackground 与系统栏同色，消除启动白闪。
        // 注意深色背景不要加 SYSTEM_UI_FLAG_LIGHT_STATUS_BAR，否则状态栏图标会变深色看不清。
        getWindow().setStatusBarColor(Color.parseColor("#101820"));
        getWindow().setNavigationBarColor(Color.parseColor("#101820"));

        web = new WebView(this);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setTextZoom(100);                       // 忽略系统字体缩放，避免布局被撑爆
        s.setMediaPlaybackRequiresUserGesture(false);

        // 关掉系统强制深色，否则浅色页面会被自动反色/发灰
        if (Build.VERSION.SDK_INT >= 33) {
            s.setAlgorithmicDarkeningAllowed(false);
        } else if (Build.VERSION.SDK_INT >= 29) {
            s.setForceDark(WebSettings.FORCE_DARK_OFF);
        }

        web.setWebViewClient(new WebViewClient());
        // file:// 下 localStorage 在部分 ROM 上不可靠，桥到 SharedPreferences
        web.addJavascriptInterface(new Store(this), "NativeStore");
        setContentView(web);
        web.loadUrl("file:///android_asset/index.html");
    }

    @Override
    public void onBackPressed() {
        // evaluateJavascript 的返回值带一层 JSON 引号："\"1\"" 才是 true。
        // 这里用匿名内部类而不是 lambda：javac 以 -bootclasspath android.jar 编译时
        // 找不到 LambdaMetafactory，会报 cannot find symbol metafactory。
        web.evaluateJavascript("window.__back && window.__back()", new ValueCallback<String>() {
            @Override
            public void onReceiveValue(String value) {
                if (!"\"1\"".equals(value)) {
                    MainActivity.this.finish();
                }
            }
        });
    }

    /** 供页面调用的持久化桥。方法必须标 @JavascriptInterface 才能被 JS 看到。 */
    static class Store {
        private final SharedPreferences sp;

        Store(Context context) {
            sp = context.getSharedPreferences("hello", Context.MODE_PRIVATE);
        }

        @JavascriptInterface
        public String get(String key) {
            return sp.getString(key, "");
        }

        @JavascriptInterface
        public void set(String key, String value) {
            sp.edit().putString(key, value).apply();
        }
    }
}
