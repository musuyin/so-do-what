import 'package:flutter/material.dart';

import '../../app/ui.dart';
import '../../core/data/picker_store.dart';
import '../drawing/collection_draw_page.dart';
import '../drawing/demo_page.dart';
import '../items/items_page.dart';
import 'collection_editor_page.dart';

class CollectionsPage extends StatefulWidget {
  const CollectionsPage({
    super.key,
    required this.store,
    this.archived = false,
    this.onSettings,
  });
  final PickerStore store;
  final bool archived;
  final VoidCallback? onSettings;
  @override
  State<CollectionsPage> createState() => _CollectionsPageState();
}

class _CollectionsPageState extends State<CollectionsPage> {
  late Future<List<Collection>> _data;
  String _query = '';
  final _searchController = TextEditingController();
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _data = widget.store.listCollections(
      archived: widget.archived,
      search: _query,
    );
  }

  void _refresh() {
    if (mounted) setState(_load);
  }

  Future<void> _edit() async {
    await openPage(context, CollectionEditorPage(store: widget.store));
    _refresh();
  }

  Future<void> _sort() async {
    try {
      final a = await widget.store.listCollections();
      final b = await widget.store.listCollections(archived: true);
      final all = [...a, ...b]
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      if (!mounted) return;
      await openPage(
        context,
        OrderPage(
          title: '调整集合顺序',
          ids: all.map((e) => e.id).toList(),
          labels: all
              .map((e) => '${e.name}${e.archived ? '（已归档）' : ''}')
              .toList(),
          onSave: widget.store.reorderCollections,
        ),
      );
      _refresh();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.archived ? '已归档集合' : '我的集合'),
      actions: [
        if (widget.onSettings != null)
          IconButton(
            tooltip: '设置',
            onPressed: widget.onSettings,
            icon: const Icon(Icons.tune_rounded),
          ),
        if (!widget.archived)
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (v) async {
              if (v == 'sort') {
                await _sort();
              } else {
                await openPage(
                  context,
                  CollectionsPage(store: widget.store, archived: true),
                );
                _refresh();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'sort', child: Text('调整顺序')),
              PopupMenuItem(value: 'archive', child: Text('已归档')),
            ],
          ),
      ],
    ),
    body: PageBody(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            widget.archived ? '收好的集合，随时可以再打开。' : '把喜欢的事，留给下一次有空。',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          TextField(
            decoration: const InputDecoration(
              labelText: '搜索集合',
              prefixIcon: Icon(Icons.search_rounded),
            ),
            onChanged: (v) => setState(() {
              _query = v;
              _load();
            }),
          ),
          const SizedBox(height: 24),
          FutureBuilder<List<Collection>>(
            future: _data,
            builder: (c, s) {
              if (s.hasError) {
                return LoadError(error: s.error!, retry: _refresh);
              }
              if (!s.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final data = s.data!;
              if (data.isEmpty) {
                return BlankState(
                  title: _query.isNotEmpty
                      ? '没有找到匹配的集合'
                      : widget.archived
                      ? '还没有归档集合'
                      : '把想做的事装进来，抽一个开始。',
                  action: _query.isNotEmpty
                      ? TextButton(
                          onPressed: () => setState(() {
                            _query = '';
                            _load();
                          }),
                          child: const Text('清除搜索'),
                        )
                      : widget.archived
                      ? null
                      : Column(
                          children: [
                            FilledButton(
                              onPressed: _edit,
                              child: const Text('创建第一个集合'),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: () =>
                                  openPage(context, const DemoPage()),
                              child: const Text('体验一下'),
                            ),
                          ],
                        ),
                );
              }
              return LayoutBuilder(
                builder: (c, constraints) {
                  final cards = data.map(_card).toList();
                  return Column(
                    children: [
                      if (constraints.maxWidth >= 600)
                        Wrap(
                          spacing: 16,
                          runSpacing: 12,
                          children: cards
                              .map(
                                (e) => SizedBox(
                                  width: (constraints.maxWidth - 16) / 2,
                                  child: e,
                                ),
                              )
                              .toList(),
                        )
                      else
                        ...cards,
                      if (!widget.archived) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _edit,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('新建集合'),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    ),
  );
  Widget _card(Collection col) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () async {
        await openPage(
          context,
          CollectionDrawPage(store: widget.store, collectionId: col.id),
        );
        _refresh();
      },
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _color(col.colorKey),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                collectionIcons[col.iconKey] ?? Icons.casino_rounded,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    col.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<List<Item>>(
                    future: widget.store.listItems(col.id),
                    builder: (c, s) => Text(
                      '${s.hasData ? s.data!.where((e) => e.available).length : '—'} 个可用 · ${col.presentationStyle == PresentationStyle.gacha ? '扭蛋' : '直接揭晓'}',
                    ),
                  ),
                  FutureBuilder<Summary>(
                    future: widget.store.summary(collectionId: col.id),
                    builder: (c, s) => s.hasData && s.data!.pending > 0
                        ? Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('还有 ${s.data!.pending} 条待行动'),
                          )
                        : const SizedBox(),
                  ),
                  if (widget.archived)
                    TextButton(
                      onPressed: () async {
                        try {
                          await widget.store.archiveCollection(col.id, false);
                          _refresh();
                        } catch (e) {
                          if (mounted) showError(context, e);
                        }
                      },
                      child: const Text('恢复集合'),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    ),
  );
  Color _color(String key) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Color(switch (key) {
      'lavender' => dark ? 0xff39323f : 0xffeee8f4,
      'sky' => dark ? 0xff2c3941 : 0xffe5edf2,
      'peach' => dark ? 0xff40362e : 0xfff4e8de,
      _ => dark ? 0xff303a32 : 0xffe8eee5,
    });
  }
}
