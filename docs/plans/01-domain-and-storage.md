# 业务与数据合同

本文件给出实施默认决定，不是已存在的代码。PRD 约束优先。

## 1. 架构与文件职责

```text
lib/
  main.dart                         组合依赖和启动，不含业务规则
  app/app.dart                      MaterialApp、主题、启动失败页
  app/app_shell.dart                三个底部入口
  app/dependencies.dart             显式构造与注入
  core/domain/{clock,id_generator,random_source,app_failure,text_rules}.dart
  core/data/{app_database,schema,migrations,write_coordinator}.dart
  core/ui/{app_theme,design_tokens,empty_state,error_panel,confirm_sheet}.dart
  features/collections/{domain,data,presentation}/
  features/items/{domain,data,presentation}/
  features/drawing/{domain,data,presentation}/
  features/history/{domain,data,presentation}/
  features/review/{domain,data,presentation}/
  features/settings/{domain,data,presentation}/
  features/settings/data/{backup_codec,backup_validator,backup_repository}.dart
assets/{artwork,sounds}/
test/{core,collections,items,drawing,history,review,settings,widgets}/
integration_test/
```

domain：纯 Dart 实体、规则、接口，不 import Flutter/sqflite。data：SQL 与平台适配。presentation：控制器、页面、组件、动画。控制器调用用例，不执行 SQL、不自己随机。跨功能通过接口：drawing 读取集合和选项，history 更改记录状态，review 只查询聚合。不要每个字段都另造仓库、事件总线或通用框架。

页面控制器持有不可变状态，ChangeNotifier 仅为通知；销毁后不通知。一个 app 级 WriteCoordinator 串行化写命令；数据库事务是最终一致性边界。恢复/清空期间独占写入口且锁住导航中的数据操作。页面禁用只是体验约束，不能替代底层校验。

## 2. 依赖选择和核验

使用实施当日彼此兼容的稳定版本并提交 lockfile；不复制本计划检索时的 latest 版本号或示例 API。T00 记录实际 Flutter/Dart/JDK/Gradle/Android SDK 与插件版本和许可。下列选择已查官方包页能力，但不等于本地集成验证：

| 用途 | 选择 | 要求 |
| --- | --- | --- |
| SQLite | sqflite + path | 事务内只用 txn；不得在 txn 回调调用外层 db；异常向外抛使整体回滚 |
| 宿主数据库测试 | sqflite_common_ffi（开发依赖） | 注入 database factory，用真实 SQL 验证，不仅用内存 Map 假实现 |
| 文件选择/保存 | file_picker | Android 系统文档界面；适配器按锁定版本实现，不假设返回值是普通文件路径 |
| NFC | unorm_dart | 仅用于文本规范化；检查许可和 Unicode 兼容性，验证组合字符 |
| 可见字符 | characters | 字素簇计数，作为直接依赖声明；不用 String.length |
| 音效 | audioplayers | 只播放内置 AssetSource，生命周期显式停止和释放 |
| ID | uuid | 稳定随机 ID，由接口注入以便测试 |
| 其余 | Flutter SDK | Navigator、ChangeNotifier、HapticFeedback、CustomPainter、动画、图标 |

