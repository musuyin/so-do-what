import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/data/picker_store.dart';
import '../features/collections/collections_page.dart';
import '../features/history/history_page.dart';
import '../features/review/review_page.dart';
import '../features/settings/settings_page.dart';
import 'ui.dart';

class PickerApp extends StatefulWidget {
  const PickerApp({super.key, required this.store});
  final PickerStore store;
  @override
  State<PickerApp> createState() => _PickerAppState();
}

class _PickerAppState extends State<PickerApp> {
  ThemeMode _theme = ThemeMode.system;
  int _generation = 0;
  final _navKey = GlobalKey<NavigatorState>();
  @override
  void initState() {
    super.initState();
    _refreshSettings();
  }

  Future<void> _refreshSettings() async {
    final s = await widget.store.settings();
    if (mounted) {
      setState(
        () => _theme = s.themeMode == 'dark'
            ? ThemeMode.dark
            : s.themeMode == 'light'
            ? ThemeMode.light
            : ThemeMode.system,
      );
    }
  }

  void _reset() {
    _navKey.currentState?.popUntil((r) => r.isFirst);
    setState(() => _generation++);
    _refreshSettings();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '随手抽',
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    debugShowCheckedModeBanner: false,
    navigatorKey: _navKey,
    theme: pickerTheme(Brightness.light),
    darkTheme: pickerTheme(Brightness.dark),
    themeMode: _theme,
    home: AppShell(
      key: ValueKey(_generation),
      store: widget.store,
      onSettings: (context) => openPage(
        context,
        SettingsPage(
          store: widget.store,
          onSettingsChanged: _refreshSettings,
          onReset: _reset,
        ),
      ),
    ),
  );
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.store, required this.onSettings});
  final PickerStore store;
  final void Function(BuildContext) onSettings;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: KeyedSubtree(
      key: ValueKey(_index),
      child: switch (_index) {
        0 => CollectionsPage(
          store: widget.store,
          onSettings: () => widget.onSettings(context),
        ),
        1 => HistoryPage(store: widget.store),
        _ => ReviewPage(store: widget.store),
      },
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (i) => setState(() => _index = i),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.grid_view_rounded), label: '集合'),
        NavigationDestination(icon: Icon(Icons.history_rounded), label: '记录'),
        NavigationDestination(
          icon: Icon(Icons.pie_chart_outline_rounded),
          label: '回顾',
        ),
      ],
    ),
  );
}
