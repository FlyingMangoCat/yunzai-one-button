# @fmc-yz/sqlite3-termux

sqlite3@5.1.6 的 Termux（Android ARM64 + clang 21 + Node 24）兼容重打包版本。

## 修复内容

- `statement.cc` 两处 `SQLITE_TRANSIENT` 在 clang 21 下报
  `invalid conversion from 'int' to 'sqlite3_destructor_type'` → 调用点显式强转
  `((sqlite3_destructor_type)-1))`
- 需配合 `node-addon-api@^8.9.2` 使用（4.x 的 `napi.h:1147` 类内静态初始化被
  clang 21 拒绝，官方 issue #1854 同因；8.x 已移除该写法）

除上述补丁外与原版 sqlite3@5.1.6 完全一致（API/入口/编译脚本均未改动），
Sequelize 等 `require('sqlite3')` 的调用方无感。

## 用法（Termux 云崽项目）

`package.json` 中加入：

```json
{
  "pnpm": {
    "overrides": {
      "sqlite3": "npm:@fmc-yz/sqlite3-termux@5.1.6-termux.1",
      "node-addon-api": "^8.9.2"
    }
  }
}
```

或 YZv3.sh 一键脚本（Termux 分支已内置等效修复，无需手动配置）。

## 发布

```bash
# 重新打包（如需更新补丁）
# tar czf fmc-yz-sqlite3-termux-5.1.6-termux.1.tgz package
npm login    # 需要包所有者本人的 npm 账号
npm publish fmc-yz-sqlite3-termux-5.1.6-termux.1.tgz --access public
```

发布前必须先在真机 Termux 上验证编译通过。
