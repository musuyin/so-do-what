# 验证矩阵与完成证据

当前全部为**待实施/待验证**，本次没有运行应用测试或真机检查。

## 1. 自动验证矩阵

U=纯规则单测；DB=真实 SQLite 事务测试（宿主 FFI）；W=widget；D=Android 设备集成/人工。测试文件为未来建议路径，按职责可以合并，但不能遗漏验收语义。

| PRD | 层 | 建议测试文件（test/ 下，D 另放 integration_test/） | 断言重点 | 任务 |
| --- | --- | --- | --- | --- |
| A01 | DB,D | collections/collection_repository_test.dart | 创建+三项原子保存，关闭重开相同 ID，能抽 | T03–04 |
| A02 | U,DB,W | items/batch_import_test.dart | 空行/重复分类，NFC、超长阻止、预览过期不部分写 | T03 |
| A03 | U,DB,W | drawing/no_available_test.dart | 随机调用 0 次，记录/消耗不变，提供管理入口 | T04 |
| A04 | U,DB | drawing/allow_repeat_test.dart | 固定 RNG 连选 A，两 ID、两 ordinal | T04 |
| A05 | U,DB | drawing/avoid_previous_test.dart | A 后排除 A，重开数据库后相同；跨模式有效 | T05 |
| A06 | U,W | drawing/one_item_test.dart | 抽前警示、可成功，无拒抽/死循环 | T05 |
| A07 | U,DB,W | drawing/cycle_test.dart | 三项各一次；耗尽不自动新轮；用户开轮后才可抽 | T05 |
| A08 | DB | drawing/cycle_status_test.dart | 完成/跳过/待行动三转不改变消耗 | T05–06 |
| A09 | DB | drawing/cycle_edit_test.dart | 停用归档再恢复保持 consumed，新 ID 可抽，内容改名不重置 | T05 |
| A10 | DB | drawing/mode_switch_test.dart | C→A/B→C 原轮消耗不变，B 最近取其他模式成功记录 | T05 |
| A11 | DB,W,D | drawing/draw_idempotency_test.dart | 连点/重建/skip/completion 只一次 commit、一次 reveal | T04,T08 |
| A12 | DB | drawing/draw_failure_test.dart | 记录插入后消耗前抛错也全回滚；重试同 ID 同选择 | T04–05 |
| A13 | DB,D | restart_consistency_test.dart | commit 后 kill，重启记录与 consumption 同存 | T07 |
| A14 | DB,W | drawing/redraw_test.dart | 两条记录，原 status 保留，首次说明不改计数 | T04,T06 |
| A15 | U,DB,W | history/record_status_test.dart | 三状态全部 9 组合、同态无更新时间、撤销与失败 | T06 |
| A16 | DB | review/summary_test.dart | 3/11=27.3%，不是百分比平均 | T06 |
| A17 | U,W | review/empty_review_test.dart | count=0、rate=null、显示“—” | T06 |
| A18 | DB,W | history/snapshot_test.dart | 修改当前实体不改旧四快照，归档仍统计可改状态 | T06 |
| A19 | DB,D | settings/backup_round_trip_test.dart | 导出→清空→恢复逐实体语义相同，C/B 行为相同 | T09 |
| A20 | U,DB,D | settings/backup_validation_test.dart | 非法/新版本/取消/中途失败旧数据完全保持 | T09 |
| A21 | D | offline_flow_test.dart | 飞行模式冷启动全流程和系统文件保存 | T10–11 |
| A22 | DB,W | drawing/demo_isolation_test.dart | 演示/历史打开都无写入，正式全表摘要不变 | T07 |

不要对候选概率做易波动统计测试。验证固定候选集合、nextInt 上界和可枚举索引映射；候选无重复且每个索引恰好映射一个选项，说明均匀采样实现的结构正确。

## 2. 必补边界

1. 长度：1/上限/上限+1，中文/emoji/组合字符、空白、大小写保留；归档重复标题也拒绝。批量 500/501 行、1,000/1,001 项，100/101 集合。
2. 提交不明：commit 已成功但响应被注入异常 → 查询同 ID 返回原记录，不再调 RNG。查询也失败则不展示“未抽取”、不盲目增加新记录。
3. 当前轮：同集合 sequence 唯一；重复新轮请求不多开；零可用和已耗尽 UI 区别；重置旧 cycleId 的历史保留。
4. 状态：completedAt 重复完成不改变；离开 completed 清空；撤销完成恢复原时间；旧撤销不覆盖后续修改；DB 更新失败原 UI 与聚合保持。
5. 历史：同毫秒多条、时间回拨、跨本地午夜、切换时区、分页边界无遗漏/重复；集合同名筛选按 ID，快照搜索不匹配当前改名。
6. 备份：空库往返、旧轮全保留、归档停用、标题 NFC 冲突、重复 ID、错误外键/跨集合消费、未知枚举、非法状态时间、非法日期、当前轮 max sequence、损坏 JSON/UTF-8/过大文件。20,001 历史可恢复。损坏原数据库的修复路径需独立中断测试。
7. 事务注入位置：新记录后、消耗后、恢复删除旧数据后、恢复插入一半、清空删除中途。逐表比较回滚前后的语义快照，不能只断言返回异常。
8. 恢复竞争：有旧页面 Future 未结束、旧状态 snackbar、正在抽取时申请恢复，写协调器和 generation 保证旧操作不能落进新数据。
9. 设置：每个开关重启后保留；清空恢复默认；系统 reduceMotion=true 时 App=false 仍减动；声音关闭、后台时调用次数为零。

