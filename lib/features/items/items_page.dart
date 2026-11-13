import 'package:flutter/material.dart';

import '../../app/ui.dart';
import '../../core/data/picker_store.dart';

class ItemsPage extends StatefulWidget {
  const ItemsPage({super.key, required this.store, required this.collection});
  final PickerStore store;
  final Collection collection;
  @override
  State<ItemsPage> createState() => _ItemsPageState();
}

class _ItemsPageState extends State<ItemsPage> {
  late Future<List<Item>> _data;
  bool _archived = false;
  String _query = '';
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _data = widget.store.listItems(
      widget.collection.id,
      archived: _archived,
      search: _query,
    );
  }

  void _refresh() {
    if (mounted) setState(_load);
  }

  Future<void> _edit([Item? item]) async {
    final saved = await openPage<bool>(
      context,
      ItemEditorPage(
        store: widget.store,
        collectionId: widget.collection.id,
        item: item,
      ),
    );
    if (saved == true) _refresh();
  }

  Future<void> _batch() async {
    await openPage(
      context,
      BatchImportPage(store: widget.store, collectionId: widget.collection.id),
    );
    _refresh();
  }

  Future<void> _sort() async {
    final normal = await widget.store.listItems(widget.collection.id);
    final archived = await widget.store.listItems(
      widget.collection.id,
      archived: true,
    );
    final all = [...normal, ...archived]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    if (!mounted) return;
    await openPage(
      context,
      OrderPage(
        title: '调整选项顺序',
        ids: all.map((e) => e.id).toList(),
        labels: all
            .map((e) => '${e.title}${e.archivedAt == null ? '' : '（已归档）'}')
            .toList(),
        onSave: (ids) => widget.store.reorderItems(widget.collection.id, ids),
      ),
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final readOnly = widget.collection.archivedAt != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('管理选项'),
        actions: [
          if (!readOnly)
            IconButton(
              tooltip: '调整顺序',
              onPressed: _sort,
              icon: const Icon(Icons.reorder_rounded),
            ),
        ],
      ),
      body: PageBody(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              widget.collection.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            TextField(
              decoration: const InputDecoration(
                labelText: '搜索选项',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (v) => setState(() {
                _query = v;
                _load();
              }),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: const Text('已归档'),
                  selected: _archived,
                  onSelected: (v) => setState(() {
                    _archived = v;
                    _load();
                  }),
                ),
                if (!readOnly) ...[
                  FilledButton.icon(
                    onPressed: () => _edit(),
                    icon: const Icon(Icons.add),
                    label: const Text('添加'),
                  ),
                  OutlinedButton(onPressed: _batch, child: const Text('逐行导入')),
                ],
              ],
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<Item>>(
              future: _data,
              builder: (c, s) {
                if (s.hasError) {
                  return LoadError(error: s.error!, retry: _refresh);
                }
                if (!s.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (s.data!.isEmpty) return const BlankState(title: '这里还没有选项');
                return Column(
                  children: s.data!
                      .map(
                        (item) => Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            title: Text(item.title),
                            subtitle: Text(
                              [
                                if (item.note.isNotEmpty) item.note,
                                item.archivedAt != null
                                    ? '已归档'
                                    : item.enabled
                                    ? '可抽取'
                                    : '已停用',
                              ].join('\n'),
                            ),
                            onTap: readOnly || _archived
                                ? null
                                : () => _edit(item),
                            trailing: !readOnly
                                ? PopupMenuButton<String>(
                                    onSelected: (v) async {
                                      try {
                                        if (v == 'archive') {
                                          await widget.store.archiveItem(
                                            item.id,
                                            !_archived,
                                          );
                                        } else {
                                          await widget.store.saveItem(
                                            id: item.id,
                                            collectionId: item.collectionId,
                                            title: item.title,
                                            note: item.note,
                                            enabled: !item.enabled,
                                          );
                                        }
                                        _refresh();
                                      } catch (e) {
                                        if (c.mounted) showError(c, e);
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      if (!_archived)
                                        PopupMenuItem(
                                          value: 'toggle',
                                          child: Text(
                                            item.enabled ? '停用' : '启用',
                                          ),
                                        ),
                                      PopupMenuItem(
                                        value: 'archive',
                                        child: Text(_archived ? '恢复' : '归档'),
                                      ),
                                    ],
                                  )
                                : null,
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class BatchImportPage extends StatefulWidget {
  const BatchImportPage({
    super.key,
    required this.store,
    required this.collectionId,
  });
  final PickerStore store;
  final String collectionId;
  @override
  State<BatchImportPage> createState() => _BatchImportPageState();
}

class _BatchImportPageState extends State<BatchImportPage> {
  final _text = TextEditingController();
  BatchPreview? _preview;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _validate() async {
    setState(() => _busy = true);
    try {
      final p = await widget.store.previewImport(
        widget.collectionId,
        _text.text,
      );
      if (mounted) {
        setState(() {
          _preview = p;
          _error = null;
        });
      }
    } catch (e) {
      setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('逐行导入')),
    body: PageBody(
      width: 560,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('每行一个标题。空行和重复会跳过，超长内容需要先修改。'),
          const SizedBox(height: 20),
          TextField(
            controller: _text,
            minLines: 8,
            maxLines: 16,
            onChanged: (_) => setState(() => _preview = null),
            decoration: InputDecoration(
              labelText: '粘贴选项（最多 500 行）',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: _busy ? null : _validate,
            child: const Text('预览导入'),
          ),
          if (_preview != null) ...[
            const SizedBox(height: 20),
            Text(
              '新增 ${_preview!.added} 项 · 重复 ${_preview!.duplicates} 项 · 空行 ${_preview!.blank} · 错误 ${_preview!.invalid}',
            ),
            for (final line in _preview!.lines)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '第 ${line.lineNumber} 行：${line.title.isEmpty ? '（空行）' : line.title}',
                ),
                subtitle: Text(switch (line.kind) {
                  ImportKind.added => '新增',
                  ImportKind.blank => '跳过空行',
                  ImportKind.duplicateExisting => '已有同名选项（含归档项），跳过',
                  ImportKind.duplicateBatch => '本批重复，跳过',
                  ImportKind.invalid => '超过 100 字，请返回修改',
                }),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy || !_preview!.canSave
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      try {
                        await widget.store.importItems(
                          widget.collectionId,
                          _text.text,
                        );
                        if (context.mounted) Navigator.pop(context, true);
                      } catch (e) {
                        if (context.mounted) showError(context, e);
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              child: Text(_busy ? '正在保存…' : '确认添加'),
            ),
          ],
        ],
      ),
    ),
  );
}

class OrderPage extends StatefulWidget {
  const OrderPage({
    super.key,
    required this.title,
    required this.ids,
    required this.labels,
    required this.onSave,
  });
  final String title;
  final List<String> ids, labels;
  final Future<void> Function(List<String>) onSave;
  @override
  State<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> {
  late List<String> ids;
  late Map<String, String> labels;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    ids = [...widget.ids];
    labels = Map.fromIterables(widget.ids, widget.labels);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      actions: [
        TextButton(
          onPressed: busy
              ? null
              : () async {
                  setState(() => busy = true);
                  try {
                    await widget.onSave(ids);
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                    if (mounted) setState(() => busy = false);
                  }
                },
          child: const Text('保存'),
        ),
      ],
    ),
    body: PageBody(
      child: ReorderableListView(
        padding: const EdgeInsets.all(24),
        onReorderItem: (old, next) => setState(() {
          ids.insert(next, ids.removeAt(old));
        }),
        children: [
          for (final id in ids)
            Card(
              key: ValueKey(id),
              child: ListTile(
                title: Text(labels[id]!),
                trailing: const Icon(Icons.drag_handle_rounded),
              ),
            ),
        ],
      ),
    ),
  );
}

class ItemEditorPage extends StatefulWidget {
  const ItemEditorPage({
    super.key,
    required this.store,
    required this.collectionId,
    this.item,
  });
  final PickerStore store;
  final String collectionId;
  final Item? item;
  @override
  State<ItemEditorPage> createState() => _ItemEditorPageState();
}

class _ItemEditorPageState extends State<ItemEditorPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title, _note;
  bool _busy = false, _dirty = false, _done = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.item?.title);
    _note = TextEditingController(text: widget.item?.note);
    for (final c in [_title, _note]) {
      c.addListener(() {
        if (mounted) setState(() => _dirty = true);
      });
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await widget.store.saveItem(
        id: widget.item?.id,
        collectionId: widget.collectionId,
        title: _title.text,
        note: _note.text,
        enabled: widget.item?.enabled ?? true,
      );
      if (mounted) {
        setState(() {
          _done = true;
          _dirty = false;
        });
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_dirty || _done,
    onPopInvokedWithResult: (didPop, _) async {
      if (!didPop &&
          !_busy &&
          await confirm(context, '放弃这次修改？', '未保存的内容会丢失。', action: '放弃修改') &&
          context.mounted) {
        setState(() => _dirty = false);
        Navigator.pop(context);
      }
    },
    child: Scaffold(
      appBar: AppBar(title: Text(widget.item == null ? '添加选项' : '编辑选项')),
      body: PageBody(
        width: 560,
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TextFormField(
                controller: _title,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: '标题',
                  helperText: '1–100 个字',
                  errorText: _error,
                ),
                validator: (v) {
                  try {
                    checkedText(v ?? '', 100, required: true);
                    return null;
                  } catch (e) {
                    return errorMessage(e);
                  }
                },
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _note,
                enabled: !_busy,
                minLines: 4,
                maxLines: 12,
                decoration: const InputDecoration(
                  labelText: '备注',
                  helperText: '最多 300 个字',
                ),
                validator: (v) {
                  try {
                    checkedText(v ?? '', 300, multiline: true);
                    return null;
                  } catch (e) {
                    return errorMessage(e);
                  }
                },
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? '正在保存…' : '保存选项'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
