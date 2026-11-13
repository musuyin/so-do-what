import 'package:flutter/material.dart';

import '../core/domain/models.dart';

const collectionIcons = <String, IconData>{
  'dice': Icons.casino_rounded,
  'movie': Icons.movie_rounded,
  'book': Icons.menu_book_rounded,
  'game': Icons.sports_esports_rounded,
  'food': Icons.restaurant_rounded,
  'walk': Icons.directions_walk_rounded,
  'music': Icons.music_note_rounded,
  'star': Icons.star_rounded,
};
const colorNames = <String, String>{
  'sage': '鼠尾草',
  'lavender': '雾紫',
  'sky': '晴空',
  'peach': '浅桃',
};
String modeLabel(DrawMode m) => switch (m) {
  DrawMode.allowRepeat => '允许重复',
  DrawMode.avoidPrevious => '仅避免连续重复',
  DrawMode.cycle => '整轮不重复',
};
String statusLabel(RecordStatus s) => switch (s) {
  RecordStatus.pending => '待行动',
  RecordStatus.completed => '已做过',
  RecordStatus.skipped => '这次不做',
};
String dateLabel(DateTime d) {
  final t = d.toLocal();
  return '${t.year}年${t.month}月${t.day}日';
}

String timeLabel(DateTime d) {
  final t = d.toLocal();
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

String errorMessage(Object error) =>
    error is AppFailure ? error.message : '暂时无法读取或保存，请检查设备剩余空间后重试。';

void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(errorMessage(error))));
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  String action = '确认',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;
Future<T?> openPage<T>(BuildContext context, Widget page) =>
    Navigator.push<T>(context, MaterialPageRoute(builder: (_) => page));

class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.child, this.width = 960});
  final Widget child;
  final double width;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: child,
    ),
  );
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(padding: const EdgeInsets.all(20), child: child),
  );
}

class BlankState extends StatelessWidget {
  const BlankState({super.key, required this.title, this.detail, this.action});
  final String title;
  final String? detail;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.bubble_chart_rounded,
          size: 64,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (detail != null) ...[
          const SizedBox(height: 12),
          Text(detail!, textAlign: TextAlign.center),
        ],
        if (action != null) ...[const SizedBox(height: 24), action!],
      ],
    ),
  );
}

class LoadError extends StatelessWidget {
  const LoadError({super.key, required this.error, required this.retry});
  final Object error;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => BlankState(
    title: '暂时无法读取',
    detail: errorMessage(error),
    action: OutlinedButton(onPressed: retry, child: const Text('重试')),
  );
}

ThemeData pickerTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final primary = Color(dark ? 0xffb7d2ba : 0xff355b49);
  final surface = Color(dark ? 0xff252b27 : 0xfffffcf7);
  final text = Color(dark ? 0xfff2f0e9 : 0xff26372f);
  final scheme =
      ColorScheme.fromSeed(seedColor: primary, brightness: brightness).copyWith(
        primary: primary,
        onPrimary: Color(dark ? 0xff26372f : 0xfffffcf7),
        surface: surface,
        onSurface: text,
        onSurfaceVariant: Color(dark ? 0xffb5bdb5 : 0xff626c64),
        outline: Color(dark ? 0xff465148 : 0xffdadfd4),
        error: Color(dark ? 0xfff1b3ae : 0xff963f3f),
      );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: Color(dark ? 0xff191d1b : 0xfff7f3ec),
    appBarTheme: AppBarTheme(
      backgroundColor: Color(dark ? 0xff191d1b : 0xfff7f3ec),
      foregroundColor: text,
      centerTitle: false,
      scrolledUnderElevation: 0,
    ),
    textTheme: TextTheme(
      headlineMedium: TextStyle(
        fontSize: 28,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: text,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: text,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: text),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: scheme.outline),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      contentPadding: const EdgeInsets.all(16),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: dark ? const Color(0xff303a32) : const Color(0xffe8eee5),
    ),
  );
}
