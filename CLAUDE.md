# CLAUDE.md — boring.notch Fork 开发交接文档

## 项目概况

**项目**：基于开源项目 [boring.notch](https://github.com/TheBoringTeam/boring.notch) 的 Fork 二次开发。

**人员**：
- Soul Child — 想法的提出者，负责方向/范围/商业模式决策，非技术执行角色，技术选型委托给巴迪。
- 巴迪 (Buddy) — 产品需求全流程协同助手，负责技术选型、架构、实现。

**核心约束**：不再把 upstream merge-friendly 作为硬约束。以前要求"最大程度保持可合并、不大面积改已有代码、只加行"，现已取消——为功能需要可以自由修改已有代码、重构、深改核心。未来若想同步 upstream 就去尝试 `git fetch upstream && git merge upstream/main`，能合就合，合不了就不合，不为保留合并能力牺牲功能实现空间。

---

## 当前功能：Scratchpad（临时工作空间）

### 需求背景

Soul Child 在 VS Code 中有一个特殊工作流：Command+N 创建 Untitled Tab，粘贴临时内容（AI Prompt、API 返回、Debug 日志、代码片段、想法记录等），不保存、不管路径、不污染项目目录，但关闭后内容不丢。

目标：把这套工作流迁移到 boring.notch 中。

### 功能定义

Scratchpad = 临时工作上下文存储空间（不是传统笔记软件）。

核心能力：
- 创建多个 Scratch Tab
- 每个 Tab 独立保存内容
- 自动保存（debounce 500ms）
- 快速打开、快速切换
- 利用 boring.notch 原有 Notch 展开和动画能力

### 数据模型

```
ScratchTab:
  id: UUID
  title: String
  content: String
  createdAt: Date
  updatedAt: Date
  isPinned: Bool
```

### 交互设计

- **Collapsed 状态**：Scratchpad 作为 Notch tab 之一（与 Home、Shelf 并列），通过 tab 栏入口进入
- **展开后**：VS Code 风格顶部 tab 条 + 下方文本编辑区

```
┌──────────────────────────────────┐
│  Home  │  Shelf  │  Scratchpad   │  ← 顶部 tab 条
├──────────────────────────────────┤
│  Untitled-1 | Untitled-2 | +     │  ← Scratch 内部 tab
├──────────────────────────────────┤
│                                  │
│       TextEditor 编辑区           │  ← 当前 tab 内容
│                                  │
└──────────────────────────────────┘
```

---

## boring.notch 架构分析（第一阶段已完成）

### 1. 项目目录结构

```
boringNotch/
├── boringNotchApp.swift          # @main 入口 + AppDelegate
├── BoringViewCoordinator.swift   # 全局协调器单例（currentView 真相源）
├── ContentView.swift             # 根视图，Notch 收起/展开的唯一编排者
├── enums/generic.swift           # 核心枚举：NotchState、NotchViews 等
├── models/
│   ├── BoringViewModel.swift     # 每 Window 一个的 ViewModel
│   ├── Constants.swift           # Defaults.Keys 偏好键定义
│   └── ...
├── components/
│   ├── Notch/                    # BoringHeader、NotchHomeView、NotchShape、Window 类
│   ├── Tabs/                     # TabSelectionView、TabButton
│   ├── Shelf/                    # Shelf 模块（Models/Services/ViewModels/Views 四层）
│   ├── Music/、Calendar/、Settings/...
├── managers/                     # MusicManager、NotchSpaceManager 等单例
├── MediaControllers/             # 媒体控制抽象
├── sizing/matters.swift          # 尺寸常量
└── extensions/、helpers/、observers/、utils/
```

### 2. App 生命周期

- `@main DynamicNotchApp` 用 SwiftUI App 协议，逻辑委托给 `AppDelegate`（`@NSApplicationDelegateAdaptor`）
- `AppDelegate` 持有 `windows: [String: NSWindow]` 和 `viewModels: [String: BoringViewModel]`（多显示器）
- `applicationDidFinishLaunching`：注册观察者、快捷键、创建 Notch Window
- Notch Window 是常驻 borderless panel，`applicationShouldTerminateAfterLastWindowClosed` 返回 `false`

### 3. Window 管理

- 继承链：`BoringNotchSkyLightWindow` → `BoringNotchWindow` → `NSPanel`
- borderless、`isFloatingPanel`、`level = .mainMenu + 3`、`canBecomeKey = false`、跨 Space 常驻
- 创建：`NSHostingView(rootView: ContentView().environmentObject(viewModel))`
- 尺寸：`openNotchSize = (640, 190)`，`windowSize = (640, 210)`（含 shadowPadding 20）

### 4. Notch UI 实现

`ContentView` 双状态驱动：
- **收起/展开**：`vm.notchState`（`.closed / .open`），spring 动画
- **展开态内容**：`BoringHeader`（顶部 tab 栏 + 右侧按钮）+ 下方 `switch coordinator.currentView`：
  ```swift
  switch coordinator.currentView {
  case .home:  NotchHomeView(albumArtNamespace: albumArtNamespace)
  case .shelf: ShelfView()
  }
  ```

### 5. 状态管理

| 手段 | 用途 | 例子 |
|------|------|------|
| `@Default(Key)` | 类型安全 UserDefaults（sindresorhus/Defaults） | 用户设置 |
| `@AppStorage` | 轻量 SwiftUI 偏好 | `firstLaunch` 等 |
| `ObservableObject` 单例 | 全局运行态 | `BoringViewCoordinator.shared`、`ShelfStateViewModel.shared` |
| `ObservableObject` 实例 | 每 Window 局部态 | `BoringViewModel`（通过 environmentObject 注入） |

### 6. Tab 系统

```swift
// TabSelectionView.swift
let tabs = [
    TabModel(label: "Home", icon: "house.fill", view: .home),
    TabModel(label: "Shelf", icon: "tray.fill", view: .shelf)
]
```
- `TabModel` / `let tabs` 仅在此文件内部定义和使用
- 点击 tab 设 `coordinator.currentView = tab.view`，`matchedGeometryEffect` 做选中高亮动画
- `BoringHeader` 里 tab 栏显示条件：`(!tvm.isEmpty || coordinator.alwaysShowTabs) && Defaults[.boringShelf]`

### 7. Shelf 模块范本（照搬对象）

- `ShelfStateViewModel.shared`：`@MainActor final class ObservableObject`
- `@Published private(set) var items`，`didSet` 时调 `ShelfPersistenceService.shared.save(items)` —— 改动即持久化
- 持久化：`~/Library/Application Support/boringNotch/Shelf/items.json` + JSONEncoder + atomic write

---

## 最终设计方案（第二阶段已完成，Soul Child 已确认）

### 设计决策

Soul Child 拍板：**完全按 boring.notch 官方现有开发逻辑改动**，不引入官方没有的概念（TabRegistry / ScratchpadModule 均不采用），ScratchpadStore 回归 `.shared` 单例（照搬 `ShelfStateViewModel.shared`）。

保留两项内部改进（不碰官方文件）：
- debounce 500ms 保存（照搬项目已有的 `Task.sleep + cancel` 模式）
- VS Code 顶部 tab UI（纯 ScratchpadView 内部布局）

### 持久化

- 路径：`~/Library/Application Support/boringNotch/Scratchpad/tabs.json`
- 方式：JSONEncoder + atomic write（与 Shelf 完全一致）
- 不用 UserDefaults / SQLite / CoreData

### 新增文件（4 个，放 `components/Scratchpad/`）

| 文件 | 职责 |
|------|------|
| `ScratchpadModel.swift` | `ScratchTab` 结构体（id/title/content/createdAt/updatedAt/isPinned），`Codable + Identifiable + Hashable` |
| `ScratchpadPersistence.swift` | JSON 文件读写，照搬 `ShelfPersistenceService` 结构 |
| `ScratchpadStore.swift` | `@MainActor final class ScratchpadStore: ObservableObject`，`.shared` 单例；`@Published private(set) var tabs` + `@Published var selectedTabID`；`updateContent` 内 debounce 500ms 调 persistence.save |
| `ScratchpadView.swift` | 顶部 tab 条 + TextEditor 编辑区；新建/删除/pin 按钮 |

### 修改官方文件（3 个，全是加行，不动已有逻辑）

#### ① `boringNotch/enums/generic.swift`（L27-30）

```swift
// 现在：
public enum NotchViews {
    case home
    case shelf
}

// 改成：
public enum NotchViews {
    case home
    case shelf
    case scratchpad   // ← 新增
}
```

#### ② `boringNotch/components/Tabs/TabSelectionView.swift`（L17-20）

```swift
// 现在：
let tabs = [
    TabModel(label: "Home", icon: "house.fill", view: .home),
    TabModel(label: "Shelf", icon: "tray.fill", view: .shelf)
]

// 改成：
let tabs = [
    TabModel(label: "Home", icon: "house.fill", view: .home),
    TabModel(label: "Shelf", icon: "tray.fill", view: .shelf),
    TabModel(label: "Scratchpad", icon: "note.text", view: .scratchpad)   // ← 新增
]
```

#### ③ `boringNotch/ContentView.swift`（L347-352）

```swift
// 现在：
switch coordinator.currentView {
case .home:
    NotchHomeView(albumArtNamespace: albumArtNamespace)
case .shelf:
    ShelfView()
}

// 改成：
switch coordinator.currentView {
case .home:
    NotchHomeView(albumArtNamespace: albumArtNamespace)
case .shelf:
    ShelfView()
case .scratchpad:            // ← 新增
    ScratchpadView()
}
```

### 不碰的文件

`boringNotchApp.swift`、`BoringHeader.swift`、`BoringViewModel.swift`、`Constants.swift`、`sizing/matters.swift`、Window 层、动画系统 —— 全部不动。

### 已知限制（第一版接受）

1. **tab 栏显示绑定 `boringShelf`**：`BoringHeader` 里 tab 栏只在 `Defaults[.boringShelf]` 开启时显示。`boringShelf` 默认为 true，正常使用没问题。若用户关掉 Shelf，Scratchpad tab 入口也会消失。未来需要独立时可再评估。
2. **高度约束 190px**：`openNotchSize = (640, 190)`，ScratchpadView 在此高度内布局，不动态改 notch 高度。文本编辑区偏紧凑，第一版接受。

### merge 冲突缓解策略

1. 新增文件独立目录 `components/Scratchpad/`，与 upstream 零路径交集
2. 三处已有修改全部行级追加，不改已有逻辑行
3. Swift `switch` 穷举检查：upstream 改 `NotchViews` 枚举时编译器强制处理新 case，把合并问题从运行时提到编译时
4. 不往 `Constants.swift` 的 `Defaults.Keys` 加配置项
5. ScratchpadStore 单例自包含持久化，不依赖也不污染 Music/Shelf 状态

---

## 第三阶段 — Scratchpad（已完成，功能可用）

**状态**：已实现并验证。核心功能（多 tab、增删、pin、重命名、自动保存、notch 内编辑、滚动、切换特效、双指左右滑切外部 tab）均可用。

### 已落地文件

新增（`components/Scratchpad/`）：
- `ScratchpadModel.swift` — `ScratchTab`（id/title/content/createdAt/updatedAt/isPinned）
- `ScratchpadPersistence.swift` — JSON 持久化，路径见下
- `ScratchpadStore.swift` — `.shared` 单例；`tabs` 为 `@Published`；**实时编辑内容存非 published 的 `contentCache` 字典**（打字不触发全 UI 重绘）；debounce 500ms 存盘
- `ScratchpadView.swift` — notch 内 UI：tab 条 / chip（重命名、内联关闭确认、高亮滑动）/ 编辑器 / 焦点桥接

官方文件行级修改：
- `enums/generic.swift`：`NotchViews` 加 `case scratchpad`
- `components/Tabs/TabSelectionView.swift`：tabs 数组加 Scratchpad 项
- `ContentView.swift`：switch 加 `case .scratchpad`
- `components/Notch/BoringNotchWindow.swift`、`BoringNotchSkyLightWindow.swift`：`canBecomeKey/Main` 改为 `currentView == .scratchpad` 时才 true（否则 notch 面板无法接收键盘输入）
- `extensions/PanGesture.swift`：`handleScroll` 中，**仅纵向手势**在鼠标落于 `NSScrollView`/`NSTextView` 时 `return`（避免编辑区上下滚动收起 notch）；横向手势不跳过（用于左右滑切 tab）
- `ContentView.swift`：新增 `.panGesture(.left/.right)` + `handleTabSwitchGesture`，双指左右滑切换外部 tab（左=下一个，右=上一个，边界停住，一次滑动只切一次，`tabSwitchArmed` 标志防连跳）

持久化路径（沙箱 app，实际在容器内）：
`~/Library/Containers/<bundle-id>/Data/Library/Application Support/boringNotch/Scratchpad/tabs.json`

### 关键实现要点与踩过的坑（重要）

1. **编辑器：每个 tab 一个独立实例，父层用 `.id(tabID)` 绑定。**
   曾用"单个 NSTextView 实例 + Combine 订阅 selectedTabID + 手动换文本"的方案，导致视图被创建多个实例、互相 flush 覆盖，**把有内容的 tab 清空**。教训：不要用一个编辑器伺候多个 tab 手动追踪当前 tab。现在每个 `ScratchTextEditor` 死绑一个 tabID，物理隔离，不可能串台。

2. **打字性能**：内容走 `contentCache`（非 published），打字不触发 `objectWillChange`。切 tab 卡顿的真凶其实是**双击重命名的手势/焦点开销**，非切换逻辑本身。

3. **输入焦点**：notch window 原本 `canBecomeKey = false`，改为仅 Scratchpad 激活时 true，并用 `WindowFocusRequester` 在出现时请求 key window。

4. **关闭确认**：不能用系统 `confirmationDialog`/`alert`——弹窗在面板外，鼠标移过去会离开 notch 悬停区导致面板收起、弹窗消失。改为**面板内内联确认**（tab 就地变"关闭? ✓ ✗"）。

5. **切换特效**：tab 条高亮块用 `matchedGeometryEffect` + `withAnimation` 平滑滑动（仿外部 tab）。编辑区因 `.id` remount，未加转场以免叠加重建开销。

6. **编辑区内左右滑切 tab**：编辑器的 scrollView 用 `HorizontalPassThroughScrollView`——横向为主的 scrollWheel 转发给 `nextResponder`（让切 tab 手势拿到真实横向 delta），纵向自己处理。不加这个的话，NSScrollView 会吞掉横向滚动，编辑区上左右滑切不了 tab。

### 待办 / 已知限制

- **"放大"已实现（第四阶段，见下）**：临时增高 notch 内容区，per-tab 生效，不持久化。
- **切 tab 跟手动画未做**：当前左右滑是"过阈值瞬间切换 + 淡入"，非 Mac 桌面那种内容随手指实时推移。跟手需接实时 translation 做双页联动位移 + 松手判定，会碰 `ContentView` tab 内容布局并可能与展开/收起动画叠加，暂缓。
- **界面文案写死中文**：未走 `Localizable.xcstrings`。build 时 Xcode 会自动把中文字面量提取进 `Localizable.xcstrings`（8 个 key），该文件由 Crowdin 管理，是**与 upstream 最可能的冲突点**。
- **pbxproj 为传统手动登记**：新增源文件需在 Xcode 手动 Add（Reference in place + Create groups + 仅勾 boringNotch target）。曾试同步分组方案，已还原。

### 环境注意
- SPM 依赖含 Lottie、Sparkle 等 binary target（GitHub Releases zip），走**系统代理**下载，终端 `HTTPS_PROXY` 等环境变量对其无效（需代理软件开系统代理/TUN）。

### 技术栈
- SwiftUI + AppKit（编辑器用 NSViewRepresentable 封装 NSTextView）
- ObservableObject
- JSON 文件持久化（照搬 ShelfPersistenceService）

---

## 第四阶段 — Scratchpad 临时放大（已完成，功能可用）

**需求**：编辑区在固定 190px 高度内太挤，想临时增高 notch 看更多内容。临时性、不持久化、per-tab。

**最终语义（重要）**：放大态**只与"是否停留在 Scratchpad tab"绑定**，与点击位置、面板 hover 开合完全无关。
- 放大后点刘海、点空白、鼠标移出让面板 hover 收起再划开 —— 全部保持放大。
- **只有主动切到别的 tab（Home/Shelf）才还原**默认高度；再切回 Scratchpad 是默认高度（不记忆）。

### 尺寸链路（关键认知）

notch 有两道高度天花板：① 物理 NSPanel 窗口尺寸；② `ContentView` 的 `.frame(maxHeight:)` 裁剪。二者原本都锁死在 `windowSize`（640×210）。真正可见的 notch 高度由 `vm.notchSize.height` + 黑色形状决定，窗口只是画布。

**收敛策略**：物理窗口**启动时一次性建到最大**（`maxWindowSize()`，按最高屏幕算），之后放大/还原**只改 `vm.notchSize.height`，永不再碰窗口层**。这把最危险的 window 改动收敛成"创建时一行"。透明区不可见、不挡点击。

放大目标高度 = 当前屏幕高 × `enlargedNotchHeightFraction`（0.6），运行时按屏幕算，多显示器自适应。

### 已落地文件

新增行（安全，无 upstream 交集）：
- `sizing/matters.swift`：加 `enlargedNotchHeightFraction`、`enlargedNotchHeight()`、`enlargedNotchSize()`、`maxWindowSize()` 纯函数
- `components/Scratchpad/ScratchpadStore.swift`：加 `@Published var isEnlarged`（**不写盘**，持久化逻辑没碰）
- `components/Scratchpad/ScratchpadView.swift`：tab 条右侧加放大/还原按钮（图标随态切换）；`onAppear` 重新套用放大态；`#Preview` 补 `.environmentObject(BoringViewModel())`（因视图新依赖 `@EnvironmentObject vm`）

官方文件行级修改：
- `models/BoringViewModel.swift`：新增 `applyScratchpadEnlarged(_:)`（带 spring 在默认/放大高间切）；`open()` 加一段——重开时若仍在 scratchpad 且 `isEnlarged` 则恢复放大高度（否则 hover 收起再开会缩回）
- `boringNotchApp.swift` L235：窗口创建高度 `windowSize` → `maxWindowSize()`（唯一的窗口层改动）
- `ContentView.swift` L217：`.frame(maxHeight: windowSize.height)` → `maxWindowSize().height`（放开裁剪，内容仍 `.top` 锚定，多出空间在黑框下方）
- `ContentView.swift`：`mainLayout` 加 `.onChange(of: coordinator.currentView)`——离开 `.scratchpad` 时才复位 `isEnlarged`

### 踩过的坑

1. **误诊点击收起**：一度以为"点空白/刘海会缩小"是点击穿透到 `doOpen()`，加了 `contentShape`+空 `onTapGesture` 补丁。**错了**——点击从不收起 notch，`doOpen()` 只负责打开。真凶是 `handleHover` 鼠标移出触发的 `vm.close()`（ContentView L570）。补丁已移除。
2. **还原时机**：最初放在 `ScratchpadView.onDisappear`，但面板 hover 收起时视图也 disappear，会误还原。改为监听 `coordinator.currentView`，只在真正离开 tab 时复位。

### 对 upstream merge 的影响

- 核心风险点是 `boringNotchApp.swift` 窗口创建行与 `ContentView` maxHeight 行——属官方 window/布局区域，upstream 若改动此处会冲突，但均为**单行替换**，冲突小且易辨。
- `open()` 内新增逻辑是加行，未删改原有行。
- 其余全在新增文件或新增 `onChange`，零交集。

---

## 开发流程约定

1. **每次只完成一个阶段**，不要一次生成全部代码
2. **每次修改必须说明**：修改文件、修改原因（若顺手评估了 upstream merge 影响可一并说，但不再是硬性要求）
3. **改动方式不设限**：新增文件、修改已有代码、重构均可，以把功能做对做好为准
4. **仍需避免**：高频刷新整个界面、破坏已有动画系统（这些是体验/正确性考量，与 merge 无关）
