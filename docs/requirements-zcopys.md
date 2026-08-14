# Zcopys 产品需求文档（PRD）

| 项 | 内容 |
|---|---|
| 产品名 | **Zcopys** |
| 文档类型 | 需求文档 / PRD（基于当前代码与已落盘设计规格） |
| 文档日期 | 2026-08-14 |
| 代码基线 | 工作区 `Sources/Zcopys`、`Tests/ZcopysTests`、`docs/superpowers/specs/`、`README.md` |
| 默认 Bundle ID | `com.local.zcopys` |
| 默认营销版本 | `1.0.0`（打包脚本变量 `MARKETING_VERSION`） |
| 最低系统 | macOS 14.0（`Package.swift` / `Info.plist`：`LSMinimumSystemVersion`） |

### 范围说明

本文档描述 **当前代码已实现或已明确进入一期规格的行为**，不以口头设想为准。对「设计有、UI 未挂接」或「一期明确不做」的能力，在第 7 节单独标注。

**不在本文档范围：** 自动更新（Sparkle）、剪贴板历史 iCloud 同步、自定义分类图标、拖拽排序分类。

---

## 1. 产品概述与目标用户

### 1.1 产品定位

Zcopys 是一款 **常驻 macOS 菜单栏** 的剪贴板增强工具（`LSUIElement = true`，无 Dock 图标）。核心价值：

1. **自动记录** 系统剪贴板中的文本、链接、文件 URL、图片；
2. 通过 **全局快捷键或菜单栏** 呼出底部横向玻璃面板，快速检索、选中并 **回填到先前前台应用**；
3. 提供 **Useful Links** 与 **自定义分类**，沉淀常用链接/文本；
4. 一期支持将 **分类与链接** 经 **CloudKit 私有库** 在同一 Apple ID 下多台 Mac 间同步。

### 1.2 目标用户

- 需要频繁在文档、浏览器表单（含 App Store Connect 等 Web 表单）、终端相关工作流间复用剪贴板内容的 macOS 用户；
- 希望把常用链接/口令式文本（非敏感策略拦截项）整理成标签页的个人用户；
- 使用多台 Mac、希望分类与收藏链接随 iCloud 账号走的用户（需完成 Developer CloudKit 配置与带 entitlements 的签名包）。

### 1.3 产品目标（可验收）

| 目标 | 说明 |
|---|---|
| 低打扰驻留 | 菜单栏图标 + 可选快捷键；启动不强制弹辅助功能权限 |
| 历史可用 | 文本/URL/文件/图片可搜、可置顶、可清空、有容量上限 |
| 快速回填 | 选中后写入剪贴板并尽量自动粘贴到呼出前的前台应用 |
| 收藏与分类 | Useful Links + 自定义分类；本地 JSON 持久化 |
| 一期云同步 | 仅分类与链接；剪贴板历史与图片不同步 |

---

## 2. 运行环境与依赖

### 2.1 平台与构建

| 项 | 要求 |
|---|---|
| OS | macOS **14.0+** |
| 语言 / 包管理 | Swift 5.9+，Swift Package Manager（`Package.swift`） |
| UI | SwiftUI + AppKit（`NSPanel`、状态栏、Carbon 热键、CGEvent） |
| 本地运行 | `swift build` / `swift run` |
| 测试 | `swift test` |
| 分发包 | `./Scripts/package_app.sh` → `dist/Zcopys.app`、zip、dmg；可选安装到 `/Applications/Zcopys.app` |

### 2.2 权限

| 权限 | 用途 | 是否启动即要求 |
|---|---|---|
| **辅助功能（Accessibility）** | ① 向其他应用自动粘贴（Accessibility 写文本或模拟 ⌘V）；② 面板为 `nonactivatingPanel` 时用 CGEvent tap 拦截 ←/→/Tab/Return/Esc，避免按键落到浏览器输入框 | **否**。启动不弹权限框；未授权时仍可复制到剪贴板，反馈「已复制，请按 ⌘V 粘贴」。状态栏右键菜单与面板 `⋯` 可引导打开系统设置 |
| **全局快捷键 ⌘⇧V** | Carbon `RegisterEventHotKey` 注册，**不依赖**辅助功能；失败时回退 NSEvent 全局/本地监听 | 否 |
| **iCloud / CloudKit** | 一期同步分类与链接 | 需 Apple ID 登录 iCloud；且 App 以含 CloudKit entitlements 的方式签名（见下） |

