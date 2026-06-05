# 桌面 Widget — 设计草案(已暂停)

**日期**: 2026-06-05
**状态**: ⏸️ 暂停 / 待决策。已完成 brainstorm,但因签名约束未定路线,**暂不实现**。
**目标**: 在 macOS 桌面上展示当前工作(今日任务 / 紧急项 / 看板进度 / 完成度)。

---

## ⚠️ 核心阻塞(决定了能不能做"真 Widget")

真正的 **WidgetKit 桌面 Widget,在"没有付费 Apple Developer 账号 + 自签名"前提下基本走不通**,死结如下:

1. Widget 是**强制沙盒**进程,只能通过 **App Group 共享容器**拿数据,没有其他口子。
2. App Group 容器路径为 `~/Library/Group Containers/<TeamID>.group…/`,**依赖带 Team 前缀的签名**才能解析。当前 `build.sh` 用 ad-hoc 自签名(`codesign -s -`,`CODE_SIGNING_ALLOWED=NO`),**无 Team → 容器解析不出 → Widget 读不到数据**。
3. 免费 Apple ID 个人 Team:macOS 上 App Group 能否在免费层启用本身不确定,且免费签名 app 有有效期问题,需定期从 Xcode 重新构建——对桌面常驻物很难受。

**当前事实**:用户**无付费开发者账号**,只想在**自己两台 Mac**上用。

---

## 已确认的设计决策(brainstorm 过程中逐项点头)

> 这些决策是在"假设走真 WidgetKit"的前提下定的。若改走"桌面常驻面板"路线(见下),数据传输/签名部分作废,但**展示内容与布局矩阵仍可复用**。

1. **目标结构**:新增 Widget Extension target(`WorkPanelWidgets`)+ 与主 app 共享 App Group。
2. **现有 SwiftData 库不迁移**,仍在 `~/Library/Application Support/WorkPanel/WorkPanel.store`。
3. **数据传输 = 方案 B(快照 JSON)**:app 在 `saveTracking()`(`Sync/Timestamped.swift`,全项目 27 处统一保存入口)之后,把精简快照写入 group 容器,再调 `WidgetCenter.reloadAllTimelines()`。
   - 刷新非瞬时:由前台用户操作触发的 reload 一般几秒内响应,系统有合并/预算机制;配 30 分钟低频 timeline 兜底(跨午夜"今日"翻篇)。
   - 注:方案 A(共享 store)在"新增任务多久反映到 Widget"上**并不更快**——Widget 永远只在 timeline 刷新时拉数据,不自动观察库。故选更轻、零迁移的 B。
4. **共享契约**:两端引用的纯 `Codable` 文件 `Shared/WidgetSnapshot.swift`,不依赖 SwiftData。筛选/排序在 app 端用现有 `TaskFilter` / `TodoTask.isUrgent` / `PlanStats` 算好,Widget 只负责画(避免逻辑两处漂移)。

   ```swift
   struct WidgetSnapshot: Codable {
       let generatedAt: Date
       let today: [TaskBrief]      // 今日计划(DayPlan committed),排序+截断 ~8
       let urgent: [TaskBrief]     // isUrgent || 高优先级,排序+截断 ~8
       let columns: [ColumnBrief]  // 看板各列计数
       let stats: StatsBrief
   }
   struct TaskBrief: Codable, Identifiable {
       let id: UUID                // 深链 workpanel://task/<id>
       let title: String
       let priority: Int           // 0/1/2 → 圆点颜色
       let deadline: Date?         // Widget 端算"剩 2h"/"逾期"
       let isCompleted: Bool
       let columnName: String?
   }
   struct ColumnBrief: Codable, Identifiable {
       let id: UUID; let name: String; let activeCount: Int
   }
   struct StatsBrief: Codable {
       let todayCommitted: Int; let todayCompleted: Int; let totalActive: Int
       // 完成率在 Widget 端算,避免除零
   }
   ```

