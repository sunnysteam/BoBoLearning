# BoBoLearning 门户视觉验收

## 验收结论

- 最终结果：通过。
- P0 / P1 / P2：无未解决项。
- 验收日期：2026-09-03。

## 参考与实现证据

### 总首页

- 参考截图：`C:\Users\yxb\AppData\Local\Temp\codex-clipboard-9bfbda8f-469c-4748-89dc-394a06223c67.png`
- 文案局部参考：`C:\Users\yxb\AppData\Local\Temp\codex-clipboard-906e7a5e-80b5-436a-a9c2-2f2b60ec76b7.png`
- 实现截图：`G:\SourceCode\BoBoLearning\output\design-qa\portal-desktop-after.png`
- 视口：1456 × 676，设备像素比 1。
- 状态：首页默认状态，三个入口均可点击。

### 菠萝早教

- 参考截图：`C:\Users\yxb\AppData\Local\Temp\codex-clipboard-f35c44f2-18ca-47d3-a36d-7103ed31b9d7.png`
- 实现截图：`G:\SourceCode\BoBoLearning\output\design-qa\early-learning-desktop-after.png`
- 视口：1912 × 914，设备像素比 1。
- 状态：空视频列表。

### 菠萝视频

- 参考截图：`C:\Users\yxb\AppData\Local\Temp\codex-clipboard-771b2f5d-5c83-4f5a-b156-288811aeb495.png`
- 实现截图：`G:\SourceCode\BoBoLearning\output\design-qa\videos-desktop-after.png`
- 视口：1912 × 914，设备像素比 1。
- 状态：准备中占位页。

### 菠萝相册

- 参考截图：`C:\Users\yxb\AppData\Local\Temp\codex-clipboard-826e4b0d-85ae-45b2-8f67-950bfed0d217.png`
- 实现截图：`G:\SourceCode\BoBoLearning\output\design-qa\albums-desktop-after.png`
- 视口：1912 × 914，设备像素比 1。
- 状态：准备中占位页。

## 检查范围

- 总首页三个分类卡片图标在 Web Release 中完整显示。
- 入口提示只保留“今天想去哪里玩？”，采用正文层级字体，不显示附加说明。
- 菠萝早教子页顶部只显示返回按钮和标题，不显示品牌图标及标题下小文案。
- 菠萝视频、菠萝相册子页顶部补齐对应标题，保留原有中央状态插图与说明。
- 三个入口及三个返回路径均完成点击验证；隔离浏览器会话中的正常主流程无控制台警告或错误。

## 修复记录

| 级别 | 初始问题 | 修复方式 | 复验结果 |
| --- | --- | --- | --- |
| P1 | Web Release 的三个分类卡片仅显示彩色底块，Material 图标被字体裁剪 | 将动态 `IconData` 改为按分类分支直接引用具体 Material 图标，使编译器保留对应字形 | 三个图标在 Release 产物中完整可见 |
| P2 | “今天想去哪里玩？”字号过大且带额外说明 | 改为 `bodyLarge`，删除附加说明 | 单行正文层级显示正常 |
| P2 | 子页面标题栏结构不一致 | 统一为“返回按钮 + 分类标题”，早教移除品牌图标和小文案，视频与相册补标题 | 三个子页标题栏一致 |

## 自动化验证

- `flutter analyze`：通过。
- `flutter test`：47 项通过。
- `flutter build web --release --base-href=/ --dart-define=API_BASE_URL=https://wx.jiayuntong.com:5172/server/`：通过。