说明：`HotkeyMonitor` 注释明确 — 热键本身不需要 Accessibility；**自动粘贴**需要。

### 2.3 Apple ID / CloudKit（一期）

| 项 | 当前实现 |
|---|---|
| 容器 | 默认 `iCloud.com.local.zcopys`（打包时为 `iCloud.${BUNDLE_IDENTIFIER}`） |
| 数据库 | CloudKit **Private** database |
| Record 类型 | `ZCategory`、`ZLinkItem` |
| 开发者前置 | Apple Developer 为 Bundle ID 开启 **iCloud → CloudKit**，创建匹配容器，并用匹配的签名/profile |
| 本地打包默认 | `ENABLE_ICLOUD_ENTITLEMENTS` 默认 **0**：签名不含 iCloud 受限权限，避免无 profile 时进程被系统杀掉；完整同步需 `ENABLE_ICLOUD_ENTITLEMENTS=1` |
| 运行时检测 | `CloudKitSyncEngine.hasICloudEntitlement`：无 CloudKit entitlement 时不构造 `CKContainer`（避免 SIGTRAP），并提示重新打包 |
| 非 `.app` 运行 | `swift run` / 测试环境：不启用真实 CloudKit |

### 2.4 应用形态

- `LSUIElement = true`：仅菜单栏驻留；
- 面板：无边框、半透明材质、浮动于状态栏层级、可跨 Space / 全屏辅助；
- Settings Scene 为空壳（`EmptyView()`），无独立系统设置窗口。

---

## 3. 功能需求

以下每项尽量包含：**描述 / 触发方式 / 规则与边界 / 验收标准**。

---

### 3.1 菜单栏 / 状态栏

**描述**  
应用在系统状态栏显示图标；左键切换历史面板，右键（或 Control+点击）弹出菜单。

**触发方式**

| 操作 | 行为 |
|---|---|
| 左键点击状态栏图标 | 面板已显示则关闭，否则 `showHistoryWindow()` |
| 右键 / Control+左键 | 弹出菜单：打开历史、清空记录、（未授权时）辅助功能提示与授权入口、退出（⌘Q） |

**规则与边界**

- 图标优先加载 `StatusBarIcon.png`（非 template）；缺失时用 SF Symbol `arrow.triangle.2.circlepath`；
- 「清空记录」仅清空 **剪贴板历史**（`clearHistory`），不影响 Useful Links / 分类；
- 启动时向剪贴板历史写入一条测试文案：「启动成功 ✓ — 复制文字即可记录」（便于确认监控存活）；
- 前台应用切换时刷新辅助功能信任状态（不主动弹权限）。

**验收标准**

- [ ] 左键可反复开关面板；
- [ ] 右键菜单项齐全；未授权时出现授权引导；
- [ ] 「退出」终止应用；
- [ ] 点击状态栏区域本身不会被「点击面板外关闭」误关（面板关闭逻辑会忽略状态栏窗口区域）。

---

### 3.2 快捷键呼出面板

**描述**  
全局快捷键 **⌘⇧V** 呼出历史面板（与左键打开同一套 `showHistoryWindow`）。

**触发方式**

1. 优先 Carbon 热键（`cmdKey | shiftKey` + `V`）；
2. 同时安装 NSEvent 全局/本地 `keyDown` 作为回退与应用内补强；
3. Carbon 与 NSEvent 可能重复触发，**0.35s 内防抖**。

**规则与边界**

- 修饰键须为 **恰好 ⌘+⇧**（不含 ⌥/⌃）；忽略 Caps Lock / Fn 干扰逻辑见实现；
- Carbon 注册失败（如 `-9878` 热键被占用）时打印日志并依赖 NSEvent；
- 呼出前记录「先前前台应用」作为粘贴目标；延迟约 **0.1s** 再显示面板（等待菜单关闭）；
- **不自动聚焦搜索框**，以免抢走浏览器（如 App Store Connect）输入焦点、破坏后续自动粘贴。