## 3. 视觉检查表

| 场景 | 操作/观测 | 证据 |
| --- | --- | --- |
| 全页面基线 | S01–S08，浅/深，360/390/430 宽 | 实际运行截图，注明尺寸和主题 |
| 大屏 | ≥600，集合两列、表单居中，不机械拉宽 | 截图 |
| 长内容 | 40 字集合名、100 字标题、300 字备注、120 字标准 | 完整可读，无 RenderFlex overflow |
| 200% 字号 | 主要按钮能滚动访问、chips 自动换行 | 截图与操作记录 |
| 中文键盘 | 新建/编辑/导入，保存和错误可见 | 截图 |
| 空/错/加载 | 空库、无搜索匹配、存储失败、分页失败、慢提交 | 四态独立截图 |
| 抽样特殊态 | B 单项、C 耗尽、Y=0、归档历史 | 提示和按钮行为录屏 |
| 完整扭蛋 | 正常/skip/instant/减动/后台返回 | 录屏，同一 recordId 由测试验证 |
| 可访问性 | TalkBack 顺序、结果只播一次、48px 点击、对比度 | 实机记录+程序化对比度表 |
| 数据管理 | 系统导出/取消/覆盖预览/恢复后刷新 | 设备录屏，不包含个人数据 |

别用截图像素快照锁死所有页面；必要时 golden 只保护稳定的绘图/主题组件。真实交互验收不可由 golden 替代。

## 4. 离线与真机脚本

1. 在设备开启飞行模式，强制停止后冷启动；使用虚构集合“周末小事”，输入三个选项。
2. C 模式抽一次，动画期间切后台，回前台确认同结果；再杀进程重开，在历史找到结果，轮次剩余正确。
3. 标记完成，返回回顾核对次数，再撤回/跳过确认口径。
4. 导出到设备本地 Documents；清空；恢复并逐项检查设置、顺序、状态、B 上次结果、C 消耗。
5. 损坏副本导入与取消确认，检查当前数据未改。
6. 音效和触感各开/关验证，系统减动与 App 减动组合验证。

Android 系统文件选择器可能列出用户配置的云盘；只测试本地位置，无需登录云服务。App 不主动上传，不能因为系统存在云盘选项宣称应用有云同步。

## 5. 容量与性能

夹具全部虚构、由确定性生成器构造，不提交个人备份。至少两组：日常基线 100 集合、一个满 1,000 项、20,000 历史；最大实体压力 100×1,000 项加 20,000 长文本历史，确认备份资源边界。附加 20,001 历史验证非硬限额。

建议工程目标（计划补充，不是 PRD 新承诺）：profile 真机热启动首页查询 <500ms、每页历史查询 <200ms、20k 聚合 <300ms；交互立即进入 busy，超过 300ms 应有明确等待反馈。记录中位数/较慢样本、设备和构建模式，达不到先分析 I/O/索引/重建，不能仅改阈值宣称通过。

动画查看 profile 帧时间与肉眼连续性，按设备刷新率预算报告超时帧；不能只给一个脱离设备的“60fps”。备份大数据解析必要时 isolate/分块批量插入，但所有正式恢复写入仍一个事务，禁止为提速部分提交。

## 6. 命令与报告模板

实施期完成必要检查：

```text
flutter doctor -v
flutter pub get
dart format lib test integration_test
flutter analyze
flutter test
flutter test integration_test -d <实际设备ID>
flutter build apk --debug
```

不存在 integration_test 时先不要把不存在目录传给 format；应在实施设备流后补齐。性能检查用 profile 实际构建，debug 包仅安装和功能验收。工具不可用写原始阻塞，不编造命令输出。

未来 `docs/validation-report.md` 至少包含：

- 日期、revision（尚未提交写工作区状态）、Flutter/Dart/Android/设备/模式。
- A01–A22 各项：通过/失败/未验证、对应测试或人工证据。
- 页面截图和动画录屏的真实路径。
- 容量规模、性能测量、备份往返、故障回滚结果。
- 已知限制与阻塞，区分“实现了”与“已经在设备验证”。

无关键数据丢失问题、A 项真实通过、完整视觉检查和 Android 验证有证据，才可宣称 P0 完成。所有者未决定开源许可时只能称本地开发交付，不称已公开发布。
