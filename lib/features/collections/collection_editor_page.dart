import 'package:flutter/material.dart';

import '../../app/ui.dart';
import '../../core/data/picker_store.dart';

class CollectionEditorPage extends StatefulWidget {
  const CollectionEditorPage({super.key, required this.store, this.collection});
  final PickerStore store;
  final Collection? collection;
  @override
  State<CollectionEditorPage> createState() => _CollectionEditorPageState();
}

class _CollectionEditorPageState extends State<CollectionEditorPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _description = TextEditingController(),
      _criterion = TextEditingController(),
      _initial = TextEditingController();
  String _icon = 'dice', _color = 'sage';
  DrawMode _mode = DrawMode.allowRepeat;
  PresentationStyle _style = PresentationStyle.gacha;
  bool _busy = false, _dirty = false, _done = false;
  @override
  void initState() {
    super.initState();
    final c = widget.collection;
    if (c != null) {
      _name.text = c.name;
      _description.text = c.description;
      _criterion.text = c.executionCriterion;
      _icon = c.iconKey;
      _color = c.colorKey;
      _mode = c.drawMode;
      _style = c.presentationStyle;
    }
    for (final t in [_name, _description, _criterion, _initial]) {
      t.addListener(() {
        if (mounted) setState(() => _dirty = true);
      });
    }
  }

  @override
  void dispose() {
    for (final t in [_name, _description, _criterion, _initial]) {
      t.dispose();
    }
    super.dispose();
  }

  Widget _field(
    TextEditingController t,
    String label,
    int max, {
    bool required = false,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: TextFormField(
      controller: t,
      minLines: lines,
      maxLines: lines == 1 ? 1 : 8,
      decoration: InputDecoration(labelText: label, helperText: '最多 $max 字'),
      validator: (v) {
        final n = (v ?? '').trim().characters.length;
        if (required && n == 0) return '请填写$label';
        if (n > max) return '$label不能超过 $max 字';
        return null;
      },
    ),
  );
  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      if (widget.collection == null && _initial.text.trim().isNotEmpty) {
        final lines = _initial.text.split(RegExp(r'\r\n|\n|\r'));
        final seen = <String>{};
        int blank = 0, duplicate = 0, valid = 0;
        for (final line in lines) {
          final title = normalized(line);
          if (title.isEmpty) {
            blank++;
          } else if (!seen.add(title)) {
            duplicate++;
          } else {
            valid++;
          }
        }
        if (!await confirm(
          context,
          '确认初始选项',
          '新增 $valid 项，空行 $blank，重复 $duplicate。重复和空行会跳过。',
          action: '创建集合',
        )) {
          return;
        }
      }
      await widget.store.saveCollection(
        id: widget.collection?.id,
        name: _name.text,
        description: _description.text,
        executionCriterion: _criterion.text,
        iconKey: _icon,
        colorKey: _color,
        drawMode: _mode,
        presentationStyle: _style,
        initialItems: _initial.text,
      );
      if (mounted) {
        _done = true;
        setState(() => _dirty = false);
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_dirty || _done,
    onPopInvokedWithResult: (didPop, result) async {
      if (!didPop &&
          !_busy &&
          await confirm(context, '放弃这次修改？', '未保存的内容会丢失。', action: '放弃修改') &&
          context.mounted) {
        setState(() => _dirty = false);
        Navigator.pop(context);
      }
    },
    child: Scaffold(
      appBar: AppBar(title: Text(widget.collection == null ? '新建集合' : '编辑集合')),
      body: PageBody(
        width: 560,
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                '把想做的事，轻轻收好。',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 24),
              _field(_name, '集合名称', 40, required: true),
              if (widget.collection == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: TextFormField(
                    controller: _initial,
                    minLines: 4,
                    maxLines: 10,
                    decoration: const InputDecoration(
                      labelText: '初始选项，每行一个',
                      helperText: '可稍后添加；每批最多 500 行',
                    ),
                  ),
                ),
              _field(_description, '描述', 200, lines: 2),
              _field(_criterion, '怎样算做过', 120, lines: 2),
              const Text('集合图标'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: collectionIcons.entries
                    .map(
                      (e) => IconButton.filledTonal(
                        isSelected: _icon == e.key,
                        tooltip: e.key,
                        onPressed: () => setState(() {
                          _icon = e.key;
                          _dirty = true;
                        }),
                        icon: Icon(e.value),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 20),
              const Text('主题色'),
              Wrap(
                spacing: 8,
                children: colorNames.entries
                    .map(
                      (e) => ChoiceChip(
                        label: Text(e.value),
                        selected: _color == e.key,
                        onSelected: (_) => setState(() {
                          _color = e.key;
                          _dirty = true;
                        }),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 24),
              DropdownButtonFormField<DrawMode>(
                initialValue: _mode,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '抽取规则'),
                items: DrawMode.values
                    .map(
                      (m) =>
                          DropdownMenuItem(value: m, child: Text(modeLabel(m))),
                    )
                    .toList(),
                onChanged: (v) => setState(() {
                  _mode = v!;
                  _dirty = true;
                }),
              ),
              const SizedBox(height: 12),
              Text(switch (_mode) {
                DrawMode.allowRepeat => '每次都从全部可用选项中抽取。',
                DrawMode.avoidPrevious => '多个可用选项时，避开上一次抽到的选项。',
                DrawMode.cycle => '整轮抽完后，手动开启新一轮。切回此规则会继续上次轮次。',
              }),
              const SizedBox(height: 24),
              DropdownButtonFormField<PresentationStyle>(
                initialValue: _style,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '展示方式'),
                items: const [
                  DropdownMenuItem(
                    value: PresentationStyle.gacha,
                    child: Text('扭蛋'),
                  ),
                  DropdownMenuItem(
                    value: PresentationStyle.instant,
                    child: Text('直接揭晓'),
                  ),
                ],
                onChanged: (v) => setState(() {
                  _style = v!;
                  _dirty = true;
                }),
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? '正在保存…' : '保存集合'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    ),
  );
}
