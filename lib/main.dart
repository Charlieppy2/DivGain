import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/database_factory_setup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureDatabaseFactory();
  runApp(const ProviderScope(child: DivGainApp()));
}
