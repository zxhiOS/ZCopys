# 跟着做：用 Cursor 从 0 到 1 做 macOS 剪贴板工具 Zcopys

> 适合人群：会一点 Swift / 想用 AI 加速桌面开发的同学  
> 成品能力：菜单栏常驻、`⌘⇧V` 呼出底部卡片面板、自动粘贴、Useful Links、打包安装  
> 预计耗时：1～2 个周末（有 AI 协作会更快）

---

## 0. 你将做出什么

做完后，你的 Mac 上会有一个叫 **Zcopys** 的菜单栏应用：

1. 复制任何文本 / 链接 / 文件 / 图片，自动记入历史  
2. 按 `⌘⇧V`，屏幕底部弹出横向卡片面板  
3. 点一张卡片 → 内容写回剪贴板 → 尽量自动粘贴到刚才的输入框  
4. 有一个 **Useful Links** 页，收藏常用命令、路径、网址  
5. 可双击的 `/Applications/Zcopys.app`

技术栈很克制：

- Swift 5.9 + SwiftUI + AppKit  
- macOS 14+  
- Swift Package Manager（SPM）  
- 脚本打包 `.app` / zip / dmg  

---

## 1. 环境准备

### 1.1 必备

- macOS 14+  
- Xcode（含 Command Line Tools）  
- Cursor（或其他 AI 编程助手）  

验证：

```bash
swift --version
xcodebuild -version
```

### 1.2 建议准备

- Apple 开发者账号（免费的 Apple Development 证书即可，本机调试够用）  
- 一张目标 UI 图（横向卡片 / 启动器风格最好）

---

## 2. 初始化工程（第 1 步就能跑）

### 2.1 建 SPM 可执行工程

```bash
mkdir Zcopys && cd Zcopys
swift package init --type executable --name Zcopys
```

或直接在已有菜单栏剪贴板雏形上迭代（本文按「有雏形再增强」路径写，从零也可对照模块拆分）。

### 2.2 最小可运行结构

建议目录：

```text
Sources/Zcopys/
  ZcopysApp.swift          # 菜单栏入口
  AppState.swift           # 状态协调
  ClipboardMonitor.swift   # 监听剪贴板
  ClipboardStore.swift     # 历史存储
  ClipboardItem.swift      # 数据模型
  HotkeyMonitor.swift      # 全局热键
  ClipboardPanelController.swift  # 悬浮面板
  ContentView.swift        # SwiftUI 界面
```

### 2.3 给 AI 的第一句提示词

```text
帮我分析/搭建一个 macOS 菜单栏剪贴板应用（SwiftUI + AppKit）：
- 轮询 NSPasteboard，记录文本/URL/文件/图片
- 菜单栏图标 + ⌘⇧V 呼出面板
- JSON 持久化到 Application Support
- 敏感信息（验证码、卡号、Token、私钥）自动跳过
请给出模块划分，并先实现可运行的最小版本。
```

跑起来：

```bash
swift run
```

菜单栏应出现图标；复制一段文字后，历史里能看到记录。

---

## 3. 先定产品，再写大段 UI

很多人卡在「直接让 AI 照着感觉改界面」。更稳的顺序是：

### 3.1 丢设计图 + 定范围

提示词：

```text
帮我把弹出面板换成这个 UI（附图）。
先不要写代码，确认：
1) Useful Links / 搜索 / + / ⋯ 本次是否实现
2) 搜索是常驻输入框，还是点放大镜再展开
3) 点击卡片是只复制，还是复制并自动粘贴
给我 2–3 个方案和推荐，我选完再实现。
```

本项目最终选择：

- 搜索：点放大镜展开  
- Useful Links：**手动添加 + 从历史收藏**  
- 点击卡片：**复制 + 自动粘贴**（后面单独做）

### 3.2 让 AI 输出设计文档

```text
按我们确认的范围，写实现设计：布局、数据模型、交互、文件改动清单。
分段确认，我回复 ok 后再写实现计划。
```

### 3.3 再拆实现计划

```text
把设计拆成可验证任务（建议 TDD）：
Store → 展示辅助函数 → AppState → Panel 尺寸/键盘 → ContentView → README/打包。
每个任务写清要改的文件和验收方式。
```

**为什么多这一步？**  
UI 大改 + 新模块时，先冻结规则，比上来生成 500 行 Swift 更省返工。

---

## 4. 实现数据层：Clipboard + Useful Links

### 4.1 ClipboardStore 要具备的能力

- `addText` / `addFileURLs` / `addImage`  
- 去重（相同内容更新 `lastUsedAt`）  
- 置顶优先排序  
- 非置顶条数上限（例如 200）  
- 敏感内容过滤  
- 持久化：`~/Library/Application Support/Zcopys/clipboard-history.json`