**验收标准**

- [ ] 其他应用前台时按 ⌘⇧V 可打开面板；
- [ ] 短时间内连按不会重复打开两次；
- [ ] 打开后面板不强制抢键，除非用户主动展开搜索/编辑器。

---

### 3.3 剪贴板历史（Clipboard）

**描述**  
后台轮询系统剪贴板，将符合规则的内容写入本地历史，并在 Clipboard 标签以横向卡片展示。

#### 3.3.1 采集

**触发方式**  
`ClipboardMonitor` 每 **0.5s** 比较 `NSPasteboard.changeCount`；有变化则按优先级读取：

1. 文件 URL（仅 file URL）；
2. 否则图片（`NSImage(pasteboard:)`）；
3. 否则纯文本字符串。

**规则与边界**

| 类型 | 行为 |
|---|---|
| 文本 | trim 后非空；非敏感；以 `http://`/`https://` 开头记为 `url`，否则 `text` |
| 文件 | 展示名：单文件用文件名，多文件用 `N files`；payload 为路径列表（换行拼接） |
| 图片 | TIFF 表示；单张超过 **8MB** 丢弃；展示文案 `Image W×H`；payload 为 Base64 TIFF |
| 去重 | 同 `kind` + 同 `payload`：不新建，只更新 `lastUsedAt` |
| 敏感跳过 | 见下表；**不写入历史**（已在历史中的条目仍可加入 Useful Links） |

**敏感内容启发式（不记录）** 包括但不限于：

- `sk-…` 类密钥、GitHub token、`AKIA…`、Bearer token、JWT 形态；
- 6 位纯数字（验证码）、12–19 位数字（常见卡号，归一化去空格/连字符后）；
- `password` / `verification code` / `otp` / `secret` 赋值形态；
- 含 `-----BEGIN` 与 `PRIVATE KEY-----` 的私钥块。

**容量与排序**

- 排序：置顶优先，其次 `lastUsedAt` 新→旧；
- 未置顶条目上限 **200**；
- 未置顶图片上限 **30** 张，且未置顶图片累计 Base64 体积约 **80MB**；
- 置顶条目不受上述未置顶裁剪剔除（裁剪循环只处理未置顶）。

**持久化**  
`~/Library/Application Support/Zcopys/clipboard-history.json`；若无新路径文件则尝试从旧路径 `…/mac_tool/clipboard-history.json` 迁移复制。

**验收标准**

- [ ] 复制普通文本/链接/文件/图片出现在 Clipboard；
- [ ] 敏感样例不被记录（测试覆盖卡号与 `sk-`）；
- [ ] 重复内容更新时间而非新增；
- [ ] 未置顶超过 200 被裁剪；置顶始终靠前。

#### 3.3.2 搜索与展示

**触发方式**  
点击放大镜展开搜索；过滤 **当前标签**（Clipboard 下匹配 `value`，不区分大小写）。

**卡片 UI（Clipboard）**

- 约 **200×280**；彩色标题栏（类型标签 + 相对时间 + 图标）、正文预览、底部字数与 1-based 序号；
- 类型色：文本蓝 / URL 青 / 文件深灰 / 图片紫；类 shell 命令文本用红色「command」色（类型仍为 Text）；
- 选中态：强调色描边；选中项变化时横向滚动居中。

**验收标准**

- [ ] 搜索只影响当前标签列表与选中同步；
- [ ] 空列表显示「No Clipboard History」空态。

---

### 3.4 面板交互

**描述**  
底部铺满当前鼠标所在屏 `visibleFrame` 宽度、高度 **400** 的玻璃面板（顶部圆角约 22，底部贴齐）。

#### 3.4.1 鼠标

| 操作 | Clipboard | Useful Links / 自定义分类 |
|---|---|---|
| **单击** 卡片 | 仅选中 | 仅选中 |
| **双击** 卡片 | 激活（复制并尝试粘贴后关闭） | 激活（打开 URL 或复制并粘贴） |
| **拖拽** 卡片 | `DragExport`：文本/URL→文本；文件→文件 provider；图片→图像 | http(s)→URL+纯文本；其他→纯文本 |
| **右键** | Copy / Pin·Unpin / Add to… / Delete | Open·Copy / Edit / Pin·Unpin / Delete |
| **点击面板外** | 关闭面板并清理搜索/编辑器状态（状态栏点击除外） | 同左 |

