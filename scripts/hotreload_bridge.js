// ============================================================
// hotreload-bridge.js — Flutter 热更新桥
// 让 agent（无终端）能向 flutter run 进程发送键盘指令。
//
// 用法:  node hotreload_bridge.js [port] [项目目录]   （项目目录默认 = 本脚本上一级的 app\）
// 指令:  向同目录 cmd.txt 写入单字符:
//           r = 热重载（保留状态）   R = 热重启（重置状态）
//           q = 退出服务            x = 完全重启 flutter（改依赖/原生配置后）
// 日志:  同目录 run.log（flutter 全部输出）
// ============================================================

const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const FLUTTER = 'D:\\Flutter_APP_Develop\\Flutter_SDK\\flutter\\bin\\flutter.bat';
const PROJECT = process.argv[3] || path.resolve(__dirname, '..', 'app');
const PORT = process.argv[2] || '57133';
const DIR = __dirname;
const CMD_FILE = path.join(DIR, 'cmd.txt');
const LOG_FILE = path.join(DIR, 'run.log');

function log(msg) {
  const line = `[${new Date().toLocaleString('zh-CN', { hour12: false })}] ${msg}\n`;
  console.log(line.trim());
  try { fs.appendFileSync(LOG_FILE, line); } catch (e) {}
}

let child = null;
let restarting = false;

function startFlutter() {
  log('启动 flutter run -d web-server --web-port=' + PORT + ' (项目: ' + PROJECT + ')');
  child = spawn('cmd.exe', ['/c', FLUTTER, 'run', '-d', 'web-server', '--web-port=' + PORT], {
    cwd: PROJECT,
    stdio: ['pipe', 'pipe', 'pipe'],
    env: Object.assign({}, process.env, { FLUTTER_SUPPRESS_ANALYTICS: 'true' })
  });

  child.stdout.on('data', (d) => {
    const t = d.toString();
    process.stdout.write(t);
    try { fs.appendFileSync(LOG_FILE, t); } catch (e) {}
  });
  child.stderr.on('data', (d) => {
    const t = d.toString();
    process.stderr.write(t);
    try { fs.appendFileSync(LOG_FILE, t); } catch (e) {}
  });
  child.on('exit', (code, sig) => {
    log('flutter 进程退出 (code=' + code + ', sig=' + sig + ')');
    if (restarting) {
      restarting = false;
      log('5 秒后自动重启...');
      setTimeout(startFlutter, 5000);
    } else {
      process.exit(0);
    }
  });
}

function sendCommand(cmd) {
  if (!child || child.stdin.destroyed) {
    log('警告: flutter 进程不可用，指令未发送: ' + JSON.stringify(cmd));
    return;
  }
  log('发送指令: ' + JSON.stringify(cmd));
  try { child.stdin.write(cmd + '\n'); } catch (e) { log('发送失败: ' + e.message); }
}

startFlutter();

// 轮询指令文件
setInterval(() => {
  try {
    const content = fs.readFileSync(CMD_FILE, 'utf8');
    const cmd = content.trim();
    if (!cmd) return;
    fs.writeFileSync(CMD_FILE, ''); // 先清空再执行，避免重复触发
    if (cmd === 'q') {
      sendCommand('q');
    } else if (cmd === 'x') {
      restarting = true;
      sendCommand('q');
    } else {
      sendCommand(cmd);
    }
  } catch (e) {
    // 文件被占用等瞬时错误，跳过本次
  }
}, 400);