sqflite 提供事务及回滚与宿主测试适配，参考 [包文档](https://pub.dev/packages/sqflite)。文件 API 的平台与主版本存在差异，参考 [FilePicker API](https://pub.dev/documentation/file_picker/latest/file_picker/FilePicker-class.html) 及 [变更记录](https://pub.dev/packages/file_picker/changelog)。NFC 入口参考 [unorm_dart nfc](https://pub.dev/documentation/unorm_dart/latest/unorm_dart/nfc.html)。本地声音用 [audioplayers](https://pub.dev/packages/audioplayers)，其 [许可](https://pub.dev/packages/audioplayers/license) 为 MIT；项目自身许可证仍待所有者选择。其他包及传递依赖许可在锁定后逐项登记，不能凭这些链接宣称全部已核验。

不加入网络、账号、分析、广告、远程字体、图片服务或付费依赖。发布 manifest 不要求联网；检查插件合并后的权限。开发调试所需权限单独核对。Android 系统自动云备份/设备迁移默认关闭并核对目标 SDK 的规则配置，防止违背主动本地备份预期。

## 3. Schema v1

字段名称 Dart camelCase，SQL snake_case；以下类型 TEXT/INTEGER 表示 SQLite。所有业务 ID TEXT PRIMARY KEY；布尔 INTEGER CHECK 0/1；枚举存稳定字符串。createdAt/updatedAt/drawnAt/completedAt 等存 UTC epoch milliseconds。可选内容用空字符串，时间和 cycleId 可 NULL，不混用 null 与空串。

| 表 | 字段与约束 |
| --- | --- |
| collections | PRD 全字段；name/description/criterion 非 NULL；sort_order 非负；draw_mode=allowRepeat/avoidPrevious/cycle；presentation_style=gacha/instant |
| items | PRD 全字段 + title_key=NFC(trim(title))；UNIQUE(collection_id,title_key) 用二进制比较；UNIQUE(id,collection_id) 供组合外键 |
| cycles | id,collection_id,sequence,created_at；UNIQUE(collection_id,sequence)，sequence≥1；UNIQUE(id,collection_id) |
| cycle_consumptions | cycle_id,collection_id,item_id；PRIMARY KEY(cycle_id,item_id)；组合 FK(cycle_id,collection_id)→cycles；FK(item_id,collection_id)→items |
| draw_records | PRD 全字段 + draw_ordinal INTEGER UNIQUE NOT NULL + revision INTEGER NOT NULL DEFAULT 0；id 为幂等键；组合 FK 保证 item/cycle 与 collection 一致；status 限三值 |
| settings | 固定 id=1，PRD 四字段 + redraw_hint_seen 布尔（只用于首次提示，备份时同样保存） |

开启外键，禁用级联删除；仅整体恢复/清空按依赖顺序删除。集合和选项不永久删除。记录 CHECK：completed 当且仅当 completed_at 非空；mode=cycle 当且仅当 cycle_id 非空。记录的快照字段一旦创建不能被编辑命令更新。

drawOrdinal 是**提交顺序**，事务内从 MAX+1 产生；用于同毫秒破平局，并以它判断最近一次成功抽取（系统时钟倒拨也不影响模式 B）。历史按 drawn_at DESC,draw_ordinal DESC；时间仍遵循实际保存时间。恢复时按 drawRecords 数组从旧到新顺序重建 ordinal；导出同样按 ordinal ASC，避免增加备份必需字段。序列化合同须固定这一点。

索引至少：items(collection_id,sort_order,id)、draw_records(collection_id,draw_ordinal DESC)、draw_records(drawn_at DESC,draw_ordinal DESC)、draw_records(collection_id,status,drawn_at DESC,draw_ordinal DESC)、draw_records(status,drawn_at DESC,draw_ordinal DESC)、cycles(collection_id,sequence DESC)。不为 20,000 条历史引入全文索引或独立统计缓存。

数据库版本独立于 appVersion。升级在事务内迁移；较新版本打开拒绝写入，显示“这份数据需要更新版本的应用”。数据库损坏展示重试/从备份恢复，不自动初始化空库覆盖。新库首次创建才写默认设置。

## 4. 输入、排序与管理合同

- `TextRules`：先 trim，再 NFC；使用字素簇验证长度。只含空白的必填值拒绝。标题规范化后保存，并单独存 titleKey。组合变音字相等，大小写不折叠。控制字符不作为可见内容通过验证；单行字段拒绝换行，备注/描述允许正常换行。
- 导入按 CRLF/LF/CR 分行，保留行号。500 行限制包括空行，末尾单个换行不额外计一个空行。分类 new/blank/duplicateExisting/duplicateBatch/invalidLength，展示计数和原行。归档重复标明可恢复；不自动创建第二 ID。
- 有 invalid 行禁用保存，返回修改；重复和空行可跳过。有效新项为零时不提交。确认时在事务内再次校验唯一性/容量；若预览过期，重新生成预览，不部分导入。创建集合与初始批量项也在同一事务。
- capacity：100 集合、1,000 项包括归档停用。新增位置 max(sortOrder)+1；编辑不变。重排输入必须为所属范围所有 ID 的排列；将整个范围写 0..n-1，事务提交。普通列表隐藏归档，但调整顺序页面展示完整范围并标归档，搜索和过滤期间不能拖动。
- collection archive 不改 items 的 enabled/archivedAt；恢复亦然。item archive 不改 enabled；停用项归档再恢复仍停用。允许归档集合查看选项/历史，但集合内新增编辑/再抽入口禁用，恢复后再改；旧记录状态仍可修改。
- 样式/规则更新在事务里验证集合可编辑。首次选择 C 同事务创建第一轮；如果备份合法但没有当前轮且模式 C，用进入 C 的初始化命令创建，不在纯读查询中写数据库。

## 5. 抽取用例与状态机

接口语义（命名可以遵循此稿，不能省略合同）：

| 接口 | 输入/输出 |
| --- | --- |
| RandomSource.nextInt | exclusiveUpperBound > 0；输出 [0,n)，生产 Random.secure()，测试固定索引序列 |
| CandidatePolicy.resolve | 当前可用项、mode、lastItemId、consumedIds → eligible + emptyReason + oneItemWarning |
| DrawService.draw | requestId,collectionId → 已持久化 DrawRecord；重复 ID 返回原记录 |
| DrawService.reconcile | requestId → found / definitelyAbsent / unavailable，后两者不能混淆 |
| CycleService.startNext | collectionId,expectedCycleId,confirmed → 新轮；重复点击发现 expected 已变则返回当前轮 |
| RecordService.setStatus | recordId,targetStatus → 提交后记录；同状态不改 completedAt/updatedAt |
| ReviewRepository.summary | 可选 collectionId → total/completed/pending/skipped，率由 UI 格式化 |
| BackupRepository | exportSnapshot / validate / restore(validatedToken)；验证令牌绑定已验证的不可变内容 |

纯候选规则：A=available；B=available 长度≤1 时原样，否则移除最近成功 itemId；C=available 减 consumed。先判断 available 为空再判断 C 耗尽，避免 Y=0 时误导开启新轮。候选按稳定 ID 排序以便可重复测试，但无权重。

一次 draw 的执行顺序：

1. 控制器同步设置 busy，并创建本次 requestId；连续点击直接忽略，重建不生成新 ID。
2. 获得写协调器锁，事务第一步按 requestId 查记录，存在则直接返回；若它属于另一集合则视为调用错误，不偷偷复用。
3. 读最新集合、模式、有效项、当前轮、最近记录；归档/空池/耗尽返回类型明确的失败，不调用随机源。
4. 根据当前状态构建候选，随机只调用一次，固定 selection 与快照、时间。保留此次 PreparedDraw 在控制器/用例会话中，直到明确结束请求。
5. 分配 drawOrdinal，INSERT DrawRecord；C 同一事务 INSERT consumption。任何失败必须抛出，整个回滚，禁止 continueOnError。
6. commit 成功才把记录交给 presentation；此时进入动画或直接结果。动画没有数据库写权限。
7. commit 结果不明：保持本次 requestId，先 reconcile；查询 unavailable 时显示“暂时无法确认是否保存，请重试”，禁新抽和改池，不当作失败。found 显示原记录；明确 absent 后才允许重试该 PreparedDraw。
8. 明确回滚后的“重试”复用 requestId 和 selection，并在事务内重新核验候选/快照前提；发生规则/候选/轮次变化则拒绝该请求，提示“集合已变化，请重新抽取”，由新的点击创建新请求。用户离开可丢弃明确未提交的请求。进程死亡不持久化 PreparedDraw，也不自动重试，已提交记录由历史找回。

应用状态：idle → committing → presenting → result；失败分 failedDefinite / reconciling。committing 禁抽和修改池、禁同集合规则编辑/归档/重置；presenting 同样禁这些操作，但允许跳过动画/返回/后台。后台立即停声音和动画；若提交尚在进行，完成后只更新保存状态，不在后台播放；恢复前台直接显示同记录。dispose 后提交仍由服务完成，不能因页面销毁取消已提交事务。

用户点击“再抽一次”是**新交互新 ID**；原记录任何状态原样保留。请求成功但动画中止，不能再调用 draw 作为“恢复”。演示用独立内存 Session，不注入正式仓库和写协调器。

## 6. 状态修改、历史与统计

setStatus 在事务读当前记录：若相等返回原值；否则写 status/updatedAt 和 completedAt。不更新其他快照、轮次或 drawnAt。UI 保存前禁该记录状态按钮；失败显示原状态。先采用提交后更新，不必实现复杂乐观更新。

每次实际状态变化在同一 UPDATE 中将 revision 加一，同态操作不增加。撤销保存旧 status/completedAt，并携带操作成功后的 expectedRevision 与 app generation；事务内仅当二者仍匹配时恢复旧值并再次增加 revision，避免旧 snackbar 覆盖用户后续修改。同毫秒和跨页面操作也由数据库 revision 防冲突；冲突提示打开详情再修改。撤销到 completed 恢复原 completedAt，不制造新标记时间；常规手动再次完成则使用新的 now。

历史每页 50，用 (drawnAt,drawOrdinal) 游标，筛选或搜索改变即重置；状态修改若使行不再符合筛选，提交后移除并刷新计数。集合筛选按 ID，包含归档；搜索匹配快照标题，SQL 使用参数化 instr，不把 %/_ 当通配符。列表日期在 UI 用当前时区转换，切时区/前台刷新分组。

summary SQL 聚合 COUNT(*) 与按 status SUM/COUNT；total=completed+pending+skipped。无记录为零个整数、率 null。全局不加 archived 过滤。按集合汇总须 LEFT JOIN 让零记录集合也可见。显示百分比一位小数，不把已舍入率再平均。

## 7. 备份与整体恢复

schemaVersion=1。Envelope 字段按 PRD；Settings 额外包括 redrawHintSeen（旧备份缺少时默认 false，需在 codec 明确定义为可选兼容字段）。内部 titleKey、drawOrdinal、revision 不导出：分别重算、按数组序重建、初始化为 0；恢复成功更新 app generation，旧撤销 token 失效。consumedItemIds 由关系表转回数组；collections/items 保留显式 sortOrder，cycles 保留所有旧轮，不只当前轮。

导出在一个一致性读事务取得所有数据和设置，再编码；不可分多次读而混入新抽记录。JSON UTF-8，UTC 时间统一 ISO 8601 毫秒 Z。保存适配器拿字节并使用系统文档保存功能；取消、失败、成功三态独立。导出成功取决于文件写入完成，不是对话框打开。exportedAt 为实际生成快照时刻，文件名用设备本地时间。

验证顺序：

1. 流式读入到临时空间，选择时优先预检长度，实际读取仍计字节；第一版备份读写资源边界 128 MiB。超出明确拒绝，不损坏旧库；导出前亦检查同一边界，不能生成本版本无法恢复的备份。此为资源默认值，T11 在基线容量夹具验证是否足够，必要时扩大或改流式处理，不能缩小业务字段限额。
2. 严格 JSON 对象、schemaVersion 为受支持整数，appVersion 只作信息，不用字符串比较判数据兼容性；缺字段、类型错误、未知必需枚举、非有限数拒绝。
3. 每类 ID 唯一、非空，引用存在，item/cycle/record 属于同一集合；sortOrder 非负且允许并列用 ID 稳定排序；sequence 正整数且同集合唯一。
4. 名称/标题/描述/备注/标准长度、NFC 标题唯一、100/1,000 容量；不设 20,000 历史拒绝阈值。时间严格解析为 UTC 毫秒，支持合法 ISO 时区偏移后归一化；不依赖 Dart 日期溢出自动修正。
5. completedAt 与 status 一致；cycleId 与 mode 一致；consumed ID 唯一且属于对应集合。每条 C 记录其 item 必须在关联轮消耗中，单个轮同 item 至多一条记录；每个消耗也必须有该轮对应记录，不接受无法解释的空消耗。当前轮取最大 sequence。归档或停用的已消耗 ID 合法。
6. iconKey/colorKey 必须属于 v1 支持集合；未知枚举不静默替换。空标准与可选字段允许，快照不能按当前实体值重写。

预览只展示已验证不可变快照，含导出时间、数量和覆盖提示；支持先导出当前数据，取消导出不自动当作确认恢复。恢复前用户明确点击“替换并恢复”，取得全局写锁并清理待提交 UI 会话，不能在确认后重新读取一个可变外部文件。

恢复采用**当前数据库的一次事务整体替换**，不复制打开中的 SQLite 文件：按 consumption→records→cycles→items→collections→settings 删；按 collections→items→cycles→consumptions→records→settings 插；外键和全部校验通过才提交。任意异常抛出回滚，旧库不变；不得嵌套独立仓库事务。成功后替换页面 generation、清空导航和缓存到集合页，刷新主题和统计；旧异步回调用 generation 拒绝写入恢复后的数据。

清空同样取得独占锁，事务删除全部业务表后插默认设置；两次确认后才执行，外部文件不触碰。失败旧数据保留。数据库无法正常打开时仍允许验证备份；实际替换损坏库的修复流程必须先保留故障文件，不能把普通失败当作首次安装覆盖。

## 8. 错误分类

领域错误用类型而非字符串判流程：validation/capacity/noAvailable/cycleExhausted/archived/conflict/storageUnavailable/commitUnknown/backupInvalid/unsupportedVersion。UI 映射中文，日志不输出用户标题、备注或完整 JSON。详情仅显示必要可理解原因；恢复失败必须明确“原有数据未更改”，只有证实回滚后才能这样写。所有成功提示都在提交或保存成功之后。