#### 3.4.2 键盘（面板可见时）

| 按键 | 行为 |
|---|---|
| ← / → | 在当前过滤列表中移动选中（到头/到尾不再越界） |
| Tab / Shift+Tab | 同右/左移动 |
| Return / 小键盘 Enter | 激活当前选中项 |
| Esc | 若搜索展开或有搜索文案 → 先清空并收起搜索；若分类/链接编辑器打开 → 取消编辑；否则关闭面板 |

**规则与边界**

- 面板为 **nonactivatingPanel**：默认不抢前台应用焦点；搜索/编辑器需要输入时再 `makeKeyForTyping`；
- 搜索或编辑器持有输入焦点、或 IME `hasMarkedText` 时：导航键不拦截（Esc 仍可取消）；
- 全局 CGEvent tap 在拦截导航键时吞掉事件，避免浏览器光标被一并移动；无辅助功能时 tap 可能不可用（日志提示）；
- 未选中时：向右选第一项，向左选最后一项；空列表移动后选中为 `nil`。

**验收标准**

- [ ] 单击不粘贴、双击才激活（与 Return 一致路径）；
- [ ] Esc 分层：编辑器 → 搜索 → 关面板；
- [ ] 点击外部关闭；拖拽可将内容拖到其他应用。

---

### 3.5 分类系统（内置 + 自定义）

**描述**  
面板顶部标签：**Clipboard**、**Useful Links**（内置，不可删）+ 用户自定义分类（同级标签）+  persistently 的 **`+`（新建分类）**。

**触发方式**

| 操作 | 行为 |
|---|---|
| 点击 Clipboard / Useful Links | 切换标签并同步选中 |
| 单击自定义标签 | 选中该分类 |
| 双击自定义标签 | 打开重命名编辑器 |
| 自定义标签右键 | Rename / Move Left / Move Right / Delete |
| 顶部 `+` | 打开「New Category」编辑器（名称必填） |

**规则与边界**

- 分类名 trim 后非空；排序字段 `sortOrder`；左右移动为相邻交换后规范化序号；
- 删除分类：删除该分类下全部条目（`UsefulLinksStore.deleteAll`），若当前正在该分类则切回 Useful Links；
- 自定义分类 **无独立图标**（规格明确 out of scope）；
- **不支持**拖拽排序分类（用左右移动）；
- 条目模型与 Useful Links 相同，用 `categoryId` 区分：`nil` = Useful Links 标签；
- 持久化：`~/Library/Application Support/Zcopys/categories.json`。

**验收标准**

- [ ] 可创建/重命名/左右移动/删除分类；
- [ ] 删除分类后其条目消失；
- [ ] 空名无法保存；
- [ ] Useful Links 与自定义分类条目互不去重（同 URL 可各存一条，按 `categoryId` 作用域去重）。

**与设计差异（见 §7）**  
规格要求「选中自定义标签时提供条目级 `+`」；当前顶部 `+` **仅**绑定 `beginAddCategory`。条目新增主要依赖剪贴板右键「Add to…」及已有条目的 Edit；`AppState.beginAddUsefulLink` / 链接编辑器逻辑已存在，但面板未提供独立「Add Item」入口。

---

### 3.6 Useful Links

**描述**  
手动收藏的标题 + URL/文本列表；可从剪贴板加入；支持置顶、搜索、打开或复制粘贴。

**触发方式**

| 操作 | 行为 |
|---|---|
| 剪贴板卡片右键 → Add to… → Useful Links | `title` = `value` 前 80 字；`urlOrText` = `payload` |
| 剪贴板 → Add to… → 某自定义分类 | 同上，写入对应 `categoryId` |
| 链接卡片右键 Edit | 打开编辑器 |
| 双击 / Open·Copy / Return | 见激活规则 |
| ⋯ → Clear Current Tab（在 Useful Links / 自定义分类下） | 仅清空该 `categoryId` 作用域 |

**规则与边界**

