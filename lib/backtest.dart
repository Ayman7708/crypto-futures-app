import 'api_candles.dart';
import 'engine.dart';
import 'indicators.dart';

/// BacktestResult - outcome of running strategy on historical data
class BacktestResult {
  final String symbol;
  final int totalTrades;
  final int wins;
  final int losses;
  final double finalBalance;
  final double maxDrawdown;
  final double profitFactor;
  final List<BacktestTrade> trades;

  BacktestResult({
    required this.symbol,
    required this.totalTrades,
    required this.wins,
    required this.losses,
    required this.finalBalance,
    required this.maxDrawdown,
    required this.profitFactor,
    required this.trades,
  });

  double get winRate => totalTrades == 0 ? 0 : (wins / totalTrades * 100);
  double get profitPct => (finalBalance - 1000) / 1000 * 100;
  bool get isProfitable => finalBalance > 1000;
}

class BacktestTrade {
  final String direction;
  final double entry;
  final double exit;
  final double pnl;
  final String reason;
  final DateTime entryTime;
  final DateTime exitTime;

  BacktestTrade({
    required this.direction,
    required this.entry,
    required this.exit,
    required this.pnl,
    required this.reason,
    required this.entryTime,
    required this.exitTime,
  });
}

class BacktestEngine {
  /// Run backtest on historical data
  ///
  /// Strategy: V9 (4h trend + 1h entry)
  /// Rules:
  ///   - SL = 1.5 × ATR
  ///   - TP = 3 × ATR
  ///   - Risk 1% of balance per trade
  ///   - Max 3 positions
  ///   - Max 10 trades/day
  static Future<BacktestResult?> run({
    required String symbol,
    int daysToTest = 30,
    double initialBalance = 1000,
    int leverage = 3,
    double riskPct = 0.01,
  }) async {
    // Fetch 4h candles (need ~200 for EMA200)
    final candles4h = await CandleService.fetchCandles(
      symbol,
      interval: '4h',
      limit: 500,
    );
    if (candles4h == null || candles4h.length < 220) return null;

    // Fetch 1h candles
    final candles1h = await CandleService.fetchCandles(
      symbol,
      interval: '1h',
      limit: 1000,
    );
    if (candles1h == null || candles1h.length < 100) return null;

    // Prepare arrays
    final closes4h = candles4h.map((c) => c.close).toList();
    final closes1h = candles1h.map((c) => c.close).toList();
    final highs1h = candles1h.map((c) => c.high).toList();
    final lows1h = candles1h.map((c) => c.low).toList();
    final volumes1h = candles1h.map((c) => c.volume).toList();
    final times1h = candles1h.map((c) => DateTime.fromMillisecondsSinceEpoch(c.time)).toList();

    double balance = initialBalance;
    double peak = initialBalance;
    double maxDD = 0;
    double grossProfit = 0;
    double grossLoss = 0;
    final trades = <BacktestTrade>[];
    Position? openPos;
    int tradesToday = 0;
    DateTime currentDay = times1h.first;

    // Start from candle 220 (need enough history for EMA200)
    for (int i = 220; i < closes1h.length; i++) {
      final now = times1h[i];
      final price = closes1h[i];

      // Reset daily trade counter
      if (now.day != currentDay.day) {
        currentDay = now;
        tradesToday = 0;
      }

      // ============ CHECK OPEN POSITION ============
      if (openPos != null) {
        final slHit = openPos.isLong
            ? price <= openPos.stopLoss
            : price >= openPos.stopLoss;
        final tpHit = openPos.isLong
            ? price >= openPos.takeProfit
            : price <= openPos.takeProfit;

        if (slHit || tpHit) {
          final exitPrice = slHit ? openPos.stopLoss : openPos.takeProfit;
          final pnl = openPos.isLong
              ? (exitPrice - openPos.entry) * openPos.size
              : (openPos.entry - exitPrice) * openPos.size;

          balance += openPos.margin + pnl;
          if (pnl > 0) {
            grossProfit += pnl;
          } else {
            grossLoss += pnl.abs();
          }

          trades.add(BacktestTrade(
            direction: openPos.isLong ? 'LONG' : 'SHORT',
            entry: openPos.entry,
            exit: exitPrice,
            pnl: pnl,
            reason: slHit ? 'SL' : 'TP',
            entryTime: openPos.openedAt,
            exitTime: now,
          ));

          openPos = null;
        }
      }

      // ============ LOOK FOR NEW ENTRY ============
      if (openPos == null && tradesToday < 10 && balance > 10) {
        // Compute 4h trend (use all available data up to current 1h time)
        final trend = _computeTrendAtIndex(closes4h, i);

        if (trend != 'NEUTRAL' && trend != 'NONE') {
          // Build 1h subset (only data before now)
          final idx1h = i + 1;
          if (idx1h >= 50) {
            final c1 = closes1h.sublist(0, idx1h);
            final h1 = highs1h.sublist(0, idx1h);
            final l1 = lows1h.sublist(0, idx1h);
            final v1 = volumes1h.sublist(0, idx1h);

            final signal = StrategyAnalyzer.analyze(
              symbol: symbol,
              closes1h: c1,
              highs1h: h1,
              lows1h: l1,
              volumes1h: v1,
              trend: trend,
              leverage: leverage,
              balance: balance,
              riskPct: riskPct,
            );

            if (signal.isValid) {
              // Calculate position size
              final slDistPct = (signal.entry - signal.stopLoss).abs() / signal.entry;
              if (slDistPct > 0.001) {
                final riskUsdt = balance * riskPct;
                final posValue = riskUsdt / slDistPct;
                final margin = posValue / leverage;
                final size = posValue / signal.entry;

                if (margin <= balance * 0.15) {
                  openPos = Position(
                    symbol: symbol,
                    entry: signal.entry,
                    size: size,
                    margin: margin,
                    stopLoss: signal.stopLoss,
                    takeProfit: signal.takeProfit,
                    leverage: leverage,
                    isLong: signal.direction == 'LONG',
                    openedAt: now,
                  );
                  balance -= margin;
                  tradesToday++;
                }
              }
            }
          }
        }
      }

      // Track drawdown
      if (balance > peak) peak = balance;
      final dd = (peak - balance) / peak * 100;
      if (dd > maxDD) maxDD = dd;
    }

    // Close any open position at end
    if (openPos != null) {
      final price = closes1h.last;
      final pnl = openPos.isLong
          ? (price - openPos.entry) * openPos.size
          : (openPos.entry - price) * openPos.size;
      balance += openPos.margin + pnl;
      trades.add(BacktestTrade(
        direction: openPos.isLong ? 'LONG' : 'SHORT',
        entry: openPos.entry,
        exit: price,
        pnl: pnl,
        reason: 'END',
        entryTime: openPos.openedAt,
        exitTime: times1h.last,
      ));
    }

    final wins = trades.where((t) => t.pnl > 0).length;
    final losses = trades.where((t) => t.pnl < 0).length;
    final pf = grossLoss == 0 ? (grossProfit > 0 ? 999.0 : 0.0) : grossProfit / grossLoss;

    return BacktestResult(
      symbol: symbol,
      totalTrades: trades.length,
      wins: wins,
      losses: losses,
      finalBalance: balance,
      maxDrawdown: maxDD,
      profitFactor: pf,
      trades: trades,
    );
  }

  /// Compute 4h trend using data up to given index
  /// idx1h: current index in 1h candles (0-based)
  /// Since 1h * 4 = 4h, index4h = idx1h ~/ 4
  static String _computeTrendAtIndex(List<double> closes4h, int idx1h) {
    final idx4h = idx1h ~/ 4;
    if (idx4h < 200) return 'NEUTRAL';

    // Get closes up to idx4h
    final subset = closes4h.sublist(0, idx4h + 1);
    final ema200 = Ind.ema(subset, 200);
    if (ema200 == null || subset.isEmpty) return 'NEUTRAL';

    final price = subset.last;
    if (price > ema200 * 1.005) return 'BULL';
    if (price < ema200 * 0.995) return 'BEAR';
    return 'NEUTRAL';
  }

  /// Run backtest on multiple symbols in parallel
  static Future<List<BacktestResult>> runAll({
    required List<String> symbols,
    int daysToTest = 30,
  }) async {
    final results = <BacktestResult>[];
    for (final sym in symbols) {
      try {
        final r = await run(symbol: sym, daysToTest: daysToTest);
        if (r != null) results.add(r);
        await Future.delayed(const Duration(milliseconds: 200));
      } catch (_) {}
    }
    return results;
  }
}