5. **Widget 矩阵 = 7 格**(砍掉冗余/低价值的 5 格;因行组件共享,补格成本低,属低后悔):

   | Widget | 小 | 中 | 大 |
   |---|:-:|:-:|:-:|
   | **今日** | ✅ 完成 `3/7`+下一条 | ✅ 前 3 条 | ✅ 全部 ~8 + 进度条 |
   | **紧急** | ✅ 最急 1 条+角标 | ✅ 前 3 条(逾期标红) | ❌(与今日大重复) |
   | **看板** | ❌ | ✅ 三列+计数+进度 | ❌ |
   | **统计** | ✅ 完成率环形图 | ❌ | ❌ |

   - 共享原子组件:`TaskRow` / `ColumnChip` / `RingGauge`;各尺寸用 `switch family` 组装。
   - 视觉沿用 `Theme` 配色。**WidgetKit 不能用毛玻璃**(背景系统给),故 Widget 为扁平卡片 + Theme 配色,与 app 内 frosted 偏好有差异。

6. **交互 = 只读 + 深链**(不做交互式 AppIntent):
   - 注册 `workpanel://` scheme(主 app `CFBundleURLTypes`)。
   - 路由:`workpanel://board` → 看板;`workpanel://today` → 看板+今日透镜;`workpanel://task/<uuid>` → 定位高亮。
   - Widget 端整块 `widgetURL(...)`,大尺寸每行 `Link(destination:)`。
   - 主 app 端 `AppDelegate` 加 `application(_:open:)` / `NSAppleEventManager` getURL → 发对应通知(复用现有通知机制)。**目前 app 无任何 URL scheme/深链**,这是新增工作。

7. **签名/分发(前置风险块,依赖账号,非代码范围)**:
   - `build.sh` 需从 ad-hoc 改为 **Developer ID 真实签名**(app + 扩展都签)+ **公证 + staple**,否则别人下载过不了 Gatekeeper、App Group 也不可用。
   - 需**付费 Apple Developer Program 会员** + 在后台注册 App Group 标识符。

8. **测试策略**:
   - `WidgetSnapshot` 编解码 round-trip。
   - `SnapshotWriter`:内存 `ModelContainer` 注入确定性数据 → 生成快照 → 断言 today/urgent/columns/stats(参考 `BoardStoreTests`)。
   - 复用现有 `TaskFilter`/`PlanStats` 已有覆盖。
   - Widget 视图不自动化测试(扩展进程不可单测),Xcode 预览人工核对。

---

## 两条待决策路线(下次从这里继续)

### 路线 A — 桌面常驻面板(推荐,符合当前约束)
不用 WidgetKit。主 app 自己画一个无边框窗口,钉在**桌面图标层级**(普通窗口之下),显示今日/紧急/看板。

- ✅ **零签名改动**:沿用现有 ad-hoc 流程,两台 Mac 直接能跑,永久有效。
- ✅ **零 App Group / 零扩展**:直接读现有 SwiftData 库,**真·实时**。
- ✅ **复用现有基建**:`BoardPanelController`(非激活 overlay)、`PanelController`、`Theme` 毛玻璃卡片;视觉与 app 完全一致。
- ⚠️ 代价:"长得像 Widget"但非系统 Widget——不进系统 Widget 画廊;桌面被窗口铺满时会被盖住(可设"显示桌面时才见")。
- 复用上文:**展示内容(今日/紧急/看板/统计)+ 布局密度想法**可直接搬;**作废**快照传输、App Group、Widget Extension、签名改造、深链(同进程直接调用面板)。

### 路线 B — 真 WidgetKit(需用户先办付费账号)
用户办 $99/年 Apple Developer 账号后,按"已确认设计决策"全套实现(App Group + 快照 + Developer ID 签名 + 公证)。能上系统 Widget 画廊。

### 路线 C — 暂不做
当前用户选择:**先存计划,以后再说**。

---

## 下次继续的入口
1. 先定路线(A / B)。
2. 若 A:把"展示内容 + 7 格密度想法"重映射到桌面面板的单一大窗口布局,走 `writing-plans`。
3. 若 B:用户确认账号就绪后,按本文档"已确认设计决策"走 `writing-plans`。
