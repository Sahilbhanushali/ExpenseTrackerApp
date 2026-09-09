import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

import '../models/app_config.dart';

/// Port of expense_bot/bot.py's load_config/save_config — same JSON shape
/// as config.json, minus telegram_token (no bot here). Config is re-read
/// on every access, same as the bot re-reading it on every message.
class ConfigRepository {
  File? _file;

  Future<File> _configFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationDocumentsDirectory();
    _file = File(join(dir.path, 'config.json'));
    return _file!;
  }

  Future<AppConfig> load() async {
    final file = await _configFile();
    if (!await file.exists()) {
      const defaultConfig = AppConfig();
      await save(defaultConfig);
      return defaultConfig;
    }
    final text = await file.readAsString();
    final json = jsonDecode(text) as Map<String, dynamic>;
    final config = AppConfig.fromJson(json);
    // Persist the rupees→paise conversion so it only ever runs once.
    if (((json['schema'] as num?)?.toInt() ?? 1) < AppConfig.schemaVersion) {
      await save(config);
    }
    return config;
  }

  Future<void> save(AppConfig config) async {
    final file = await _configFile();
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString('${encoder.convert(config.toJson())}\n');
  }
}
