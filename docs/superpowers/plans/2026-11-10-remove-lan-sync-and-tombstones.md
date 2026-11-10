# 移除 LAN 自动同步与删除墓碑 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 移除 LAN 多设备自动同步与 Tombstone 删除传播机制,导入/导出回归纯全量合并(newest-wins,删除不传播)。

**Architecture:** 纯删除 + 语义回退。LAN 模块(`Sync/LAN/`)、其 App/设置接线、AppSettings 键整体移除;Tombstone 模型、Store 删除路径的墓碑创建、`SyncDocument`/`SyncService` 的墓碑编解码与应用一并删除。保留导入/导出与 `Timestamped`/`saveTracking`。

**Tech Stack:** Swift 6 / SwiftUI / SwiftData / Swift Testing;工程为 PBXFileSystemSynchronized(增删文件直接操作磁盘,无需改 pbxproj)。

**Spec:** [docs/superpowers/specs/2026-11-10-remove-lan-sync-and-tombstones-design.md](../specs/2026-11-10-remove-lan-sync-and-tombstones-design.md)

## Global Constraints

- Xcode 工程为同步文件夹组:`git rm` 源文件即可,禁止手改 project.pbxproj
- `schemaVersion` 维持 1;旧导出文件(含 `tombstones` 键)必须仍可导入(JSONDecoder 忽略未知键)
- 导入语义:按 ID 合并 + 最新者胜;**文件中不存在的本地记录一律保留,不做任何删除**
- `Timestamped` / `saveTracking()` / `SyncSettings` / 导入导出 UI 保持不动
- 测试命令统一 `rtk test`(只显示失败);单测预期失败/通过看输出中对应测试名
- Conventional commits(develop 分支)

## Review Focus

1. **旧导出文件兼容**:带 `tombstones` 键的 JSON 必须解码成功且忽略该键 → Task 3 `documentWithLegacyTombstonesKeyDecodesAndIgnores`
2. **删除不误伤**:导入不含某本地任务的文件,该任务必须保留 → Task 3 `mergeDoesNotDeleteLocalTaskAbsentFromFile`
3. **删列迁移**:删除列时列内任务仍迁到其它列 → Task 2 `deleteRemovesColumnMovesTasks`
4. **最后一列保护**:仅剩一列时删除是 no-op → Task 2 `deleteLastColumnIsNoop`
5. **新导出干净**:导出 JSON 不再含 `tombstones` 键 → Task 3 `exportOmitsTombstonesKey`

---

### Task 1: 移除 LAN 模块、App 接线与设置区块

**Files:**
- Delete: `WorkPanel/Sync/LAN/SyncClient.swift`、`SyncCoordinator.swift`、`SyncPeerBrowser.swift`、`SyncPeerServer.swift`
- Delete: `WorkPanelTests/SyncPeerBrowserTests.swift`、`SyncPeerServerTests.swift`
- Modify: `WorkPanel/WorkPanelApp.swift`(行 69 `syncCoordinator` 属性;行 88-90 `.lanSyncSettingsChanged` 观察者;行 152-167 `startOrStopSync()`/`restartSync()`)
- Modify: `WorkPanel/MCP/MCPServer.swift:9-11`(删 `lanSyncSettingsChanged` 定义,保留 `mcpSettingsChanged`)
- Modify: `WorkPanel/Store/AppSettings.swift`(删 Key 中 6 个:`lanSyncEnabled`/`lanSyncPort`/`lanSyncPairingCode`/`lanSyncIntervalSeconds`/`syncInstanceID`/`lanSyncDeviceName`;删对应访问器与 `registerDefaults` 里 4 个 LAN 条目)
- Modify: `WorkPanel/UI/Settings/SettingsView.swift`(行 21-23 两个 `@AppStorage` 与 `lanStatus` `@State`;`SettingsTab` 枚举删 `lan` case 及 label;`content(for:)` 删 `case .lan`;删 `lanSection` 整个计算属性约行 464-510)

**Interfaces:**
- Consumes: 无
- Produces: 无(纯移除;`LANSyncStatus` 随 LAN 目录消失,SettingsView 是其唯一 UI 消费方)

- [ ] **Step 1: 删除 LAN 源文件与测试文件**

```bash
git rm WorkPanel/Sync/LAN/SyncClient.swift WorkPanel/Sync/LAN/SyncCoordinator.swift \
       WorkPanel/Sync/LAN/SyncPeerBrowser.swift WorkPanel/Sync/LAN/SyncPeerServer.swift \
       WorkPanelTests/SyncPeerBrowserTests.swift WorkPanelTests/SyncPeerServerTests.swift
```

- [ ] **Step 2: 清理 WorkPanelApp.swift、MCPServer.swift、AppSettings.swift、SettingsView.swift 的全部引用**

按 Files 列表逐处删除。`AppSettings.Key` 中 LAN 键删除后,任何残留引用都会编译报错——以编译器为清单清零。

- [ ] **Step 3: 编译验证无残留引用**

Run: `xcodebuild build -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: 跑全量测试**

Run: `rtk test`
Expected: 全绿(LAN 两个测试文件已删,其余不受影响)

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(sync): remove LAN auto-sync module and settings UI"
```

---

### Task 2: Store 删除路径停止创建墓碑

**Files:**
- Modify: `WorkPanel/Store/TodoStore.swift:59-63`(`delete` 里 `context.insert(Tombstone(...))` 行)
- Modify: `WorkPanel/Store/BoardStore.swift:59-69`(`delete` 里同款行)
- Test: `WorkPanelTests/TodoStoreTests.swift:105-115`、`WorkPanelTests/BoardStoreTests.swift:182-204`、`WorkPanelTests/WorkDocApplierTests.swift:68-80`

