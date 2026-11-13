import 'package:flutter/material.dart';

import '../../../core/data/picker_store.dart';
import '../collections/collection_editor_page.dart';
import '../items/items_page.dart';
import '../history/history_page.dart';
import '../review/review_page.dart';
import 'gacha_machine.dart';
import 'gacha_presentation.dart';
import 'record_result_page.dart';

String drawModeLabel(DrawMode mode) => switch (mode) {
  DrawMode.allowRepeat => '允许重复',
  DrawMode.avoidPrevious => '仅避免连续重复',
  DrawMode.cycle => '整轮不重复',
};

class CollectionDrawPage extends StatefulWidget {
  const CollectionDrawPage({
    super.key,
    required this.store,
    required this.collectionId,
    this.drawImmediately = false,
  });
  final PickerStore store;
  final String collectionId;
  final bool drawImmediately;
  @override
  State<CollectionDrawPage> createState() => _CollectionDrawPageState();
}

class _CollectionDrawPageState extends State<CollectionDrawPage>
    with WidgetsBindingObserver {
  Collection? _collection;
  List<Item> _available = [];
  CollectionCycle? _cycle;
  int _pending = 0;
  bool _busy = false, _loading = true, _foreground = true, _autoDrawn = false;
  String? _error, _requestId;
  DrawRecord? _waitingRecord;
  PickerSettings _settings = const PickerSettings();
  PickerStore get store => widget.store;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await store.getCollection(widget.collectionId);
      final items = await store.listItems(c.id);
      final cycle = await store.currentCycle(c.id);
      final settings = await store.settings();
      final summary = await store.summary(collectionId: c.id);
      if (!mounted) return;
      setState(() {
        _collection = c;
        _available = items.where((i) => i.available).toList();
        _cycle = cycle;
        _settings = settings;
        _pending = summary.pending;
        _loading = false;
        _error = null;
      });
      if (widget.drawImmediately &&
          !_autoDrawn &&
          _requestId == null &&
          !_busy) {
        // Only used when a historical result explicitly requests another draw.
        _autoDrawn = true;
        _requestId = store.newId();
        await _draw();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _message(e);
        });
      }
    }
  }

  String _message(Object e) => e is AppFailure ? e.message : '暂时无法读取或保存，请重试。';
  int get remaining => _available
      .where((i) => !(_cycle?.consumedItemIds.contains(i.id) ?? false))
      .length;
  Future<void> _draw() async {
    if (_busy || _collection == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    _requestId ??= store.newId();
    try {
      final record = await store.draw(
        widget.collectionId,
        requestId: _requestId!,
      );
      _requestId = null;
      if (!mounted) return;
      if (!_foreground) {
        _waitingRecord = record;
        return;
      }
      await _present(record);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _message(e);
        });
      }
    }
  }

  Future<void> _present(DrawRecord record) async {
    if (!mounted) return;
    var revealFeedback = true;
    final reduce =
        _settings.reduceMotion || MediaQuery.disableAnimationsOf(context);
    if (!reduce && record.styleSnapshot == PresentationStyle.gacha) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (routeContext) => GachaPresentation(
            record: record,
            settings: _settings,
            onFeedbackPolicy: (enabled) => revealFeedback = enabled,
            onReveal: () => Navigator.of(routeContext).pop(),
          ),
        ),
      );
    }
    if (!mounted) return;
    final again = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RecordResultPage(
          store: store,
          record: record,
          newlyDrawn: true,
          playFeedback: revealFeedback,
          returnRedraw: true,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    await _load();
    if (again == true && mounted) await _draw();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && _waitingRecord != null) {
      final record = _waitingRecord!;
      _waitingRecord = null;
      // A background commit is revealed statically, without replay.
      _presentStatic(record);
    }
  }

  Future<void> _presentStatic(DrawRecord record) async {
    final again = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RecordResultPage(
          store: store,
          record: record,
          newlyDrawn: true,
          playFeedback: false,
          returnRedraw: true,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    await _load();
    if (again == true && mounted) await _draw();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context)
        .push<void>(MaterialPageRoute(builder: (_) => page));
    if (mounted) await _load();
  }

  Future<void> _newCycle({bool early = false}) async {
    if (early) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('开启新一轮？'),
          content: const Text('本轮的抽取进度将重新开始，已有记录会保留。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('开启新一轮'),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await store.startNextCycle(
        widget.collectionId,
        expectedCycleId: _cycle?.id,
      );
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archive() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('归档这个集合？'),
        content: const Text('选项和历史都会保留，可以从设置中恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('归档'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await store.archiveCollection(widget.collectionId, true);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _message(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _collection;
    return Scaffold(
      appBar: AppBar(
        title: Text(c?.name ?? '集合'),
        actions: [
          if (c != null && !c.archived)
            PopupMenuButton<String>(
              enabled: !_busy && _requestId == null,
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    _open(CollectionEditorPage(store: store, collection: c));
                  case 'items':
                    _open(ItemsPage(store: store, collection: c));
                  case 'cycle':
                    _newCycle(early: true);
                  case 'archive':
                    _archive();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('编辑集合')),
                const PopupMenuItem(value: 'items', child: Text('管理选项')),
                if (c.drawMode == DrawMode.cycle)
                  const PopupMenuItem(value: 'cycle', child: Text('重置本轮')),
                const PopupMenuItem(value: 'archive', child: Text('归档集合')),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    if (c != null) ...[
                      Text(
                        drawModeLabel(c.drawMode),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (c.description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            c.description,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      const SizedBox(height: 16),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: _busy || _requestId != null
                                ? null
                                : () => _open(
                                    ItemsPage(store: store, collection: c),
                                  ),
                            child: Text('选项 ${_available.length}'),
                          ),
                          OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () => _open(
                                    HistoryPage(
                                      store: store,
                                      collectionId: c.id,
                                    ),
                                  ),
                            child: const Text('记录'),
                          ),
                          OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () => _open(
                                    ReviewPage(
                                      store: store,
                                      collectionId: c.id,
                                    ),
                                  ),
                            child: const Text('回顾'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: GachaMachine(
                          instant:
                              c.presentationStyle == PresentationStyle.instant,
                        ),
                      ),
                      if (c.archived)
                        const Text(
                          '集合已归档，恢复后可继续抽取。',
                          textAlign: TextAlign.center,
                        )
                      else ...[
                        if (c.drawMode == DrawMode.cycle &&
                            _available.isNotEmpty)
                          Text(
                            remaining == 0
                                ? '本轮已抽完'
                                : '本轮还剩 $remaining / ${_available.length} 个可抽',
                            textAlign: TextAlign.center,
                          ),
                        if (c.drawMode == DrawMode.avoidPrevious &&
                            _available.length == 1)
                          const Text(
                            '仅 1 个可用选项，本次允许重复',
                            textAlign: TextAlign.center,
                          ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _busy
                              ? null
                              : _available.isEmpty
                              ? () => _open(
                                  ItemsPage(store: store, collection: c),
                                )
                              : c.drawMode == DrawMode.cycle && remaining == 0
                              ? _newCycle
                              : _draw,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Text(
                              _busy
                                  ? '正在保存…'
                                  : _available.isEmpty
                                  ? '添加 / 启用选项'
                                  : c.drawMode == DrawMode.cycle &&
                                        remaining == 0
                                  ? '开启新一轮'
                                  : _requestId != null
                                  ? '重试这次抽取'
                                  : '抽一个',
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(switch (c.drawMode) {
                          DrawMode.allowRepeat => '每个可用选项的机会相同，也可能再次遇见。',
                          DrawMode.avoidPrevious => '暂时避开上一次抽到的选项。',
                          DrawMode.cycle => '抽到即计入本轮；做过与否不会改变轮次。',
                        }, textAlign: TextAlign.center),
                      ],
                      if (_pending > 0)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _open(
                                  HistoryPage(store: store, collectionId: c.id),
                                ),
                          child: Text('还有 $_pending 条待行动 ›'),
                        ),
                    ],
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(_error!, textAlign: TextAlign.center),
                      ),
                    if (c == null)
                      TextButton(onPressed: _load, child: const Text('重试')),
                  ],
                ),
              ),
            ),
    );
  }
}
