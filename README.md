# Zcopys

这是一个常驻菜单栏的 macOS 剪贴板增强器。

## 当前目标

- 自动记录剪贴板历史
- 支持搜索、置顶、清空、键盘选择和回填
- 支持文本、链接、文件 URL 与图片
- 用 `⌘⇧V` 呼出底部横向铺满的玻璃面板
- **Clipboard / Useful Links** 双标签页；当前标签页内可展开搜索
- **Useful Links**：手动添加链接，或从剪贴板条目收藏；支持置顶、去重与打开/复制
- 数据目录：`~/Library/Application Support/Zcopys/`

## 代码结构

- `Sources/Zcopys/ClipboardItem.swift`
- `Sources/Zcopys/ClipboardStore.swift`
- `Sources/Zcopys/ClipboardMonitor.swift`
- `Sources/Zcopys/UsefulLink.swift`
- `Sources/Zcopys/UsefulLinksStore.swift`
- `Sources/Zcopys/CardPresentation.swift`
- `Sources/Zcopys/ClipboardPanelController.swift`
- `Sources/Zcopys/AppState.swift`
- `Sources/Zcopys/ZcopysApp.swift`
- `Sources/Zcopys/ContentView.swift`

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
open ./dist/Zcopys.app
```

当前脚本会同时：

- 生成应用图标
- 使用 `release` 配置构建并打包成 `.app`
- 生成 `zip` 和 `dmg`
- 优先使用本机 Apple Development 证书签名，并安装到 `/Applications/Zcopys.app`

用于分发时，请传入你的 Developer ID 身份和已注册的 Bundle ID：

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
BUNDLE_IDENTIFIER="com.yourcompany.zcopys" \
MARKETING_VERSION="1.0.0" \
BUILD_NUMBER="1" \
./Scripts/package_app.sh
```

可选的公证流程：

```bash
xcrun notarytool store-credentials "Zcopys" --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-password"
NOTARYTOOL_PROFILE=Zcopys ./Scripts/notarize_app.sh
```

如果你只想分发安装包，可以直接拿：

- `dist/Zcopys.zip`
- `dist/Zcopys.dmg`

当前支持：

- 文本 / 链接
- 文件 URL
- 图片剪贴板
- 自动跳过常见验证码、银行卡号、私钥和 API Token
- 置顶记录始终优先，重复内容只更新原记录
- 横向卡片 UI：彩色标题栏、正文预览、底部元信息；左右方向键切换选中项
- Useful Links 标签：右键剪贴板条目「Add to Useful Links」，或顶部 `+` 手动编辑
- 搜索栏可展开；`Esc` 先收起搜索再关闭面板
- 点击卡片后自动粘贴到先前输入框（需辅助功能权限）
