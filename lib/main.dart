import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'app/app.dart';
import 'app/ui.dart';
import 'core/data/database_recovery.dart';
import 'core/data/picker_store.dart';
import 'features/settings/startup_recovery_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _Bootstrap());
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();
  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  String? _path;
  late Future<PickerStore> _opening = _open();
  Future<PickerStore> _open() async {
    final path = p.join(await getDatabasesPath(), 'so_do_what.db');
    _path = path;
    await DatabaseRecovery().recoverInterrupted(path);
    return PickerStore.open(path: path);
  }

  void _retry() => setState(() => _opening = _open());
  @override
  Widget build(BuildContext context) => FutureBuilder<PickerStore>(
    future: _opening,
    builder: (context, snapshot) {
      if (snapshot.hasData) return PickerApp(store: snapshot.data!);
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: pickerTheme(Brightness.light),
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('zh', 'CN')],
        home: snapshot.hasError && _path != null
            ? StartupRecoveryPage(
                databasePath: _path!,
                error: snapshot.error,
                onRetry: _retry,
                onRecovered: _retry,
              )
            : Scaffold(
                body: Center(
                  child: snapshot.hasError
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('暂时无法访问设备存储，请检查剩余空间后重试。'),
                              const SizedBox(height: 24),
                              FilledButton(
                                onPressed: _retry,
                                child: const Text('重新打开'),
                              ),
                            ],
                          ),
                        )
                      : const CircularProgressIndicator(),
                ),
              ),
      );
    },
  );
}