- `urlOrText` trim 后必填；`title` 可空，默认取 body 前 80 字；
- **同分类内** 相同 `urlOrText`：更新标题与时间，不新增；
- 编辑成与另一条同分类同 body：合并到已有并删除正在编辑的那条；
- 排序：置顶优先，再按 `lastUsedAt`；
- 搜索：匹配 `title` 或 `urlOrText`；
- Useful Links 非空时标签旁显示 **红点**；自定义分类同理；
- 持久化：`~/Library/Application Support/Zcopys/useful-links.json`（含 legacy `mac_tool` 迁移）。

**激活规则**

| `urlOrText` | 行为 |
|---|---|
| 可解析且 scheme 为 `http`/`https` | `markUsed` → 默认浏览器打开 → 关闭面板（**不**走自动粘贴） |
| 其他 | 写入剪贴板 → `markUsed` → 关闭面板并尝试粘贴到先前应用 |

**验收标准**

- [ ] 空 body 无法保存（编辑器保持打开）；
- [ ] 去重、置顶、过滤、按分类清空行为与单测一致；
- [ ] http(s) 打开浏览器；普通文本走粘贴路径。

---

### 3.7 粘贴到目标应用

**描述**  
用户激活剪贴板条目或非 URL 的 Useful Link 后：先写系统剪贴板，关闭面板，激活先前前台应用，再按策略插入内容。

**触发方式**  
`copyItemAndClose` / `activateUsefulLink`（非 http）→ `closePanelAndPasteIntoPreviousApp`。

**规则与边界**

1. **先前应用**：打开面板前记录；之后若其他应用成为前台则更新；忽略本进程；
2. **写剪贴板**：优先不激活本 App（避免抢走 App Store Connect 等 Web 输入焦点）；失败再 activate 重试；
3. **无辅助功能**：只激活目标并提示「已复制，请按 ⌘V 粘贴」；
4. **有辅助功能**：延迟后激活目标（若已是前台则 **不再** `activate`，避免 Chromium 丢 first responder），再粘贴；
5. **策略**（`PasteboardPaster`）：
   - **浏览器类**（Safari / Chrome / Brave / Arc / Edge / Firefox / Opera / Vivaldi / Zen 等 Bundle ID，或名称含 chrome/safari/firefox/edge/brave/arc/opera）：仅模拟 ⌘V（`keystrokeOnly`）；延迟略长（约 0.12s 激活 + 0.28s 粘贴）；
   - **其他应用**：优先 Accessibility 写入聚焦控件的 `AXSelectedText`（`AXWebArea` 直接失败以免假成功），否则 ⌘V；延迟约 0.08s + 0.18s；
6. **可自动插入的文本**：剪贴板条目仅 `text` / `url` / `other` 传文本 fallback；**文件与图片**只保证剪贴板内容，粘贴依赖 ⌘V 对文件/图片的处理；
7. 粘贴失败反馈：「无法复制此记录」。

**验收标准**

- [ ] 原生文本框：在授权后可自动插入或 ⌘V 成功；
- [ ] 浏览器 Web 表单：走 keystroke-only，不依赖 AX 假成功；
- [ ] 未授权时不弹权限框打断，只提示手动 ⌘V。

---

### 3.8 iCloud 同步（一期）

**描述**  
在同一 Apple ID 下，双向同步 **自定义分类** 与 **Useful Links / 分类条目**；**不同步**剪贴板历史与图片。

**触发方式**

| 时机 | 行为 |
|---|---|
| 应用启动且同步开启 | `syncNow(reason: "launch")` |
| 本地分类/链接变更 | debounce **800ms** 后 `syncNow(reason: "localChange")` |
| 面板 `⋯` →「立即同步」 | `syncNow(reason: "manual")` |
| 打开「iCloud 同步分类与链接」开关 | 若引擎已 start，立即同步 |

**UI（面板 `⋯`）**

- Toggle：`iCloud 同步分类与链接`（UserDefaults 键 `zcopys.icloudSyncEnabled`；正式 CloudKit 包默认 **true**）；
- 「立即同步」/「同步中…」（同步中或关闭时禁用）；
- 上次同步时间、账号状态文案、最近错误文案；
- 未授权辅助功能时另有 Request Accessibility Permission。

