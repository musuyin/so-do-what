import 'package:flutter/material.dart';

import '../../app/ui.dart';
import '../../core/data/picker_store.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key, required this.store, this.collectionId});
  final PickerStore store;
  final String? collectionId;
  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  String? _selected;
  late Future<Summary> _data;
  List<Collection> _collections = [];
  @override
  void initState() {
    super.initState();
    _selected = widget.collectionId;
    _load();
    _init();
  }

  void _load() {
    _data = widget.store.summary(collectionId: _selected);
  }

  Future<void> _init() async {
    try {
      final a = await widget.store.listCollections();
      final b = await widget.store.listCollections(archived: true);
      if (mounted) {
        setState(
          () =>
              _collections = [...a, ...b]
                ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('回顾')),
    body: PageBody(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('看看抽到的事，有多少成为了行动。'),
          const SizedBox(height: 24),
          if (_collections.isNotEmpty || _selected == null)
            DropdownButtonFormField<String>(
              key: ValueKey(_selected),
              initialValue: _selected,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '查看范围'),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('全部集合'),
                ),
                for (final c in _collections)
                  DropdownMenuItem(
                    value: c.id,
                    child: Text(
                      '${c.name}${c.archived ? '（已归档）' : ''}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) => setState(() {
                _selected = v;
                _load();
              }),
            ),
          const SizedBox(height: 24),
          FutureBuilder<Summary>(
            future: _data,
            builder: (c, s) {
              if (s.hasError) {
                return LoadError(error: s.error!, retry: () => setState(_load));
              }
              if (!s.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final d = s.data!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('执行率'),
                        const SizedBox(height: 12),
                        Text(
                          d.rateLabel,
                          style: Theme.of(context).textTheme.displayMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          d.total == 0
                              ? '还没有抽取记录'
                              : '已做过 ${d.completed} 次 / 共抽取 ${d.total} 次',
                        ),
                        if (d.rate != null) ...[
                          const SizedBox(height: 20),
                          LinearProgressIndicator(
                            value: d.rate,
                            minHeight: 5,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _metric('总抽取', d.total),
                      _metric('已做过', d.completed),
                      _metric('待行动', d.pending),
                      _metric('这次不做', d.skipped),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 32),
          Text('每个集合的小记', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          for (final col in _collections)
            FutureBuilder<Summary>(
              future: widget.store.summary(collectionId: col.id),
              builder: (c, s) => Card(
                child: ListTile(
                  title: Text('${col.name}${col.archived ? '（已归档）' : ''}'),
                  subtitle: Text(
                    s.hasData
                        ? '共 ${s.data!.total} 次 · 已做过 ${s.data!.completed} 次'
                        : '正在读取…',
                  ),
                  trailing: Text(s.data?.rateLabel ?? '—'),
                ),
              ),
            ),
        ],
      ),
    ),
  );
  Widget _metric(String label, int value) => SizedBox(
    width:
        MediaQuery.sizeOf(context).width < 400 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.4
        ? double.infinity
        : 200,
    child: SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 8),
          Text('$value', style: Theme.of(context).textTheme.headlineMedium),
        ],
      ),
    ),
  );
}
