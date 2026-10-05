# @fmc-yz/sqlite3-termux

sqlite3@5.1.6 在 Termux（Android ARM64 + clang 21 + Node 24）下编译失败的兼容补丁包。

## 修复内容

1. `statement.cc` 两处 `SQLITE_TRANSIENT` 在 clang 21 下报
   `invalid conversion from 'int' to 'sqlite3_destructor_type'` → 调用点显式强转
2. 配合 `node-addon-api@^8.9.2` 覆盖（4.x 的 `napi.h:1147` 类内静态初始化被
   clang 21 拒绝，官方 issue #1854 同因）

## 用法（云崽项目）

`package.json` 中加入：

```json
{
  "pnpm": {
    "overrides": {
      "sqlite3": "npm:@fmc-yz/sqlite3-termux@^1.0.0",
      "node-addon-api": "^8.9.2"
    }
  }
}
```

本包 postinstall 会在依赖树里找到真实的 sqlite3 源码并打补丁（幂等）。

## 发布

```bash
cd sqlite3-termux
npm login   # 需要包所有者本人的 npm 账号
npm publish --access public
```

发布前必须先在真机 Termux 上验证编译通过。
