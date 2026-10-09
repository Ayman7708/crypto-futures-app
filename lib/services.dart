import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ============ API SERVICE (with fallback) ============
class ApiService {
  static const _endpoints = [
    'https://fapi.binance.com/fapi/v1/ticker/price',
    'https://api.binance.com/api/v3/ticker/price',
    'https://api1.binance.com/api/v3/ticker/price',
    'https://api2.binance.com/api/v3/ticker/price',
    'https://api3.binance.com/api/v3/ticker/price',
  ];

  /// Fetch prices with automatic fallback
  static Future<Map<String, double>?> fetchPrices(List<String> symbols) async {
    for (final base in _endpoints) {
      try {
        final res = await http
            .get(Uri.parse(base))
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final List data = json.decode(res.body);
          final map = <String, double>{};
          for (final item in data) {
            final sym = item['symbol'] as String;
            if (symbols.contains(sym)) {
              map[sym] = double.parse(item['price'].toString());
            }
          }
          if (map.isNotEmpty) {
            debugPrint('✅ API OK: $base (${map.length} prices)');
            return map;
          }
        }
      } catch (e) {
        debugPrint('⚠️ API fail $base: $e');
      }
    }
    return null;
  }
}

// ============ STORAGE SERVICE ============
class StorageService {
  static const _kBalance = 'balance';
  static const _kPositions = 'positions';
  static const _kTrades = 'trades';
  static const _kSettings = 'settings';
  static const _kHistory = 'history';

  static Future<void> saveAll({
    required double balance,
    required Map<String, dynamic> positions,
    required List<dynamic> trades,
    required Map<String, dynamic> settings,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kBalance, balance);
    await p.setString(_kPositions, json.encode(positions));
    await p.setString(_kTrades, json.encode(trades));
    await p.setString(_kSettings, json.encode(settings));
  }

  static Future<Map<String, dynamic>?> loadAll() async {
    final p = await SharedPreferences.getInstance();
    if (!p.containsKey(_kBalance)) return null;
    return {
      'balance': p.getDouble(_kBalance) ?? 1000.0,
      'positions': json.decode(p.getString(_kPositions) ?? '{}'),
      'trades': json.decode(p.getString(_kTrades) ?? '[]'),
      'settings': json.decode(p.getString(_kSettings) ?? '{}'),
    };
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.clear();
  }

  // Historical prices for backtest
  static Future<void> saveHistory(Map<String, List<double>> history) async {
    final p = await SharedPreferences.getInstance();
    final encoded = history.map((k, v) => MapEntry(k, v.map((e) => e.toString()).toList()));
    await p.setString(_kHistory, json.encode(encoded));
  }

  static Future<Map<String, List<double>>> loadHistory() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kHistory);
    if (raw == null) return {};
    final Map<String, dynamic> decoded = json.decode(raw);
    return decoded.map((k, v) => MapEntry(k, (v as List).map((e) => double.parse(e.toString())).toList()));
  }
}

// ============ NOTIFICATION SERVICE ============
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);

    // Request permission on Android 13+
    final android12 = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android12 != null) {
      await android12.requestNotificationsPermission();
    }
    _initialized = true;
  }

  static Future<void> show(String title, String body, {bool isAlert = false}) async {
    await init();
    const android = AndroidNotificationDetails(
      'crypto_bot_channel', 'Crypto Bot',
      channelDescription: 'Trade notifications',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      styleInformation: BigTextStyleInformation(''),
    );
    const details = NotificationDetails(android: android);
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title, body, details,
    );
  }
}
