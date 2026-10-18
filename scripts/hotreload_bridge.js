// ============================================================
// hotreload_bridge.js — Flutter 热更新桥（Windows 桌面 + Web 通用）
//
// 让 agent（没有终端可敲键）能向 flutter run 进程发指令：
//   向同目录 cmd.txt 写入单字符 → 本桥转发给 flutter 的 stdin
//
// 用法：
//   node hotreload_bridge.js [--device windows|web-server] [--port 57134] [--project <app 目录>]
//   兼容旧用法：node hotreload_bridge.js 57134   （= web-server + 该端口）
//
// 指令：r 热重载（保留状态） · R 热重启 · x 完全重启 flutter · q 退出 · d 脱离（保留窗口）
// 产物：run.log（flutter 全部输出） · state.json（phase / device / vmService，给 agent 读）
// ============================================================

const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const FLUTTER = 'D:\\Flutter_APP_Develop\\Flutter_SDK\\flutter\\bin\\flutter.bat';
const DIR = __dirname;
const CMD_FILE = path.join(DIR, 'cmd.txt');
const LOG_FILE = path.join(DIR, 'run.log');
const STATE_FILE = path.join(DIR, 'state.json');

const argv = process.argv.slice(2);
function argOf(name, def) {
  const i = argv.indexOf(name);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : def;
}

let device = argOf('--device', 'windows');
let port = argOf('--port', '57134');
if (argv.length && /^\d+$/.test(argv[0])) {
  device = 'web-server';
  port = argv[0];
}
const PROJECT = argOf('--project', path.resolve(__dirname, '..', 'app'));

let child = null;
let restarting = false;
let vmService = null;

function stamp() {
  return new Date().toLocaleString('zh-CN', { hour12: false });
}

function log(msg) {
  const line = `[${stamp()}] ${msg}\n`;
  console.log(line.trim());
  try { fs.appendFileSync(LOG_FILE, line); } catch (e) {}
}

function writeState(phase) {
  const state = {
    phase,
    device,
    port: device === 'web-server' ? Number(port) : null,
    vmService,
    updatedAt: new Date().toISOString(),
    pid: child ? child.pid : null,
  };
  try { fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2)); } catch (e) {}
}

function startFlutter() {
  const extra = device === 'web-server' ? ['--web-port=' + port] : [];
  const cmdArgs = ['run', '-d', device, ...extra];
  log(`启动 flutter ${cmdArgs.join(' ')}   项目: ${PROJECT}`);
  try { fs.writeFileSync(LOG_FILE, `\n===== 会话 ${stamp()} · ${cmdArgs.join(' ')} =====\n`); } catch (e) {}
  vmService = null;
  writeState('building');

  child = spawn('cmd.exe', ['/c', FLUTTER, ...cmdArgs], {
    cwd: PROJECT,
    stdio: ['pipe', 'pipe', 'pipe'],
    env: Object.assign({}, process.env, { FLUTTER_SUPPRESS_ANALYTICS: 'true' }),
  });

  const onOut = (d) => {
    const t = d.toString();
    process.stdout.write(t);
    try { fs.appendFileSync(LOG_FILE, t); } catch (e) {}
    const m = t.match(/http:\/\/127\.0\.0\.1:\d+\/[\w\-=]+\//);
    if (m && m[0] !== vmService) {
      vmService = m[0];
      writeState('running');
      log('VM service: ' + vmService);
    }
    if (/Reloaded|Restarted/.test(t)) {
      const reload = t.match(/(Reloaded[^\n]*|Restarted[^\n]*)/);
      if (reload) log(reload[1].trim());
      writeState('running');
    }
  };
  child.stdout.on('data', onOut);
  child.stderr.on('data', (d) => {
    const t = d.toString();
    process.stderr.write(t);
    try { fs.appendFileSync(LOG_FILE, t); } catch (e) {}
  });
  child.on('exit', (code, sig) => {
    log(`flutter 进程退出 (code=${code}, sig=${sig})`);
    writeState('stopped');
    if (restarting) {
      restarting = false;
      log('3 秒后自动重启…');
      setTimeout(startFlutter, 3000);
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

try { fs.writeFileSync(CMD_FILE, ''); } catch (e) {}
startFlutter();

setInterval(() => {
  let content = '';
  try {
    content = fs.readFileSync(CMD_FILE, 'utf8').trim();
  } catch (e) {
    return;
  }
  if (!content) return;
  const cmd = content.split(/\s+/)[0];
  try { fs.writeFileSync(CMD_FILE, ''); } catch (e) {}
  if (cmd === 'x') {
    restarting = true;
    sendCommand('q');
  } else {
    sendCommand(cmd);
  }
}, 300);
