### Yunzai-Bot（云崽）纯净插件收录与审查台账

> 本表只收录**安全审计通过**的插件；未收录的插件不在本表，用户自行安装的后果自负（安装时自行提示风险）。
>
> 等级说明：
> 🟢 官方 —— 本团队维护的仓库，免审
> 🟡 已收录 —— 人工审查通过，每月抽查、每年全面复查
>
> 安装/更新只信任"版本哈希"列记录的 commit，超出该范围的更新需重新确认。
> ✅ = 连续多次检查无异常，长期稳定。

| 等级 | 插件 | 作者 | 简介 | 下载地址 | 检查日期 | 版本哈希 | 安全备注 |
|------|------|------|------|----------|----------|----------|----------|
| 🟢 官方 | [榴莲插件 (liulian-plugin)](https://gitee.com/huifeidemangguomao/liulian-plugin) | [@会飞的芒果猫](https://gitee.com/huifeidemangguomao) [@萧枘](https://gitee.com/xiaoxiaorurui) | 原神地下地图、B站推送、插件管理及原神/星铁猜角色、娶群友、随机表情、星座运势、话痨统计、天气、多群广播等群聊功能 | [Gitee](https://gitee.com/huifeidemangguomao/liulian-plugin)（主）→[GitCode](https://gitcode.com/huifeidemangguomao/liulian-plugin)→[GitHub](https://github.com/FlyingMangoCat/liulian-plugin) | 免审 | — | 本团队维护 |
| 🟡 已收录 | [喵喵插件 (miao-plugin)](https://github.com/yoimiya-kokomi/miao-plugin) | [@喵喵](https://gitee.com/yoimiya-kokomi) | Yunzai-Bot 升级插件，提供角色面板查询、素材资源等升级功能 | [GitHub](https://github.com/yoimiya-kokomi/miao-plugin)（主）→[GitCode](https://gitcode.com/huifeidemangguomao/miao-plugin)→[Gitee 镜像](https://gitee.com/huifeidemangguomao/miao-plugin) | 2026-10-21（抽查） | aca4f20 | 无安装钩子（scripts 为空）；自带手动调试页服务（`npm run web`，8000 端口），非自启动；抽查时本地镜像与上游 HEAD 一致 |
