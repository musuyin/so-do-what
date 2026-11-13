import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/ui.dart';
import '../../core/data/picker_store.dart';
import '../collections/collections_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.store,
    required this.onSettingsChanged,
    required this.onReset,
  });
  final PickerStore store;
  final VoidCallback onSettingsChanged, onReset;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  PickerSettings? _settings;
  bool _busy = false;
  Object? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await widget.store.settings();
      if (mounted) setState(() => _settings = s);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save(PickerSettings settings) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.store.saveSettings(settings);
      if (mounted) setState(() => _settings = settings);
      widget.onSettingsChanged();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    final text = await widget.store.exportBackup();
    final date = DateTime.now();
    String pad(int n) => n.toString().padLeft(2, '0');
    final name =
        'random-picker-backup-${date.year}${pad(date.month)}${pad(date.day)}-${pad(date.hour)}${pad(date.minute)}${pad(date.second)}.json';
    final result = await FilePicker.saveFile(
      dialogTitle: '保存备份',
      fileName: name,
      mimeType: 'application/json',
      bytes: Uint8List.fromList(utf8.encode(text)),
    );
    if (result != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('备份已保存')));
    }
  }

  Future<void> _restore() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (picked.isEmpty) return;
    final file = picked.single;
    final length = await file.length();
    if (length != null && length > 128 * 1024 * 1024) {
      throw const AppFailure('backupInvalid', '备份超过可读取的大小');
    }
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in file.readAsByteStream()) {
      if (buffer.length + chunk.length > 128 * 1024 * 1024) {
        throw const AppFailure('backupInvalid', '备份超过可读取的大小');
      }
      buffer.add(chunk);
    }
    final bytes = buffer.takeBytes();
    final preview = widget.store.validateBackup(utf8.decode(bytes));
    if (!mounted) return;
    while (mounted) {
      if (!mounted) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('恢复备份'),
          content: SingleChildScrollView(
            child: Text(
              '导出于 ${dateLabel(preview.exportedAt)} ${timeLabel(preview.exportedAt)}\n\n${preview.collectionCount} 个集合 · ${preview.itemCount} 个选项 · ${preview.recordCount} 条记录\n\n当前的集合、选项、记录和设置将全部被替换。',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, 'cancel'),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, 'backup'),
              child: const Text('先备份当前数据'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, 'restore'),
              child: const Text('替换并恢复'),
            ),
          ],
        ),
      );
      if (choice == 'backup') {
        await _export();
        continue;
      }
      if (choice != 'restore') return;
      await widget.store.restoreBackup(preview);
      widget.onReset();
      return;
    }
  }

  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await work();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('设置')),
        body: PageBody(
          width: 640,
          child: s == null
              ? (_error == null
                    ? const Center(child: CircularProgressIndicator())
                    : LoadError(error: _error!, retry: _load))
              : ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    _heading('外观'),
                    SectionCard(
                      child: Column(
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: s.themeMode,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: '主题'),
                            items: const [
                              DropdownMenuItem(
                                value: 'system',
                                child: Text('跟随系统'),
                              ),
                              DropdownMenuItem(
                                value: 'light',
                                child: Text('浅色'),
                              ),
                              DropdownMenuItem(
                                value: 'dark',
                                child: Text('深色'),
                              ),
                            ],
                            onChanged: _busy
                                ? null
                                : (v) => _save(s.copyWith(themeMode: v)),
                          ),
                          const SizedBox(height: 16),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('减少动态效果'),
                            subtitle: Text(
                              MediaQuery.disableAnimationsOf(context)
                                  ? '系统已启用'
                                  : '直接展示结果，减少位移和旋转',
                            ),
                            value: s.reduceMotion,
                            onChanged: _busy
                                ? null
                                : (v) => _save(s.copyWith(reduceMotion: v)),
                          ),
                        ],
                      ),
                    ),
                    _heading('轻轻回应'),
                    SectionCard(
                      child: Column(
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('音效'),
                            subtitle: const Text('仅播放内置的轻音效'),
                            value: s.soundEnabled,
                            onChanged: _busy
                                ? null
                                : (v) => _save(s.copyWith(soundEnabled: v)),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('触感'),
                            value: s.hapticsEnabled,
                            onChanged: _busy
                                ? null
                                : (v) => _save(s.copyWith(hapticsEnabled: v)),
                          ),
                        ],
                      ),
                    ),
                    _heading('数据，留在自己手中'),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Text('备份为明文文件，可能包含你的集合与行动记录，请自行保管。'),
                    ),
                    SectionCard(
                      child: Column(
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.file_download_outlined),
                            title: const Text('导出完整备份'),
                            onTap: _busy ? null : () => _run(_export),
                          ),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.restore_rounded),
                            title: const Text('从备份覆盖恢复'),
                            onTap: _busy ? null : () => _run(_restore),
                          ),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.inventory_2_outlined),
                            title: const Text('已归档集合'),
                            onTap: _busy
                                ? null
                                : () => openPage(
                                    context,
                                    CollectionsPage(
                                      store: widget.store,
                                      archived: true,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                    _heading('关于'),
                    SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('随手抽 · 0.1.0'),
                          const SizedBox(height: 8),
                          const Text('离线、免费、无广告。没有账号，也不会上传你的记录。'),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () => showLicensePage(
                              context: context,
                              applicationName: '随手抽',
                              applicationVersion: '0.1.0',
                              applicationLegalese:
                                  '扭蛋绘图及内置音效由本项目原创。项目使用 Apache-2.0 许可证。',
                            ),
                            child: const Text('资源与依赖许可'),
                          ),
                        ],
                      ),
                    ),
                    _heading('危险操作'),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              if (!await confirm(
                                context,
                                '清空全部数据？',
                                '所有集合、选项、记录和设置将被清空。已经导出的备份文件不会被删除。',
                                action: '继续清空',
                              )) {
                                return;
                              }
                              if (!context.mounted) return;
                              if (!await confirm(
                                context,
                                '最后确认',
                                '此操作无法撤销。请确认已保存需要的备份。',
                                action: '清空全部数据',
                              )) {
                                return;
                              }
                              await widget.store.clear();
                              widget.onReset();
                            }),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('清空全部数据'),
                    ),
                    if (_busy)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    const SizedBox(height: 32),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 16),
    child: Text(text, style: Theme.of(context).textTheme.titleLarge),
  );
}