**Interfaces:**
- Consumes: `Tombstone` 模型仍存在(本任务只停写,不删类型——Task 3 才删)
- Produces: `TodoStore.delete(_ task:now:)` / `BoardStore.delete(_ column:now:)` 签名不变,行为变为纯 `context.delete`

- [ ] **Step 1: 改写测试 pin 新行为(墓碑不再产生)**

- `TodoStoreTests.deleteCreatesTaskTombstone` → 改名 `deleteRemovesTask`:断言任务 fetch 为空,**且** `fetch(FetchDescriptor<Tombstone>()).isEmpty`
- `BoardStoreTests.deleteCreatesColumnTombstone` → 改名 `deleteRemovesColumnMovesTasks`:断言列删除、列内任务 `columnID` 已迁到目标列、Tombstone fetch 为空
- `BoardStoreTests.deleteLastColumnCreatesNoTombstone` → 改名 `deleteLastColumnIsNoop`:断言列仍在、任务不动,去掉 Tombstone fetch(改由前两个测试覆盖「不产生墓碑」)
- `WorkDocApplierTests.deleteRemovesTaskAndLeavesTombstone` → 改名 `deleteRemovesTask`:断言任务为空 + Tombstone fetch 为空

- [ ] **Step 2: 跑测试确认失败**

Run: `rtk test`
Expected: FAIL——上述 4 个测试报「Tombstone fetch 非空」

- [ ] **Step 3: 实现删除墓碑创建**

`TodoStore.delete` 与 `BoardStore.delete` 各删去 `context.insert(Tombstone(...))` 一行(`let id = ...` 局部变量若无它用一并删)。

- [ ] **Step 4: 跑测试确认通过**

Run: `rtk test`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(sync): stop creating deletion tombstones"
```

---

### Task 3: 移除 Tombstone 模型与同步编解码

**Files:**
- Delete: `WorkPanel/Models/Tombstone.swift`
- Modify: `WorkPanel/WorkPanelApp.swift:19`(Schema 数组删 `Tombstone.self`)
- Modify: `WorkPanel/Sync/SyncDocument.swift`(删 `SyncTombstoneDTO` 整个 struct 约 64-74 行、`SyncDocument.tombstones` 字段约 85 行)
- Modify: `WorkPanel/Sync/SyncService.swift`(exportData 删 tombstones 抓取与编码;merge 删阶段一墓碑合并/按墓碑删除、列与任务循环里的墓碑抑制及「复活撤销墓碑」块、`SyncReport` 删 `tasksDeleted`/`columnsDeleted`/`totalDeleted`)
- Test: `WorkPanelTests/SyncDocumentTests.swift`、`SyncServiceMergeTests.swift`、`SyncServiceExportTests.swift`、`BoardStoreTests.swift`、`TodoStoreTests.swift`、`WorkDocApplierTests.swift`(各 container 的 `Schema`/`ModelContainer(for:)` 列表删 `Tombstone.self`;删 tombstone 专属用例)

**Interfaces:**
- Consumes: Task 2 后无任何生产代码再写墓碑;本任务把类型与消费一并移除
- Produces: `SyncReport` 不再有 `tasksDeleted`/`columnsDeleted`/`totalDeleted`(若 `SettingsView` 导入预览引用了它们,同步删除该 UI 引用——实现时 grep `totalDeleted` 定位)

- [ ] **Step 1: 先写兼容性/语义测试**

- `SyncServiceMergeTests` 新增 `mergeDoesNotDeleteLocalTaskAbsentFromFile`:本地插入任务 A;构造只含一条无关列的 doc 合并;断言任务 A 仍在、`report.tasksInserted == 0`
- `SyncServiceExportTests.exportIncludesTombstones` → 改名 `exportOmitsTombstonesKey`:插入任务后 `exportData`,断言编码字符串不含 `"tombstones"`
- `SyncDocumentTests` 删 `tombstoneDTORoundTrips`/`documentMissingTombstonesDecodesAsNil`/`tombstoneDTOUnknownKindFallsBackToTask`,新增 `documentWithLegacyTombstonesKeyDecodesAndIgnores`:手写 JSON(含 `schemaVersion:1`、一条 task、多余 `"tombstones": [...]` 键),`SyncDocument.decoder` 解码成功且 `doc.tasks.count == 1`
- 删 `SyncServiceMergeTests` 的 `tombstoneDeletesLocalTask`/`tombstoneSuppressesReinsertFromThirdDoc`/`newerEditSupersedesTombstone`;`docWith` 辅助函数删 `tombstones` 参数

- [ ] **Step 2: 跑测试确认失败**

Run: `rtk test`
Expected: FAIL/编译错(`exportOmitsTombstonesKey` 仍产出 tombstones 键;`docWith` 签名不匹配等)

- [ ] **Step 3: 移除类型与全部残留引用**

按 Files 清单删代码。测试文件里 `ModelContainer(for: ... Tombstone.self ...)` 全部去掉该项。以编译器为清单清零残留。

- [ ] **Step 4: 跑测试确认通过**

Run: `rtk test`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(sync): remove tombstone model and deletion propagation"
```

---

### Task 4: 全量验证与冒烟

**Files:** 无新改动(验证任务)

- [ ] **Step 1: 全量测试 + 构建**

Run: `rtk test` 与 `xcodebuild build -project WorkPanel.xcodeproj -scheme WorkPanel -destination 'platform=macOS' 2>&1 | tail -3`
Expected: 全绿 + BUILD SUCCEEDED

- [ ] **Step 2: 人工冒烟清单(留给用户)**

启动 App:设置面板无「局域网同步」tab;导入/导出按钮可用;删除一个任务后导出,文件中无 `tombstones` 字段。存量库首次启动由 SwiftData 迁移丢弃墓碑表,属预期。
