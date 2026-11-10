# Jira 状态 → 看板列映射(按项目)设计

日期:2026-11-10(追加于 Jira 拉取同步)

## 意图

用户在两个 Jira 项目(AAA、OC)有工作,各自工作流状态不同。希望拉取的任务按「项目 × 状态」落到对应看板列,而不是全部堆在第一列;Jira 里状态变化后,本地任务跟着挪列。

## 设计(对话已拍板)

- **映射表**:`项目 → (状态名 → 看板列名)`,存 UserDefaults JSON(`jiraColumnMapping`),每机配置、不进导出白名单
- **状态发现**:每次拉取后记录见过的 `(projectKey, statusName)` 对(`jiraDiscoveredStatuses`,JSON),设置面板据此渲染映射行;下次拉取整体替换
- **projectKey**:从 issue key 前缀解析(`OC-1597 → OC`),客户端侧解析,不加 API 字段
- **列解析**:按列名匹配本地 `BoardColumn`;**未映射 / 列名不存在 → columnID = nil**(显示时回退第一列,不写死列 ID,避免加列/改名列后错位)
- **应用时机**:插入时与远端字段更新时(本地改过则不动——本地优先规则统一覆盖;用户手动拖过的卡不会被拉取搬走)
- **JiraIssue 增字段**:`statusName`(状态名,解析自 `fields.status.name`)、`projectKey`
- **设置 UI**:Jira 区块加「状态→列映射」:按项目分组,每状态一个列名 Picker(含「不映射」);拉取后刷新;未拉取过显示占位提示

## 验证

- 单测:projectKey/statusName 解析;插入落列(含未映射→nil、列不存在→nil);未改本地任务随状态变化挪列;本地拖过的卡不挪;发现状态记录
- 全量单元包 + 构建 + 真机拉取回归

## 备注

小改动,按 executing-plans(Native)直接实现,不再单开计划文档。
