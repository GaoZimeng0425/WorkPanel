# 移除 LAN 自动同步与删除墓碑设计

日期:2026-11-10

## 目标 / 动机

用户单机使用 WorkPanel,不使用多设备同步。LAN 自动同步(Bonjour 发现 + 对端互推)是纯负担;为其服务的删除墓碑(Tombstone)机制一并移除——**导入/导出回归纯全量同步语义:文件里有就按最新者胜合并,没有的本地保留,删除不传播**。手动导入/导出(唯一的备份与换机迁移路径)保留。

## 语义变化(明确接受的后果)

- 导入/导出**不再传播删除**。恢复一份较早的备份会把当时存在、后来删掉的任务重新导入(复活)——与 2026-06-05 导入/导出设计的原始语义一致,删除是每台机器自己的事。
- 旧导出文件(含 `tombstones` 数组)仍可导入:`JSONDecoder` 忽略未知键,`schemaVersion` 维持 1。

## 删除清单

**LAN 同步:**
- `WorkPanel/Sync/LAN/` 整目录:`SyncClient.swift`、`SyncCoordinator.swift`、`SyncPeerBrowser.swift`、`SyncPeerServer.swift`
- `WorkPanelApp.swift`:`syncCoordinator` 属性、`startOrStopSync()`/`restartSync()`、`.lanSyncSettingsChanged` 通知观察者及调用点
- `MCP/MCPServer.swift`:`.lanSyncSettingsChanged` 通知名定义
- `UI/Settings/SettingsView.swift`:LAN 同步区块 UI(开关、配对码、端口、间隔、设备名)及对应 `@AppStorage` 属性
- `Store/AppSettings.swift`:6 个键及访问器、`registerDefaults` 条目——`lanSyncEnabled`、`lanSyncPort`、`lanSyncPairingCode`、`lanSyncIntervalSeconds`、`syncInstanceID`、`lanSyncDeviceName`
- `WorkPanelTests/`:`SyncPeerBrowserTests.swift`、`SyncPeerServerTests.swift`

**Tombstone:**
- `Models/Tombstone.swift`(`TombstoneKind` 一并移除)
- `TodoStore` / `BoardStore` 删除路径里的墓碑创建代码(删除回归直接 `context.delete`)
- `SyncDocument`:`SyncTombstoneDTO`、导出时的 tombstones 编码、`SyncService.merge` 里的墓碑应用与相应 report 字段
- 测试:`SyncDocumentTests` / `SyncServiceMergeTests` 中的 tombstone 用例;`BoardStoreTests` / `TodoStoreTests` / `WorkDocApplierTests` 里断言墓碑创建的部分(精确行号在计划阶段定位)

## 保留(明确不动)

- `SyncService` / `SyncDocument`(任务/列/日计划部分)/ `SyncSettings`:导入/导出的实现
- `Timestamped` / `saveTracking`:newest-wins 的时间戳基础
- 设置面板的导入/导出 UI 与相关测试

## 取舍(我的决定)

- **UserDefaults 残留值不清**:键定义与读取方全删后,plist 里的旧值无人消费,不写清理代码
- **存量墓碑数据不迁不清**:`Tombstone` 模型从 schema 移除后,旧库里的表随 SwiftData 迁移废弃,无需手动处理
- **无权限/声明清理**:已核实工程里没有 `NSLocalNetworkUsageDescription`、Bonjour services、entitlements 等与 LAN 相关的声明

## 验证

- `rtk test` 全绿(删除清单中的测试文件/用例移除后无编译残留)
- 设置面板无 LAN 区块,导入/导出可用;导入旧格式文件(带 tombstones 键)不报错
- 删除任务/列后导出的文件不含 `tombstones` 字段
- App 启动不创建 `SyncCoordinator`,无 Bonjour 网络活动
