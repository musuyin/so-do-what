# 验证报告 · v0.1.0 试用版

日期：2026-11-13。验证对象：当前工作区实现（提交前验证）；首次交付，未声称完整 P0 验收完成。

## 环境

Windows 11；Flutter 3.47.7 stable / Dart 3.13.5；JDK 17.0.12；Android SDK 36、Build Tools 36.0.0；Gradle 9.3.1 / AGP 9.1.0 / Kotlin 2.4.0。设备：MuMu Android 12 API 32 x64，型号上报 HBP-AL00，属于模拟器，不能称真实手机。

现有 SDK 位于其他本地工程的 `.tooling`，仅复用工具链和缓存，应用代码/数据互相独立。Windows 跨盘 Kotlin 增量缓存冲突通过 `kotlin.incremental=false` 解决；宿主 sqlite3 下载超时通过官方 system hook 改用系统 winsqlite3 解决。发布构建、设备测试应串行，避免 Flutter 生成插件注册文件互相覆盖。

## 已运行验证

- `flutter analyze`：无问题；最终构建前再次执行。
- `flutter test`：59/59 全部通过，55 秒。23 个真实 SQLite 核心测试、19 个故障库文件恢复测试、7 个管理页/启动恢复页组件测试、9 个抽取/动画组件测试、1 个最大容量测试。
- `flutter test integration_test -d emulator-5554`：2/2 通过。真实 Android SQLite 关闭重开、幂等、轮次、完成、备份清空恢复、下一次抽取、历史及回顾导航；另一个测试从实际运行页面生成截图。
- 页面与组件：360 宽、200% 字号、深浅主题、未保存返回确认、长文可滚动；动画正常结束/跳过/系统减动/后台恢复保持同一已提交结果。组件测试不是硬件流畅度测量。
- 故障回滚：插入前/后、消耗后、提交后响应异常、恢复删除后/插入中途、清空中途。对应断言见 `core-validation.md`。

- `python tool/record_device_flow.py`：Android 完整扭蛋、已保存结果、完成标记通过；原生 screenrecord 保存 `docs/recordings/gacha-android.mp4`。测试临时修改旋转/密度并在结束后恢复。
- `python tool/test_native_documents.py`：原生 DocumentsUI 保存备份、选取该文件、Flutter预览确认覆盖、取消保存均通过；恢复移除了备份之后新增的虚构集合，原记录数正确。此测试需配套脚本，普通 integration_test 批跑会跳过它，避免等待无人操作的系统对话框。

原始构建/测试日志存放 `.tooling/`（忽略目录，不提交）；本报告保留命令和实际结论，测试源码可复跑。

## A01–A22 证据范围

| 验收 | 自动验证 | Android / 人工边界 |
| --- | --- | --- |
| A01–A02 | 创建与批量导入原子性、NFC、空行重复、容量通过 | SQLite 重开通过；中文键盘人工检查待补 |
| A03–A06 | 空池不随机、A可重复、B排除前次与单项通过 | 规则控件有实现，逐模式真机长期使用待补 |
| A07–A10 | C耗尽、新轮幂等、状态不归还、编辑/归档恢复/切模式保持通过 | Android 关闭重开和轮次通过 |
| A11–A12 | 连点仅一条、持久化后才演出、跳过/后台/减动、全部故障回滚通过 | 后台/硬件音效触感人工检查待补 |
| A13 | 文件数据库及 Android store 关闭重开通过 | 操作系统杀进程/断电中断检查待补 |
| A14–A15 | 重抽保留旧记录、9种状态转换、同态无副作用、撤销冲突通过 | Android 状态/回顾导航通过 |
| A16–A18 | 3/11=27.3%、零分母、快照不可变、归档统计、历史分页通过 | 实际页面截图通过 |
| A19–A20 | 逐实体备份往返、非法备份与失败不改旧数据通过 | Android SQLite 恢复通过；系统保存、选择恢复、取消保存均通过 |
| A21 | 无账号/后端；所有功能使用本地存储与内置资源 | 飞行模式和系统文件界面另列结果 |
| A22 | Demo无正式仓库依赖，widget打开不新增记录 | 完整Android扭蛋演出、已保存结果与完成标记通过并录屏 |

## 最大容量测试

虚构数据：100 集合 × 每集合 1,000 项 = 100,000 项，20,001 条历史。备份 UTF-8 29,165,895 字节，小于 128 MiB 资源边界。真实 SQLite FFI 导入 46,478 ms，包含导出和再校验的往返约 54,673 ms。集合/选项/记录数量正确，历史50条游标分页不重复；再抽后20,002条成功保存。

这些是 Windows 宿主功能/压力数据，不是 Android profile 性能。真机首屏、SQL分页和动画帧预算未测，不宣称达到计划建议性能目标。大备份解析当前同步执行，可能短暂占用界面线程，应避免操作直到恢复完成。

## 页面证据

`docs/screenshots/01–10*.png`：390×844 逻辑像素手机视口截图（1.5倍输出）；`docs/screenshots/wide/*.png`：宽屏原始截图。来自 Android debug 运行中的 RenderRepaintBoundary，不是概念图；每张只显示当前视口，不表示滚动下方的全部内容都在图中。

包含集合、详情扭蛋、结果、选项、编辑、历史、回顾、设置，以及深色详情/回顾。完整页面深色矩阵、430宽、200%截图、TalkBack顺序和中文键盘截图尚未齐全；不能宣称完成全部视觉验收。

## 已知限制与发布判断

- 损坏数据库启动恢复已实现，并通过19项真实文件测试；包括原db/WAL/SHM字节保留、替换失败回滚、多阶段中断恢复和较新版本拒绝覆盖。Android设备断电/存储满场景尚未验证。
- 真机验证、TalkBack、硬件音效/触感、完整飞行模式流程、系统文件选择器故障路径、profile性能仍有待验项。
- 当前 Android release 使用开发测试签名和开发包名 `dev.local.so_do_what`。它是自用试用包；正式长期签名密钥及发行身份未确定。
- 本次用户已选择 Apache-2.0；依赖和资源许可已核查，完整文本随仓库提供。

结论：核心功能与数据不变量通过自动及模拟器测试，可交付试用安装包。由于上述设备与视觉验收缺口，使用 GitHub prerelease 标识，不称完整 P0 或正式生产版本。

## 最终 APK

`flutter build apk --release` 成功，128.3秒；APK约52.0 MB，minSdk24 / targetSdk36，arm64-v8a、armeabi-v7a、x86_64。Android12模拟器安装、强制停止后冷启动通过，无fatal/unhandled异常，截图 `docs/screenshots/11-release-empty.png`。release实包权限仅自有动态接收器权限，无INTERNET；allowBackup=false，云备份/迁移排除规则已合并。

飞行模式检查中模拟器连接/服务中断，重新启动模拟器并恢复网络设置后完成普通冷启动。因此不将飞行模式全流程标为通过。

交付路径：`outputs/so-do-what-0.1.0-android.apk`，附`.sha256`。SHA-256：`fa9e2965fa6a545d5b65bc33a36c0fcd4bf4d57fc015d850dd29d39d7166bd79`。安装包使用本地开发测试签名；不含私钥。首次交付采用 GitHub v0.1.0 prerelease。

发布渠道：[GitHub v0.1.0 试用版](https://github.com/musuyin/so-do-what/releases/tag/v0.1.0)，提供APK与SHA-256。