提示词：

```text
实现 ClipboardStore：ObservableObject，支持文本/文件/图片，去重、置顶、容量裁剪、敏感过滤、JSON 持久化。
先写 XCTest，再写实现。存储路径可注入，方便测试。
```

### 4.2 Useful Links

模型字段建议：

- `id`, `title`, `urlOrText`, `createdAt`, `lastUsedAt`, `isPinned`

规则：

- `urlOrText` 必填；`title` 可空，默认截取正文前 80 字  
- 相同 `urlOrText` 去重  
- 持久化到 `useful-links.json`

提示词：

```text
新增 UsefulLink + UsefulLinksStore：
CRUD、置顶、过滤、去重、JSON 持久化。
并提供从 ClipboardItem 收藏的方法（title 用 value 截断，body 用 payload）。
先测试后实现。
```

---

## 5. 做面板：底部全宽 + 横向卡片

### 5.1 AppKit 面板要点

用 `NSPanel` 承载 SwiftUI：

- 无边框、透明背景  
- 每次显示时按**当前鼠标所在屏**布局  
- 位置：贴 `visibleFrame` 底部  
- 宽度：铺满可用宽度  
- 高度：约 400pt  

提示词：

```text
把剪贴板面板改成：贴屏幕底部、横向铺满当前显示器可用区域，高度约 400。
SwiftUI 内容用 maxWidth/maxHeight 撑满，顶部圆角、底部贴边。
```

### 5.2 卡片 UI

每张卡片建议三段：

1. 彩色顶栏：类型标签 + 相对时间 + 图标  
2. 白底正文预览  
3. 底栏：字符数 + 序号  

颜色可按类型：

- text：蓝  
- url：青  
- file：深灰  
- image：紫  
- 命令启发式（`git`/`npm`/`tl` 等或含 ` | `）：红  

提示词：

```text
重写 ContentView：玻璃顶栏 + Clipboard/Useful Links Tab + 横向 ScrollView 卡片。
卡片含彩色顶栏、正文、底部 meta；选中描边；右键菜单支持置顶/删除/收藏。
```

### 5.3 搜索必须能输入

坑：`nonactivatingPanel` 常常无法成为 key window，TextField 看起来在，但敲不出字。

解法：

1. 自定义 `NSPanel` 子类，`canBecomeKey = true`  
2. 本地按键监听在「输入框聚焦」时放行字符键  
3. 展开搜索后主动 `focused`

提示词：

```text
搜索框无法输入。请让面板可成为 key window，并避免 key monitor 在输入时拦截字符键。修好后重新打包。
```

---

## 6. 全局快捷键 ⌘⇧V

### 6.1 不要只靠 NSEvent 全局监听

`NSEvent.addGlobalMonitorForEvents` 强依赖辅助功能，还容易被 Caps Lock 等修饰键干扰。

更稳：用 **Carbon `RegisterEventHotKey`** 注册系统热键，再用 NSEvent 做兜底。

提示词：

```text
⌘⇧V 打不开面板。
请改用 Carbon RegisterEventHotKey 注册系统热键，并修正修饰键判断（忽略 Caps Lock）。
重新打包并验证热键可唤起。
```

### 6.2 键盘操作约定

面板打开后：

- `←` / `→`：切换选中卡片  
- `Return`：激活选中项  
- `Esc`：先清空/收起搜索，再关闭面板  

---

## 7. 自动粘贴（最容易翻车的一步）

### 7.1 目标行为

点击卡片后：

1. 内容写入剪贴板  
2. 关闭面板  
3. 回到「打开面板前」的应用  
4. 把内容粘进当前输入框  

### 7.2 实现思路

1. 打开面板前记录 `previousFrontmostApp`  
2. 复制成功后激活该应用  
3. 优先用 Accessibility 写 `AXSelectedText`  
4. 失败则模拟完整 `⌘V` 键序  

### 7.3 权限怎么处理才不会「开了又关」

常见翻车：

- 每次点击都 `AXIsProcessTrustedWithOptions(prompt:true)`  
- 弹窗出现时又 `NSApp.hide` / 切前台，把授权框冲掉  
- 用 ad-hoc 签名，每次重打包系统当新 App，开关不持久  

建议：

1. 用 **Apple Development** 证书签名  
2. 安装到 **`/Applications/Zcopys.app`**（路径稳定）  
3. 业务路径里不强制弹权限；无权限时至少「已复制，请手动 ⌘V」  
4. 用户去：系统设置 → 隐私与安全性 → 辅助功能 → 打开 Zcopys  

提示词：

