// sqlite3@5.1.6 Termux/clang 21 兼容补丁
// 修复两处编译错误（真机日志+官方 issue 实锤）:
// 1. statement.cc:315/320  SQLITE_TRANSIENT 在 clang 21 下报
//    invalid conversion from 'int' to 'sqlite3_destructor_type'
//    → 调用点替换为显式强转 ((sqlite3_destructor_type)-1)
// 2. node-addon-api 4.x napi.h:1147 类内静态初始化枚举越界（issue #1854 同因）
//    → 需配合 pnpm.overrides {"node-addon-api": "^8.9.2"}（见 README）
// 幂等: 已补丁的文件不会重复处理
const fs = require('fs');
const path = require('path');

function findSqlite3Dirs(start) {
  const out = [];
  const stack = [start];
  while (stack.length) {
    const dir = stack.pop();
    let entries;
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { continue; }
    for (const e of entries) {
      const p = path.join(dir, e.name);
      if (!e.isDirectory()) continue;
      if (e.name === 'sqlite3' && fs.existsSync(path.join(p, 'src', 'statement.cc'))) {
        out.push(p);
      } else if (e.name === 'node_modules' || e.name.startsWith('sqlite3@') || e.name === '.pnpm') {
        stack.push(p);
      }
    }
  }
  return out;
}

// 从本包位置向上找最近的 node_modules
function findBase() {
  let dir = __dirname;
  for (let i = 0; i < 10; i++) {
    const nm = path.join(dir, 'node_modules');
    if (fs.existsSync(nm)) return nm;
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return null;
}

const base = findBase();
if (!base) {
  console.log('[sqlite3-termux] 未找到 node_modules，跳过补丁（首次 install 时会自动再跑）');
  process.exit(0);
}

const dirs = findSqlite3Dirs(base);
let patched = 0;
for (const dir of dirs) {
  const f = path.join(dir, 'src', 'statement.cc');
  let src = fs.readFileSync(f, 'utf8');
  if (src.includes('SQLITE_TRANSIENT') && !src.includes('sqlite3_destructor_type)-1')) {
    src = src.replaceAll('SQLITE_TRANSIENT)', '((sqlite3_destructor_type)-1))');
    fs.writeFileSync(f, src);
    console.log(`[sqlite3-termux] 已补丁: ${f}`);
    patched++;
  }
}
console.log(`[sqlite3-termux] 完成，本次补丁 ${patched} 处${dirs.length ? '' : '（未找到 sqlite3 源码，如首次安装请以 overrides 方式引用本包）'}`);
