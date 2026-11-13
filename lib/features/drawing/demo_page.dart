import 'package:flutter/material.dart';

import 'gacha_machine.dart';

/// Deliberately isolated: no store, database, or application settings dependency.
class DemoPage extends StatefulWidget {
  const DemoPage({super.key});
  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _animation;
  static const _titles = ['散步十分钟', '整理书桌', '听一首歌'];
  int _index = -1;
  bool _presenting = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _animation =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 1850),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) _reveal();
        });
  }

  void _reveal() {
    if (!mounted) return;
    _animation.stop();
    setState(() => _presenting = false);
  }

  void _draw() {
    setState(() {
      _index = (_index + 1) % _titles.length;
      _presenting = true;
    });
    if (MediaQuery.disableAnimationsOf(context)) {
      _reveal();
    } else {
      _animation.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) && _presenting) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_presenting && state != AppLifecycleState.resumed) _reveal();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('体验一下 · 演示')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text('把想做的事装进来，抽一个开始。', textAlign: TextAlign.center),
            const SizedBox(height: 20),
            Center(
              child: AnimatedBuilder(
                animation: _animation,
                builder: (_, _) => GachaMachine(progress: _animation.value),
              ),
            ),
            if (_index >= 0 && !_presenting) ...[
              const Text('这次抽到', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                _titles[_index],
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 24),
            ],
            FilledButton(
              onPressed: _presenting ? _reveal : _draw,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  _presenting
                      ? '跳过动画'
                      : _index < 0
                      ? '体验抽一个'
                      : '再体验一次',
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '这是独立的演示，不会添加集合、抽取记录或影响回顾。',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}
