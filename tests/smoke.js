/* eslint-disable */
// 无浏览器环境下验证 assets/index.html 的交互逻辑。
//   NODE_PATH=<jsdom 所在 node_modules> node tests/smoke.js
// jsdom 没有布局引擎：只断言 DOM / 事件 / 持久化，不测尺寸。
const fs = require('fs');
const path = require('path');
const { JSDOM } = require('jsdom');

const htmlPath = path.join(__dirname, '..', 'examples', 'hello-webview', 'assets', 'index.html');
const html = fs.readFileSync(htmlPath, 'utf8');

const memory = {};
const dom = new JSDOM(html, {
  runScripts: 'dangerously',
  url: 'file:///android_asset/index.html',
  beforeParse(window) {
    // 模拟 MainActivity 注入的 @JavascriptInterface 桥
    window.NativeStore = {
      get: (k) => memory[k] || '',
      set: (k, v) => { memory[k] = String(v); }
    };
  }
});

const { window } = dom;
const doc = window.document;
let passed = 0;
function check(name, cond) {
  if (!cond) { console.error('FAIL ' + name); process.exitCode = 1; }
  else { console.log('ok   ' + name); passed += 1; }
}
function click(id) {
  doc.getElementById(id).dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
}

check('页面标题正确', /构建成功/.test(doc.querySelector('h1').textContent));
check('初始计数为 0', doc.getElementById('n').textContent === '0');

click('add'); click('add'); click('add');
check('点击三次后计数为 3', doc.getElementById('n').textContent === '3');
check('写入了持久化桥', memory.clicks === '3');

click('reset');
check('清零后计数归零', doc.getElementById('n').textContent === '0');
check('持久化值同步清零', memory.clicks === '0');

check('面板初始隐藏', !doc.getElementById('panel').classList.contains('on'));
click('toggle');
check('面板可展开', doc.getElementById('panel').classList.contains('on'));
check('面板打开时返回键被消费', window.__back() === '1');
check('面板关闭后返回键交还 Activity', window.__back() === '0');

check('无外部脚本引用', doc.querySelectorAll('script[src]').length === 0);
check('无外链资源', !/https?:\/\//.test(html.replace(/<!--[\s\S]*?-->/g, '')) ||
      !doc.querySelector('img[src^="http"], link[href^="http"]'));

console.log('\n' + passed + ' assertions passed');
