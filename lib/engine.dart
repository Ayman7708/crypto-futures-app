import 'indicators.dart';

/// Position - opened trade
class Position {
  final String symbol;
  final double entry;
  final double size;        // contract quantity
  final double margin;      // USDT margin used
  final double stopLoss;
  final double takeProfit;
  final int leverage;
  final bool isLong;
  final DateTime openedAt;

  Position({
    required this.symbol,
    required this.entry,
    required this.size,
    required this.margin,
    required this.stopLoss,
    required this.takeProfit,
    required this.leverage,
    this.isLong = true,
    DateTime? openedAt,
  }) : openedAt = openedAt ?? DateTime.now();

  double pnl(double current) => isLong
      ? (current - entry) * size
      : (entry - current) * size;

  double get liquidationPrice => isLong
      ? entry * (1 - 1 / leverage)
      : entry * (1 + 1 / leverage);

  Map<String, dynamic> toJson() => {
        'symbol': symbol,
        'entry': entry,
        'size': size,
        'margin': margin,
        'stopLoss': stopLoss,
        'takeProfit': takeProfit,
        'leverage': leverage,
        'isLong': isLong,
        'openedAt': openedAt.toIso8601String(),
      };

  factory Position.fromJson(Map<String, dynamic> j) => Position(
        symbol: j['symbol'],
        entry: (j['entry'] as num).toDouble(),
        size: (j['size'] as num).toDouble(),
        margin: (j['margin'] as num).toDouble(),
        stopLoss: (j['stopLoss'] as num).toDouble(),
        takeProfit: (j['takeProfit'] as num).toDouble(),
        leverage: (j['leverage'] as num).toInt(),
        isLong: j['isLong'] ?? true,
        openedAt: DateTime.tryParse(j['openedAt'] ?? '') ?? DateTime.now(),
      );
}

/// TradeRecord - closed trade log
class TradeRecord {
  final String symbol;
  final String action;   // BUY, SELL, STOP_LOSS, TAKE_PROFIT, MANUAL
  final double price;
  final double pnl;
  final DateTime time;
  final bool isLong;

  TradeRecord({
    required this.symbol,
    required this.action,
    required this.price,
    required this.pnl,
    required this.time,
    this.isLong = true,
  });

  Map<String, dynamic> toJson() => {
        'symbol': symbol,
        'action': action,
        'price': price,
        'pnl': pnl,
        'time': time.toIso8601String(),
        'isLong': isLong,
      };

  factory TradeRecord.fromJson(Map<String, dynamic> j) => TradeRecord(
        symbol: j['symbol'],
        action: j['action'],
        price: (j['price'] as num).toDouble(),
        pnl: (j['pnl'] as num).toDouble(),
        time: DateTime.tryParse(j['time'] ?? '') ?? DateTime.now(),
        isLong: j['isLong'] ?? true,
      );
}

/// Signal - entry decision
class Signal {
  final String symbol;
  final String direction;   // LONG, SHORT, NONE
  final int score;          // 0-100 confidence
  final double entry;       // suggested entry price
  final double stopLoss;    // suggested SL
  final double takeProfit;  // suggested TP
  final String reason;      // why

  Signal({
    required this.symbol,
    required this.direction,
    required this.score,
    required this.entry,
    required this.stopLoss,
    required this.takeProfit,
    required this.reason,
  });

  bool get isValid => direction != 'NONE' && score >= 50;
}

/// StrategyAnalyzer - V9 logic
/// 4h trend + 1h entry + RSI confirmation + Volume
class StrategyAnalyzer {
  /// Analyze 4h candles for overall trend
  static String trend4h({
    required List<double> closes4h,
  }) {
    final ema200 = Ind.ema(closes4h, 200);
    if (ema200 == null || closes4h.isEmpty) return 'NONE';
    final price = closes4h.last;
    if (price > ema200 * 1.005) return 'BULL';
    if (price < ema200 * 0.995) return 'BEAR';
    return 'NEUTRAL';
  }