**合并策略**

- 按记录 **id** 对齐；冲突取 **`updatedAt` 更大** 的一方；
- 本地与远端 **并集**：仅存在于一侧的 id 保留；
- 分类合并后按 `sortOrder` / `createdAt` 排序；
- 推送：将合并结果整批 upsert 到 Private DB（分块 100）；`savePolicy: .changedKeys`。

**规则与边界**

- 账号非 `available` 时不同步，并设置可读错误（未登录 / 受限 / 暂时不可用 / 无法确认）；
- 无 iCloud entitlement：提示用 `ENABLE_ICLOUD_ENTITLEMENTS=1` 重新打包；
- CloudKit 常见错误映射：未登录、网络、配额、容器未配置等；
- **删除同步限制（一期现状）**：推送路径 `deleting: []`，无墓碑；本地删除后若云端仍有记录，下次拉取合并可能 **把条目拉回**。需求上应视为一期已知限制，后续阶段需补删除/墓碑策略。

**验收标准**

- [ ] 两台 Mac、同一 Apple ID、正确签名与容器：分类与链接可双向合并（新 `updatedAt` 胜出）；
- [ ] 关闭开关后本地改动不再触发上传；
- [ ] 剪贴板历史文件不出现在 CloudKit 记录类型中；
- [ ] 单测：`SyncMerge` 同 id 取新、不同 id 并集。

---

### 3.9 设置 / 菜单项汇总

| 入口 | 菜单项 / 控件 |
|---|---|
| 状态栏右键 | 打开历史；清空记录（仅历史）；辅助功能提示/授权；退出 |
| 面板 `⋯` | Clear Current Tab；iCloud 开关；立即同步；同步状态；辅助功能请求 |
| 系统 Settings Scene | 空（无独立设置页） |

**Clear Current Tab**

- Clipboard → `clearHistory`；
- Useful Links → `clear(categoryId: nil)`；
- 自定义 → `clear(categoryId: id)`。

---

## 4. 非功能需求

### 4.1 性能与资源

| 项 | 指标 / 行为 |
|---|---|
| 剪贴板轮询 | 500ms |
| 历史规模 | 未置顶 ≤200；图片张数/体积上限见 §3.3 |
| 同步防抖 | 本地变更 800ms |
| 同步推送分块 | 每批 ≤100 条 CKRecord |
| 面板布局 | 单屏底部全宽 × 400pt，避免遮挡过多工作区中部 |

### 4.2 隐私与安全

- 敏感剪贴板内容尽量不落盘（启发式，非密码学保证）；
- 一期云端仅 Private DB；不同步剪贴板历史与图片；
- 辅助功能仅用于粘贴与（可选）导航键拦截；不采集其他应用内容到云端；
- 本地数据在用户主目录 Application Support 下，明文 JSON（当前实现无加密）。

### 4.3 本地存储路径

| 文件 | 路径 |
|---|---|
| 剪贴板历史 | `~/Library/Application Support/Zcopys/clipboard-history.json` |
| Useful Links | `~/Library/Application Support/Zcopys/useful-links.json` |
| 自定义分类 | `~/Library/Application Support/Zcopys/categories.json` |
| 同步开关 | `UserDefaults`：`zcopys.icloudSyncEnabled` |
| 旧版迁移 | 若新路径不存在，从 `…/mac_tool/` 下同名 json **复制**一次 |

### 4.4 签名、打包与公证

| 能力 | 说明 |
|---|---|
| `package_app.sh` | release 构建、生成图标、写入 Info.plist、codesign、zip/dmg；默认装到 `/Applications` |
| 签名身份 | 优先环境变量；否则本机第一枚 `Apple Development:…`；都没有则 ad-hoc（辅助功能开关跨重建不稳定） |
| iCloud entitlements | 默认关闭；`ENABLE_ICLOUD_ENTITLEMENTS=1` 写入容器 `iCloud.${BUNDLE_IDENTIFIER}` |
| 分发 | 可设 `SIGNING_IDENTITY`（Developer ID）、`BUNDLE_IDENTIFIER`、`MARKETING_VERSION`、`BUILD_NUMBER` |
| 公证 | `Scripts/notarize_app.sh` + `NOTARYTOOL_PROFILE`；要求 Developer ID Application 签名 |

