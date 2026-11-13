import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../core/data/picker_store.dart';
import 'collection_draw_page.dart';
import 'gacha_machine.dart';

String statusLabel(RecordStatus status) => switch (status) {
  RecordStatus.pending => '待行动',
  RecordStatus.completed => '已做过',
  RecordStatus.skipped => '这次不做',
};

class RecordResultPage extends StatefulWidget {
  const RecordResultPage({
    super.key,
    required this.store,
    required this.record,
    this.newlyDrawn = false,
    this.returnRedraw = false,
    this.playFeedback = false,
  });
  final PickerStore store;
  final DrawRecord record;
  final bool newlyDrawn, returnRedraw, playFeedback;
  @override
  State<RecordResultPage> createState() => _RecordResultPageState();
}

class _RecordResultPageState extends State<RecordResultPage>
    with WidgetsBindingObserver {
  AudioPlayer? _player;
  bool _foreground = true;
  late DrawRecord _record;
  bool _busy = false, _archived = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.playFeedback) unawaited(_revealFeedback());
    _record = widget.record;
    _checkCollection();
    if (widget.newlyDrawn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          SemanticsService.sendAnnouncement(
            View.of(context),
            '这次抽到，${_record.itemTitleSnapshot}',
            Directionality.of(context),
          );
        }
      });
    }
  }

  Future<void> _revealFeedback() async {
    try {
      final settings = await widget.store.settings();
      if (!mounted || !_foreground) return;
      if (settings.hapticsEnabled) await HapticFeedback.lightImpact();
      if (!mounted || !_foreground || !settings.soundEnabled) return;
      _player = AudioPlayer();
      await _player!.play(AssetSource('sounds/reveal.wav'), volume: .35);
    } catch (_) {
      /* Feedback is optional and never changes the record. */
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) unawaited(_player?.stop() ?? Future<void>.value());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_player?.dispose() ?? Future<void>.value());
    super.dispose();
  }

  Future<void> _checkCollection() async {
    try {
      final c = await widget.store.getCollection(_record.collectionId);
      final current = await widget.store.reconcile(_record.id);
      if (mounted && current != null) setState(() => _record = current);
      if (mounted) setState(() => _archived = c.archived);
    } catch (_) {
      /* Result snapshots remain available if a collection cannot be loaded. */
    }
  }

  String _message(Object e) => e is AppFailure ? e.message : '暂时无法保存，请重试。';
  Future<void> _status(RecordStatus status) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final previous = _record;
      final generation = widget.store.generation;
      final updated = await widget.store.setStatus(_record.id, status);
      if (mounted) {
        setState(() => _record = updated);
        if (previous.status != updated.status) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 5),
              content: Text('已标记为${statusLabel(updated.status)}'),
              action: SnackBarAction(
                label: '撤销',
                onPressed: () async {
                  if (!mounted) return;
                  if (generation != widget.store.generation) {
                    setState(() => _error = '数据已更新，请重新打开记录。');
                    return;
                  }
                  setState(() => _busy = true);
                  try {
                    final restored = await widget.store.undoStatus(
                      previous,
                      expectedRevision: updated.revision,
                    );
                    if (mounted) setState(() => _record = restored);
                  } catch (e) {
                    if (mounted) setState(() => _error = _message(e));
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _redraw() async {
    if (_busy || _archived) return;
    setState(() => _busy = true);
    try {
      final settings = await widget.store.settings();
      if (!mounted) return;
      if (!settings.redrawHintSeen) {
        final yes = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('再给自己一个选择'),
            content: Text('再抽会新增一条记录，这条仍保留为“${statusLabel(_record.status)}”。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('再抽一次'),
              ),
            ],
          ),
        );
        if (yes != true) return;
        try {
          await widget.store.saveSettings(
            settings.copyWith(redrawHintSeen: true),
          );
        } catch (_) {}
      }
      if (!mounted) return;
      if (widget.returnRedraw) {
        Navigator.of(context).pop(true);
      } else {
        await Navigator.of(context).pushReplacement<void, void>(
          MaterialPageRoute(
            builder: (_) => CollectionDrawPage(
              store: widget.store,
              collectionId: _record.collectionId,
              drawImmediately: true,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_record.collectionNameSnapshot),
      leading: IconButton(
        tooltip: '关闭结果',
        icon: const Icon(Icons.close_rounded),
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
          children: [
            const Center(
              child: SizedBox(
                width: 150,
                height: 120,
                child: GachaMachine(instant: true),
              ),
            ),
            Text(
              widget.newlyDrawn ? '这次抽到' : '抽取记录',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 16),
            Text(
              _record.itemTitleSnapshot,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w600, height: 1.4),
            ),
            if (_record.itemNoteSnapshot.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(_record.itemNoteSnapshot, textAlign: TextAlign.center),
            ],
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer
                    .withValues(alpha: .45),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('怎样算做过', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Text(
                    _record.criterionSnapshot.isEmpty
                        ? '按你认为合适的程度，实际做过这件事'
                        : _record.criterionSnapshot,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.newlyDrawn && _record.status == RecordStatus.pending
                  ? '已加入待行动'
                  : '当前状态：${statusLabel(_record.status)}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : () => _status(RecordStatus.completed),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  _busy
                      ? '正在保存…'
                      : _record.status == RecordStatus.completed
                      ? '已做过 ✓'
                      : '我做过了',
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _busy ? null : () => _status(RecordStatus.skipped),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('这次不做'),
              ),
            ),
            if (_record.status != RecordStatus.pending)
              TextButton(
                onPressed: _busy ? null : () => _status(RecordStatus.pending),
                child: const Text('改回待行动'),
              ),
            if (!_archived)
              TextButton(
                onPressed: _busy ? null : _redraw,
                child: const Text('再抽一次'),
              )
            else
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text('集合已归档，恢复后可继续抽取。', textAlign: TextAlign.center),
              ),
            if (_error != null) Text(_error!, textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}
