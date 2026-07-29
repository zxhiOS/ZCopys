# mac_tool

这是一个常驻菜单栏的 macOS 剪贴板增强器。

## 当前目标

- 自动记录剪贴板历史
- 支持搜索、置顶、清空、键盘选择和回填
- 支持文本、链接、文件 URL 与图片
- 用 `⌘⇧V` 呼出横向卡片画廊式玻璃面板（约 1100×420，圆角 ~28）
- **Clipboard / Useful Links** 双标签页；当前标签页内可展开搜索
- **Useful Links**：手动添加链接，或从剪贴板条目收藏；支持置顶、去重与打开/复制
- Useful Links 持久化路径：`~/Library/Application Support/mac_tool/useful-links.json`

## 代码结构

- `Sources/mac_tool/ClipboardItem.swift`
- `Sources/mac_tool/ClipboardStore.swift`
- `Sources/mac_tool/ClipboardMonitor.swift`
- `Sources/mac_tool/UsefulLink.swift`
- `Sources/mac_tool/UsefulLinksStore.swift`
- `Sources/mac_tool/CardPresentation.swift`
- `Sources/mac_tool/ClipboardPanelController.swift`
- `Sources/mac_tool/AppState.swift`
- `Sources/mac_tool/mac_toolApp.swift`
- `Sources/mac_tool/ContentView.swift`

## 下一步

直接在项目根目录运行：

```bash
swift build
swift run
```

运行回归测试：

```bash
swift test
```

生成可双击的 `.app`：

```bash
./Scripts/package_app.sh
open ./dist/mac_tool.app
```

当前脚本会同时：

- 生成基础应用图标
- 使用 `release` 配置构建并打包成 `.app`
- 生成 `zip` 和 `dmg`
- 在设置 `SIGNING_IDENTITY` 时做 Developer ID 签名和 Hardened Runtime
- 否则做一次仅适合本机测试的 ad-hoc 签名

未提供 `SIGNING_IDENTITY` 的包不能通过其他 Mac 的 Gatekeeper 校验。用于分发时，请传入你的 Developer ID 身份和已注册的 Bundle ID：

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
BUNDLE_IDENTIFIER="com.yourcompany.clipboard" \
MARKETING_VERSION="1.0.0" \
BUILD_NUMBER="1" \
./Scripts/package_app.sh
```

可选的公证流程：

```bash
xcrun notarytool store-credentials "mac_tool" --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-password"
NOTARYTOOL_PROFILE=mac_tool ./Scripts/notarize_app.sh
```

公证脚本会：

- 验证 Developer ID 签名并创建上传包
- 通过 `xcrun notarytool submit --wait` 上传
- 用 `xcrun stapler staple` 把票据钉回 `.app`
- 自动重新生成含票据的最终 `zip` 和 `dmg`

如果你只想分发安装包，可以直接拿：

- `dist/mac_tool.zip`
- `dist/mac_tool.dmg`

当前支持：

- 文本 / 链接
- 文件 URL
- 图片剪贴板
- 自动跳过常见验证码、银行卡号、私钥和 API Token
- 置顶记录始终优先，重复内容只更新原记录
- 横向卡片 UI：彩色标题栏、正文预览、底部操作；左右方向键切换选中项
- Useful Links 标签：右键剪贴板条目「Add to Useful Links」，或顶部 `+` 手动编辑
- 搜索栏可展开；`Esc` 先收起搜索再关闭面板
