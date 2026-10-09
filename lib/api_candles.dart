import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class Kline {
  final int time;
  final double open, high, low, close, volume;
  Kline({
    required this.time, required this.open, required this.high,
    required this.low, required this.close, required this.volume,
  });
}

class CandleService {
  static const _endpoints = [
    'https://fapi.binance.com/fapi/v1/klines',
    'https://api.binance.com/api/v3/klines',
  ];

  static Future<List<Kline>?> fetchCandles(
    String symbol, {
    String interval = '1m',
    int limit = 100,
  }) async {
    for (final base in _endpoints) {
      try {
        final url = Uri.parse('$base?symbol=$symbol&interval=$interval&limit=$limit');
        final res = await http.get(url).timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final List<dynamic> data = json.decode(res.body);
          final List<Kline> result = [];
          for (final item in data) {
            result.add(Kline(
              time: item[0] as int,
              open: double.parse(item[1].toString()),
              high: double.parse(item[2].toString()),
              low: double.parse(item[3].toString()),
              close: double.parse(item[4].toString()),
              volume: double.parse(item[5].toString()),
            ));
          }
          return result;
        }
      } catch (e) {
        debugPrint('Candle fail $base: $e');
      }
    }
    return null;
  }

  static Future<Map<String, List<Kline>>?> fetchAll(List<String> symbols) async {
    final out = <String, List<Kline>>{};
    for (final s in symbols) {
      final c = await fetchCandles(s);
      if (c != null && c.isNotEmpty) out[s] = c;
      await Future.delayed(const Duration(milliseconds: 80));
    }
    return out.isEmpty ? null : out;
  }
}