### 4.5 可靠性 / UX 约束（实现已编码）

- 不在启动时反复 `AXIsProcessTrustedWithOptions(prompt:)`，避免权限开关被「弹窗+激活」冲掉；
- 粘贴前不 `NSApp.hide`；
- 面板非激活显示，保护 Web 表单焦点。

---

## 5. 数据模型概要

### 5.1 `ClipboardItem`

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | UUID | 主键 |
| `kind` | enum | `text` / `url` / `file` / `image`；另保留 `other`、`sensitive` 兼容旧数据 |
| `value` | String | 展示文案 |
| `payload` | String | 回写内容（默认等于 value；文件为路径列表；图片为 Base64） |
| `createdAt` | Date | 创建时间 |
| `lastUsedAt` | Date | 最近使用/去重刷新 |
| `isPinned` | Bool | 置顶 |

**不同步到 CloudKit（一期）。**

### 5.2 `UsefulLink`

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | UUID | 主键；CK recordName `link-{uuid}` |
| `title` | String | 展示标题 |
| `urlOrText` | String | URL 或任意文本 |
| `createdAt` | Date | |
| `lastUsedAt` | Date | 打开/复制/去重更新 |
| `updatedAt` | Date | 冲突比较；旧数据缺省时回退 `lastUsedAt` |
| `isPinned` | Bool | |
| `categoryId` | UUID? | `nil` = Useful Links 标签 |

### 5.3 `PanelCategory`

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | UUID | 主键；CK recordName `category-{uuid}` |
| `name` | String | 标签名 |
| `sortOrder` | Int | 显示顺序 |
| `createdAt` | Date | |
| `updatedAt` | Date | 冲突比较 |

### 5.4 CloudKit 字段映射（一期）

**ZCategory：** `id`, `name`, `sortOrder`, `createdAt`, `updatedAt`  
**ZLinkItem：** `id`, `title`, `urlOrText`, `createdAt`, `lastUsedAt`, `updatedAt`, `isPinned`(0/1), `categoryId`(空串表示 nil)

### 5.5 运行时状态（非持久或半持久）

`AppState`：`selectedTab`（`.clipboard` / `.usefulLinks` / `.custom(UUID)`）、搜索展开与文案、选中 ID、链接/分类编辑器字段、反馈 Toast、辅助功能信任标志、先前前台应用等。

---

## 6. 已实现 vs 未实现 / 后续阶段

### 6.1 已实现（代码可验证）

| 模块 | 状态 |
|---|---|
| 菜单栏驻留、左键面板、右键菜单 | ✅ |
| ⌘⇧V 热键 + 防抖 | ✅ |
| 剪贴板监控（文本/文件/图片）+ 敏感过滤 + 容量 | ✅ |
| 底部玻璃面板、横向卡片、搜索、Esc 分层 | ✅ |
| 单击选中 / 双击激活 / 拖拽导出 / 点击外部关闭 | ✅ |
| 置顶、删除、清空当前标签 | ✅ |
| Useful Links CRUD 存储、去重、置顶、搜索 | ✅ |
| 自定义分类 CRUD、左右移动、删分类连带删条目 | ✅ |
| 从剪贴板 Add to Useful Links / 自定义分类 | ✅ |
| 自动粘贴策略（浏览器 keystroke-only vs AX） | ✅ |
| CloudKit 一期引擎、开关 UI、合并、防抖推送 | ✅（依赖正确签名与容器） |
| 打包 / 可选 iCloud entitlements / 公证脚本 | ✅ |
| 单测：Store / AppState / CardPresentation / SyncMerge | ✅ |

### 6.2 部分实现 / 与规格有缺口

| 项 | 说明 |
|---|---|
| 手动「添加链接/条目」入口 | `AppState` + 链接编辑器 overlay 已实现；顶部 `+` 目前只建分类，**缺少** Useful Links/自定义分类下的条目 `+` UI |
| 云端删除 | 本地删除后可能被远端记录在下次 sync 时合并回来；无 tombstone |
| 面板尺寸 | 早期设计稿约 1100×420；现行为 **全宽 × 400** |
| Useful Links 存储路径 | 旧设计写 `mac_tool/`；现统一 `Zcopys/` + 迁移 |