  /// Analyze 1h candles for entry timing
  static Signal analyze({
    required String symbol,
    required List<double> closes1h,
    required List<double> highs1h,
    required List<double> lows1h,
    required List<double> volumes1h,
    required String trend,
    required int leverage,
    required double balance,
    required double riskPct,
  }) {
    if (closes1h.length < 50) {
      return Signal(
        symbol: symbol, direction: 'NONE', score: 0,
        entry: 0, stopLoss: 0, takeProfit: 0,
        reason: 'بيانات غير كافية',
      );
    }

    final price = closes1h.last;
    final ema50 = Ind.ema(closes1h, 50);
    final rsi = Ind.rsi(closes1h, 14);
    final atr = Ind.atr(highs1h, lows1h, closes1h, 14);
    final vs = Ind.volumeSurge(volumes1h, 20);

    if (ema50 == null || rsi == null || atr == 0) {
      return Signal(
        symbol: symbol, direction: 'NONE', score: 0,
        entry: 0, stopLoss: 0, takeProfit: 0,
        reason: 'مؤشرات غير جاهزة',
      );
    }

    int score = 0;
    final reasons = <String>[];

    // ========== LONG setup ==========
    if (trend == 'BULL') {
      // Condition 1: price above EMA50 (uptrend in 1h)
      if (price > ema50) {
        score += 25;
        reasons.add('فوق EMA50');
      }

      // Condition 2: RSI in recovery zone (30-55)
      if (rsi >= 30 && rsi <= 55) {
        score += 25;
        reasons.add('RSI=${rsi.toStringAsFixed(0)}');
      } else if (rsi > 55 && rsi < 70) {
        score += 10;
        reasons.add('RSI=${rsi.toStringAsFixed(0)}');
      }

      // Condition 3: Price near EMA50 (pullback)
      final distPct = (price - ema50) / ema50 * 100;
      if (distPct >= -1.5 && distPct <= 2.5) {
        score += 20;
        reasons.add('قرب EMA50');
      }

      // Condition 4: Volume surge
      if (vs > 1.3) {
        score += 20;
        reasons.add('حجم ×${vs.toStringAsFixed(1)}');
      }

      // Condition 5: RSI momentum up
      if (closes1h.length >= 3) {
        final rsiPrev = Ind.rsi(closes1h.sublist(0, closes1h.length - 1), 14);
        if (rsiPrev != null && rsi > rsiPrev) {
          score += 10;
          reasons.add('RSI↑');
        }
      }

      if (score >= 60) {
        final sl = price - atr * 1.5;
        final tp = price + atr * 3.0;
        return Signal(
          symbol: symbol, direction: 'LONG', score: score,
          entry: price, stopLoss: sl, takeProfit: tp,
          reason: reasons.join(' | '),
        );
      }
    }

    // ========== SHORT setup ==========
    if (trend == 'BEAR') {
      if (price < ema50) {
        score += 25;
        reasons.add('تحت EMA50');
      }

      if (rsi >= 45 && rsi <= 70) {
        score += 25;
        reasons.add('RSI=${rsi.toStringAsFixed(0)}');
      } else if (rsi > 30 && rsi < 45) {
        score += 10;
        reasons.add('RSI=${rsi.toStringAsFixed(0)}');
      }

      final distPct = (ema50 - price) / ema50 * 100;
      if (distPct >= -1.5 && distPct <= 2.5) {
        score += 20;
        reasons.add('قرب EMA50');
      }

      if (vs > 1.3) {
        score += 20;
        reasons.add('حجم ×${vs.toStringAsFixed(1)}');
      }

      if (closes1h.length >= 3) {
        final rsiPrev = Ind.rsi(closes1h.sublist(0, closes1h.length - 1), 14);
        if (rsiPrev != null && rsi < rsiPrev) {
          score += 10;
          reasons.add('RSI↓');
        }
      }

      if (score >= 60) {
        final sl = price + atr * 1.5;
        final tp = price - atr * 3.0;
        return Signal(
          symbol: symbol, direction: 'SHORT', score: score,
          entry: price, stopLoss: sl, takeProfit: tp,
          reason: reasons.join(' | '),
        );
      }
    }

    return Signal(
      symbol: symbol, direction: 'NONE', score: score,
      entry: price, stopLoss: 0, takeProfit: 0,
      reason: score > 0 ? reasons.join(' | ') : 'لا توجد شروط كافية',
    );
  }
}