```text
点击卡片后没有自动粘贴到输入框。
请实现：记录前台应用 → 复制 → 关闭面板 → 激活原应用 → AX 插入或模拟 ⌘V。
不要在每次点击时反复弹辅助功能授权；无权限时保证剪贴板已写入并提示手动粘贴。
用开发者证书签名并安装到 /Applications。
```

---

## 8. 图标与品牌

### 8.1 App Icon

1. 准备一张方图（去掉水印）  
2. 用脚本生成 `.iconset` → `.icns`  
3. 写入 `Info.plist` 的 `CFBundleIconFile`

提示词：

```text
去掉这张图右下角水印，生成 macOS App Icon（各尺寸 icns），并接入打包脚本。
```

### 8.2 状态栏图标

菜单栏小图标建议：

- 白底圆角方块  
- 灰色图形  
- `isTemplate = false`（不要被系统自动着色冲掉你的配色）

提示词：

```text
状态栏图标改成白色背景 + 灰色图标，关闭 template 着色，重新打包安装。
```

### 8.3 改名

把工程名、可执行文件、显示名、Bundle ID、Application Support 目录统一成一个品牌名（本文是 Zcopys）。

提示词：

```text
把工程名称和应用名称都改成 Zcopys，包括 Package、源码目录、Info.plist、打包脚本和 /Applications 安装名。旧数据目录如可迁移请兼容。
```

---

## 9. 打包与安装

### 9.1 一键打包

项目里用脚本完成：

```bash
./Scripts/package_app.sh
```

脚本通常会：

1. 生成 icns  
2. `swift build -c release`  
3. 组装 `Zcopys.app`  
4. codesign  
5. 产出 zip / dmg  
6. 复制到 `/Applications/Zcopys.app`

### 9.2 验证清单

打开 App 后逐项勾：

- [ ] 菜单栏图标正确  
- [ ] 复制文本后历史出现  
- [ ] `⌘⇧V` 打开底部全宽面板  
- [ ] 搜索可输入并过滤  
- [ ] 点卡片能粘贴到备忘录/文本编辑  
- [ ] Useful Links 可添加 / 打开 / 删除  
- [ ] 辅助功能授权后自动粘贴稳定  

---

## 10. 推荐的 AI 协作节奏（可直接照做）

把下面当成你的「会话剧本」：

1. **分析现状** → 搞清模块  
2. **贴 UI 图 + 选择题定范围**  
3. **要设计文档，分段 ok**  
4. **要实现计划（可测试）**  
5. **按任务实现 + `swift test`**  
6. **打包真机验收**  
7. **用「现象 + 期望」修 Bug**  
8. **最后统一品牌/图标/安装路径**

真机 Bug 提示词万能模板：

```text
【现象】……
【期望】……
【已尝试】……
请定位根因，给出最小修复，跑测试，重新打包并启动。
不要做无关重构。
```

---

## 11. 常见问题 FAQ

**Q: 为什么单元测试全绿，真机还是不行？**  
A: 焦点、热键、TCC 权限、签名，测不进 XCTest。桌面应用必须真机清单验收。

**Q: 每次重打包辅助功能都要重开？**  
A: 多半是 ad-hoc 签名。改用 Apple Development 证书，并固定安装到 `/Applications`。

**Q: 面板能出来但搜不了字？**  
A: 面板没成为 key window，或 key monitor 吞了按键。

**Q: 只复制不粘贴可以吗？**  
A: 可以。自动粘贴是增强项，但「点一下就进输入框」是剪贴板工具的核心体验之一。

---

## 12. 小结

跟做一遍，你实际练到的不只是「调用 NSPasteboard」，而是一套可迁移的桌面开发方法：

1. 先产品边界，后代码  
2. 先数据与测试，后华丽 UI  
3. 真机问题用系统关键词描述（key window / Accessibility / codesign）  
4. 用稳定签名和安装路径保护权限  

如果你把 Zcopys 跑起来了，欢迎在评论区贴一张面板截图，或说说你卡在第几步。

---

## 附录：提示词速查

```text
# 搭建
帮我做 macOS 菜单栏剪贴板 App（SwiftUI+AppKit），最小可运行版本。

# 改 UI
按附图重做弹出面板；先确认范围再写代码。

# 新功能
实现 Useful Links：手动添加 + 从历史收藏，含测试。

# 热键
⌘⇧V 无效，改用 Carbon 热键并重新打包。

# 粘贴
点卡片后自动粘贴到原输入框；处理好辅助功能，勿反复弹窗。

# 输入
搜索框无法输入，修复 key window / 按键拦截。

# 品牌
去水印换图标；状态栏白底灰标；工程改名 Zcopys 并安装到 /Applications。
```

（完）
