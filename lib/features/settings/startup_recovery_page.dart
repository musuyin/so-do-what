import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/ui.dart';
import '../../core/data/database_recovery.dart';
import '../../core/domain/models.dart';

/// A recovery entry point that never opens or overwrites the failed database.
/// Only the recovery adapter performs file replacement after validation.
class StartupRecoveryPage extends StatefulWidget {
  const StartupRecoveryPage({
    super.key,
    required this.databasePath,
    required this.onRetry,
    required this.onRecovered,
    this.error,
    this.backupReader,
    this.recovery,
  });

  final String databasePath;
  final VoidCallback onRetry, onRecovered;
  final Object? error;
  final Future<String?> Function()? backupReader;
  final DatabaseRecovery? recovery;

  @override
  State<StartupRecoveryPage> createState() => _StartupRecoveryPageState();
}

class _StartupRecoveryPageState extends State<StartupRecoveryPage> {
  bool _busy = false;
  String? _message;
  bool get _needsUpdate =>
      widget.error is AppFailure &&
      (widget.error as AppFailure).code == 'unsupportedVersion';

  Future<String?> _readBackup() async {
    if (widget.backupReader != null) return widget.backupReader!();
    final file = await FilePicker.pickFile(
      dialogTitle: '选择备份文件',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (file == null) return null;
    const limit = 128 * 1024 * 1024;
    final length = await file.length();
    if (length != null && length > limit) {
      throw const AppFailure('backupInvalid', '备份超过可读取的大小');
    }
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in file.readAsByteStream()) {
      if (buffer.length + chunk.length > limit) {
        throw const AppFailure('backupInvalid', '备份超过可读取的大小');
      }
      buffer.add(chunk);
    }
    return utf8.decode(buffer.takeBytes());
  }

  Future<void> _restore() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final text = await _readBackup();
      if (text == null || !mounted) return;
      final recovery = widget.recovery ?? DatabaseRecovery();
      final backup = await recovery.prepareBackup(text);
      if (!mounted) return;
      final p = backup.preview;
      final accepted = await confirm(
        context,
        '从备份修复本地数据？',
        '备份导出于 ${dateLabel(p.exportedAt)} ${timeLabel(p.exportedAt)}。\n\n'
            '${p.collectionCount} 个集合 · ${p.itemCount} 个选项 · ${p.recordCount} 条记录\n\n'
            '恢复后的内容会以这份备份为准。当前无法打开的原有文件会单独保留，供之后排查；不会自动删除。',
        action: '保留原文件并恢复',
      );
      if (!accepted || !mounted) return;
      await recovery.recover(widget.databasePath, backup);
      if (mounted) widget.onRecovered();
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error is AppFailure
              ? '${error.message}。尚未完成恢复，请重试。'
              : '暂时无法完成恢复。请检查剩余空间与文件访问权限后重试。';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('打开本地数据')),
      body: PageBody(
        width: 560,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 48),
            Icon(
              Icons.folder_off_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 28),
            Text(
              '暂时无法打开本地数据',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            const Text('原有文件会保留，应用不会自动清空数据。请先检查设备剩余空间，然后重新打开。'),
            const SizedBox(height: 20),
            SectionCard(
              child: Text(
                widget.error is AppFailure &&
                        (widget.error as AppFailure).code ==
                            'unsupportedVersion'
                    ? '这份数据需要更新版本的应用。请更新后重新打开；旧版本不会覆盖它。'
                    : '如果仍无法打开，可以使用之前导出的完整备份进行恢复。恢复前会先检查文件并显示内容数量。',
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  _message!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : widget.onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重新打开'),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _busy || _needsUpdate ? null : _restore,
              icon: const Icon(Icons.restore_rounded),
              label: Text(_busy ? '正在检查与恢复…' : '选择备份恢复'),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            const SizedBox(height: 24),
            const Text('备份可能包含集合与行动记录。应用只在本地读取，不会上传文件。'),
            const SizedBox(height: 32),
          ],
        ),
      ),
    ),
  );
}
