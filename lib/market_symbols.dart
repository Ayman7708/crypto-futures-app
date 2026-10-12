import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class MarketSymbol {
  final String symbol;
  final double volume24h;
  final double price;
  final double change24hPct;
  MarketSymbol({
    required this.symbol,
    required this.volume24h,
    required this.price,
    required this.change24hPct,
  });
}

class MarketService {
  static const _exchangeUrl = 'https://fapi.binance.com/fapi/v1/exchangeInfo';
  static const _tickerUrl = 'https://fapi.binance.com/fapi/v1/ticker/24hr';

  /// Fetch all USDT perpetual futures symbols sorted by 24h volume.
  static Future<List<String>?> fetchAllSymbols({double minVolumeUsdt = 50000000}) async {
    try {
      // Step 1: get list of all futures symbols
      final res1 = await http.get(Uri.parse(_exchangeUrl))
          .timeout(const Duration(seconds: 15));
      if (res1.statusCode != 200) return null;
      final info = json.decode(res1.body);
      final validSymbols = <String>{};
      for (final s in (info['symbols'] as List)) {
        final status = s['status'];
        final contractType = s['contractType'];
        final quote = s['quoteAsset'];
        final symbol = s['symbol'];
        if (status == 'TRADING' && contractType == 'PERPETUAL' && quote == 'USDT') {
          validSymbols.add(symbol as String);
        }
      }
      debugPrint('📊 Binance has ${validSymbols.length} USDT perpetuals');

      // Step 2: get 24h ticker for volume sorting
      final res2 = await http.get(Uri.parse(_tickerUrl))
          .timeout(const Duration(seconds: 15));
      if (res2.statusCode != 200) return null;
      final tickers = json.decode(res2.body) as List;

      final candidates = <MarketSymbol>[];
      for (final t in tickers) {
        final sym = t['symbol'] as String;
        if (!validSymbols.contains(sym)) continue;
        final vol = double.tryParse(t['quoteVolume'].toString()) ?? 0;
        final price = double.tryParse(t['lastPrice'].toString()) ?? 0;
        final change = double.tryParse(t['priceChangePercent'].toString()) ?? 0;
        if (vol < minVolumeUsdt) continue;
        if (price <= 0) continue;
        candidates.add(MarketSymbol(
          symbol: sym, volume24h: vol, price: price, change24hPct: change,
        ));
      }

      // Sort by 24h volume desc
      candidates.sort((a, b) => b.volume24h.compareTo(a.volume24h));
      final top = candidates.take(60).map((c) => c.symbol).toList();
      debugPrint('✅ Selected ${top.length} top-volume symbols');
      return top;
    } catch (e) {
      debugPrint('❌ MarketService error: $e');
      return null;
    }
  }
}
