import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/domain/models.dart';
import 'gacha_machine.dart';

/// Presents a committed record. It has no access to persistence or randomness.
class GachaPresentation extends StatefulWidget {
  const GachaPresentation({
    super.key,
    required this.record,
    required this.settings,
    required this.onReveal,
    this.onFeedbackPolicy,
  });
  final DrawRecord record;
  final PickerSettings settings;
  final VoidCallback onReveal;
  final ValueChanged<bool>? onFeedbackPolicy;
  @override
  State<GachaPresentation> createState() => _GachaPresentationState();
}

class _GachaPresentationState extends State<GachaPresentation>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _animation;
  AudioPlayer? _player;
  bool _revealed = false;
  bool _foreground = true;
  bool _wasBackgrounded = false;
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _revealed) return;
      if (_reduced ||
          widget.record.styleSnapshot == PresentationStyle.instant) {
        _reveal();
      } else {
        unawaited(_feedback('turn'));
        _animation.forward();
      }
    });
  }

  bool get _reduced =>
      widget.settings.reduceMotion || MediaQuery.disableAnimationsOf(context);
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduced) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reveal();
      });
    }
  }

  Future<void> _feedback(String name) async {
    if (!_foreground) return;
    try {
      if (widget.settings.hapticsEnabled) await HapticFeedback.lightImpact();
      if (!_foreground || !mounted || !widget.settings.soundEnabled) return;
      _player ??= AudioPlayer();
      await _player!.play(AssetSource('sounds/$name.wav'), volume: .35);
    } catch (_) {
      /* Optional feedback never affects a committed draw. */
    }
  }

  void _reveal() {
    if (_revealed || !mounted || !_foreground) return;
    _revealed = true;
    _animation.stop();
    widget.onFeedbackPolicy?.call(!_wasBackgrounded);
    widget.onReveal();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _wasBackgrounded = true;
      _animation.stop();
      unawaited(_player?.stop() ?? Future<void>.value());
    } else {
      _reveal();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animation.dispose();
    unawaited(_player?.dispose() ?? Future<void>.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: true,
    child: Scaffold(
      appBar: AppBar(title: Text(widget.record.collectionNameSnapshot)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _animation,
                builder: (_, _) =>
                    GachaMachine(progress: _reduced ? 0 : _animation.value),
              ),
              const SizedBox(height: 20),
              const Text('让下一件小事，慢慢出现。'),
              const SizedBox(height: 24),
              TextButton(onPressed: _reveal, child: const Text('跳过动画')),
            ],
          ),
        ),
      ),
    ),
  );
}