### 6.3 明确后续阶段 / Out of scope

| 阶段 / 项 | 说明 |
|---|---|
| **二期：剪贴板历史同步** | 规格与 README 均写明一期 **不含** 历史与图片 |
| 自定义分类图标 | Out of scope |
| 拖拽排序分类 | Out of scope（用左右移动） |
| 剪贴板历史子分类 | Out of scope |
| Sparkle 自动更新 | 面板 UI 设计 non-goal |
| 独立 Settings 窗口 | 当前 EmptyView |
| 加密本地 JSON | 未实现 |

---

## 7. 附录

### 7.1 关键文件 / 模块索引

| 路径 | 职责 |
|---|---|
| `Sources/Zcopys/ZcopysApp.swift` | `@main`、AppDelegate、状态栏与菜单 |
| `Sources/Zcopys/AppState.swift` | 全局状态、热键/监控装配、激活与粘贴编排、编辑器 |
| `Sources/Zcopys/ClipboardPanelController.swift` | NSPanel、布局、外点关闭、键盘与 CGEvent tap |
| `Sources/Zcopys/ContentView.swift` | 面板 UI：标签、搜索、卡片、编辑器、`⋯` 菜单 |
| `Sources/Zcopys/ClipboardStore.swift` | 历史持久化、敏感过滤、容量、回写剪贴板 |
| `Sources/Zcopys/ClipboardMonitor.swift` | 剪贴板轮询 |
| `Sources/Zcopys/ClipboardItem.swift` | 历史模型 |
| `Sources/Zcopys/UsefulLink.swift` / `UsefulLinksStore.swift` | 链接模型与存储 |
| `Sources/Zcopys/PanelCategory.swift` / `CategoryStore.swift` | 分类模型与存储 |
| `Sources/Zcopys/CloudKitSyncEngine.swift` | 一期同步、合并、账号状态 |
| `Sources/Zcopys/PasteboardPaster.swift` | 粘贴策略与 ⌘V 模拟 |
| `Sources/Zcopys/HotkeyMonitor.swift` | ⌘⇧V |
| `Sources/Zcopys/DragExport.swift` | 拖拽 `NSItemProvider` |
| `Sources/Zcopys/CardPresentation.swift` | 卡片色、相对时间、shell 启发式 |
| `Resources/Zcopys.entitlements` | CloudKit 容器与 get-task-allow（打包时可能改写） |
| `Scripts/package_app.sh` | 构建、签名、entitlements 开关、安装 |
| `Scripts/notarize_app.sh` | 公证 |
| `Tests/ZcopysTests/*` | 行为回归 |

### 7.2 相关设计规格

| 文档 | 内容 |
|---|---|
| `docs/superpowers/specs/2026-07-29-clipboard-panel-ui-design.md` | 横向卡片 UI + Useful Links |
| `docs/superpowers/specs/2026-08-14-custom-categories-design.md` | 自定义分类 |
| `docs/superpowers/specs/2026-08-14-icloud-sync-phase1-design.md` | iCloud 一期范围与合并 |
| `README.md` | 产品现状、同步配置与打包说明 |

### 7.3 行为证据（测试对照）

| 测试文件 | 覆盖需求要点 |
|---|---|
| `ClipboardStoreTests` | 置顶顺序、去重、敏感跳过、200 上限 |
| `UsefulLinksStoreTests` | 默认标题、拒空 body、去重/合并、置顶、过滤、分类作用域 |
| `CategoryStoreTests` | 增删改移、拒空名 |
| `AppStateTests` | 左右选中边界、加入 Useful Links、清空当前标签、编辑器校验 |
| `SyncMergeTests` | `updatedAt` 胜出、id 并集 |
| `CardPresentationTests` | shell 色、相对时间、字数文案 |

---

## 8. 修订记录

| 日期 | 说明 |
|---|---|
| 2026-08-14 | 初版：依据当时工作区代码、README 与 superpowers specs 整理，中文需求表述 |
