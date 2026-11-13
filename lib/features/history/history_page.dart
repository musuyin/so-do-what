import 'package:flutter/material.dart';

import '../../app/ui.dart';
import '../../core/data/picker_store.dart';
import '../drawing/record_result_page.dart' hide statusLabel;

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.store, this.collectionId});
  final PickerStore store;
  final String? collectionId;
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<DrawRecord> _records = [];
  List<Collection> _collections = [];
  String? _collection;
  RecordStatus? _status;
  String _query = '';
  bool _loading = true, _more = true;
  Object? _error;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    _collection = widget.collectionId;
    _init();
  }

  Future<void> _init() async {
    try {
      final a = await widget.store.listCollections();
      final b = await widget.store.listCollections(archived: true);
      if (mounted) setState(() => _collections = [...a, ...b]);
    } catch (e) {
      if (mounted) showError(context, e);
    }
    await _load();
  }

  Future<void> _load({bool append = false}) async {
    if (!mounted) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      if (!append) _records = [];
    });
    try {
      final data = await widget.store.history(
        collectionId: _collection,
        status: _status,
        search: _query,
        before: append && _records.isNotEmpty ? _records.last : null,
      );
      if (mounted && request == _request) {
        setState(() {
          _records = [if (append) ..._records, ...data];
          _more = data.length == 50;
        });
      }
    } catch (e) {
      if (mounted && request == _request) setState(() => _error = e);
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('记录')),
    body: PageBody(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            decoration: const InputDecoration(
              labelText: '搜索抽取时的标题',
              prefixIcon: Icon(Icons.search_rounded),
            ),
            onChanged: (v) {
              _query = v;
              _load();
            },
          ),
          const SizedBox(height: 16),
          if (_collections.isNotEmpty || _collection == null)
            DropdownButtonFormField<String>(
              key: ValueKey(_collection),
              initialValue: _collection,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '集合'),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('全部集合'),
                ),
                for (final c in _collections)
                  DropdownMenuItem(
                    value: c.id,
                    child: Row(
                      children: [
                        Icon(
                          collectionIcons[c.iconKey] ?? Icons.casino_rounded,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${c.name}${c.archived ? '（已归档）' : ''} · ${c.description.isEmpty ? '第 ${_collections.indexOf(c) + 1} 个集合' : c.description}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              onChanged: (v) {
                _collection = v;
                _load();
              },
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ChoiceChip(
                label: const Text('全部'),
                selected: _status == null,
                onSelected: (_) {
                  _status = null;
                  _load();
                },
              ),
              for (final s in RecordStatus.values)
                ChoiceChip(
                  label: Text(statusLabel(s)),
                  selected: _status == s,
                  onSelected: (_) {
                    _status = s;
                    _load();
                  },
                ),
            ],
          ),
          const SizedBox(height: 24),
          if (_records.isEmpty && !_loading && _error == null)
            BlankState(
              title: _query.isEmpty && _status == null
                  ? '抽出的结果会留在这里'
                  : '没有符合条件的记录',
            ),
          ..._rows(),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null)
            LoadError(
              error: _error!,
              retry: () => _load(append: _records.isNotEmpty),
            ),
          if (!_loading && _more && _records.isNotEmpty)
            OutlinedButton(
              onPressed: () => _load(append: true),
              child: const Text('加载更多'),
            ),
        ],
      ),
    ),
  );
  List<Widget> _rows() {
    String? last;
    final rows = <Widget>[];
    for (final r in _records) {
      final day = dateLabel(r.drawnAt);
      if (day != last) {
        rows.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(day, style: Theme.of(context).textTheme.titleMedium),
          ),
        );
        last = day;
      }
      rows.add(
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            title: Text(r.itemTitleSnapshot),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${r.collectionNameSnapshot} · ${timeLabel(r.drawnAt)}\n${statusLabel(r.status)}',
              ),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              await openPage(
                context,
                RecordResultPage(store: widget.store, record: r),
              );
              _load();
            },
          ),
        ),
      );
    }
    return rows;
  }
}
