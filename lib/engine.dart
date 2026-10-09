import 'dart:math';

class Candle {
  final DateTime time;
  final double open, high, low, close;
  Candle({required this.time, required this.open, required this.high, required this.low, required this.close});
}

class Position {
  final String symbol;
  final double entry;
  final double size;
  final double margin;
  final double stopLoss;
  final double takeProfit;
  final int leverage;
  final bool isScalp;
  final DateTime openedAt;

  Position({
    required this.symbol, required this.entry, required this.size,
    required this.margin, required this.stopLoss, required this.takeProfit,
    required this.leverage, this.isScalp = false, DateTime? openedAt,
  }) : openedAt = openedAt ?? DateTime.now();

  double pnl(double current) => (current - entry) * size;
}

class TradeRecord {
  final String symbol;
  final String action;
  final double price;
  final double pnl;
  final DateTime time;
  final bool isScalp;
  TradeRecord({
    required this.symbol, required this.action, required this.price,
    required this.pnl, required this.time, this.isScalp = false,
  });

  Map<String, dynamic> toJson() => {
    'symbol': symbol, 'action': action, 'price': price,
    'pnl': pnl, 'time': time.toIso8601String(), 'isScalp': isScalp,
  };

  factory TradeRecord.fromJson(Map<String, dynamic> j) => TradeRecord(
    symbol: j['symbol'], action: j['action'], price: (j['price'] as num).toDouble(),
    pnl: (j['pnl'] as num).toDouble(), time: DateTime.parse(j['time']),
    isScalp: j['isScalp'] ?? false,
  );
}

// =============== INDICATORS ===============
class Indicators {
  static double? sma(List<double> arr, int period) {
    if (arr.length < period) return null;
    double sum = 0;
    for (int i = arr.length - period; i < arr.length; i++) sum += arr[i];
    return sum / period;
  }

  static double? ema(List<double> arr, int period) {
    if (arr.length < period) return null;
    final k = 2 / (period + 1);
    double ema = arr.take(period).reduce((a, b) => a + b) / period;
    for (int i = period; i < arr.length; i++) {
      ema = arr[i] * k + ema * (1 - k);
    }
    return ema;
  }

  static double? rsi(List<double> arr, [int period = 14]) {
    if (arr.length < period + 1) return null;
    double gains = 0, losses = 0;
    for (int i = arr.length - period; i < arr.length; i++) {
      final d = arr[i] - arr[i - 1];
      if (d > 0) gains += d; else losses -= d;
    }
    final ag = gains / period;
    final al = losses / period;
    if (al == 0) return 100;
    return 100 - (100 / (1 + ag / al));
  }

  static (double?, double?, double?) macd(List<double> arr) {
    final ema12 = ema(arr, 12);
    final ema26 = ema(arr, 26);
    if (ema12 == null || ema26 == null) return (null, null, null);
    final macd = ema12 - ema26;
    // approximate signal (9-period EMA of MACD) using last 9 macd values
    if (arr.length < 35) return (macd, null, null);
    final macdHistory = <double>[];
    for (int i = 26; i <= arr.length; i++) {
      final sub = arr.sublist(0, i);
      final e12 = ema(sub, 12);
      final e26 = ema(sub, 26);
      if (e12 != null && e26 != null) macdHistory.add(e12 - e26);
    }
    if (macdHistory.length < 9) return (macd, null, null);
    final signal = ema(macdHistory, 9);
    final hist = signal != null ? macd - signal : null;
    return (macd, signal, hist);
  }

  static (double?, double?, double?) bollinger(List<double> arr, [int period = 20, double mult = 2]) {
    if (arr.length < period) return (null, null, null);
    final slice = arr.sublist(arr.length - period);
    final mean = slice.reduce((a, b) => a + b) / period;
    double variance = 0;
    for (final v in slice) variance += pow(v - mean, 2);
    variance /= period;
    final sd = sqrt(variance);
    return (mean - mult * sd, mean, mean + mult * sd);
  }

  static double? stochastic(List<double> highs, List<double> lows, List<double> closes, [int period = 14]) {
    if (closes.length < period) return null;
    final start = closes.length - period;
    double highest = highs[start], lowest = lows[start];
    for (int i = start; i < closes.length; i++) {
      if (highs[i] > highest) highest = highs[i];
      if (lows[i] < lowest) lowest = lows[i];
    }
    if (highest == lowest) return 50;
    return ((closes.last - lowest) / (highest - lowest)) * 100;
  }
}

// =============== SCALPING SCORER ===============
class ScalpSignal {
  final int score;      // 0-100
  final String direction; // 'LONG' or 'NONE'
  final String reason;
  ScalpSignal(this.score, this.direction, this.reason);
}

class ScalpAnalyzer {
  /// Analyze market and return a score 0-100 for a LONG scalp entry
  static ScalpSignal analyze({
    required List<double> closes,
    required List<double> highs,
    required List<double> lows,
    required int smaShort,
    required int smaLong,
    required int rsiBuy,
  }) {
    if (closes.length < max(smaLong, 30)) {
      return ScalpSignal(0, 'NONE', 'بيانات غير كافية');
    }

    int score = 0;
    final reasons = <String>[];

    // 1. SMA trend (25 points)
    final ss = Indicators.sma(closes, smaShort);
    final sl = Indicators.sma(closes, smaLong);
    if (ss != null && sl != null && ss > sl) {
      score += 25;
      reasons.add('اتجاه صاعد (SMA)');
    }

    // 2. RSI (20 points)
    final rsi = Indicators.rsi(closes, 14);
    if (rsi != null) {
      if (rsi < rsiBuy) { score += 20; reasons.add('RSI=${rsi.toStringAsFixed(1)} (تشبع بيعي)'); }
      else if (rsi < 50) { score += 10; reasons.add('RSI=${rsi.toStringAsFixed(1)}'); }
    }

    // 3. MACD (20 points)
    final (macd, signal, hist) = Indicators.macd(closes);
    if (macd != null && signal != null && hist != null) {
      if (hist > 0) { score += 20; reasons.add('MACD إيجابي'); }
      else if (macd > signal) { score += 10; reasons.add('MACD تقاطع صاعد'); }
    }

    // 4. Bollinger Bands (20 points)
    final (lowBB, midBB, upBB) = Indicators.bollinger(closes, 20, 2);
    if (lowBB != null) {
      final last = closes.last;
      if (last <= lowBB) { score += 20; reasons.add('تحت حد بولنجر السفلي'); }
      else if (last < midBB!) { score += 10; reasons.add('تحت وسط بولنجر'); }
    }

    // 5. Stochastic (15 points)
    final stoch = Indicators.stochastic(highs, lows, closes, 14);
    if (stoch != null && stoch < 20) {
      score += 15;
      reasons.add('Stochastic=${stoch.toStringAsFixed(1)}');
    }

    final direction = score >= 60 ? 'LONG' : 'NONE';
    return ScalpSignal(score, direction, reasons.join(' • '));
  }
}

// =============== BACKTEST ===============
class BacktestResult {
  final int trades;
  final int wins;
  final int losses;
  final double finalBalance;
  final double maxDrawdown;
  BacktestResult({
    required this.trades, required this.wins, required this.losses,
    required this.finalBalance, required this.maxDrawdown,
  });
  double get winRate => trades == 0 ? 0 : (wins / trades * 100);
  double get profitPct => (finalBalance - 1000) / 1000 * 100;
}

class Backtester {
  static BacktestResult run({
    required List<double> prices,
    required int smaShort,
    required int smaLong,
    required int rsiBuy,
    required int rsiSell,
    double initial = 1000,
    int leverage = 10,
    double marginPerTrade = 50,
  }) {
    double balance = initial;
    int wins = 0, losses = 0, trades = 0;
    double peak = initial, maxDD = 0;
    Position? pos;

    final hist = <double>[];
    for (int i = 0; i < prices.length; i++) {
      hist.add(prices[i]);
      if (hist.length < max(smaLong, 15) + 1) continue;
      final price = prices[i];
      final ss = Indicators.sma(hist, smaShort);
      final sl = Indicators.sma(hist, smaLong);
      final rsi = Indicators.rsi(hist, 14);
      if (ss == null || sl == null || rsi == null) continue;

      // Check SL/TP
      if (pos != null) {
        if (price <= pos.stopLoss || price >= pos.takeProfit) {
          final pnl = (price - pos.entry) * pos.size;
          balance += pos.margin + pnl;
          if (pnl > 0) wins++; else losses++;
          trades++;
          pos = null;
        }
      }

      // Entry
      if (pos == null && ss > sl && rsi < rsiBuy && balance >= marginPerTrade) {
        final size = (marginPerTrade * leverage) / price;
        final sl2 = price * 0.99;
        final tp2 = price * 1.015;
        pos = Position(
          symbol: 'BT', entry: price, size: size, margin: marginPerTrade,
          stopLoss: sl2, takeProfit: tp2, leverage: leverage,
        );
        balance -= marginPerTrade;
      }
      // Exit
      else if (pos != null && ss < sl && rsi > rsiSell) {
        final pnl = (price - pos.entry) * pos.size;
        balance += pos.margin + pnl;
        if (pnl > 0) wins++; else losses++;
        trades++;
        pos = null;
      }

      if (balance > peak) peak = balance;
      final dd = (peak - balance) / peak * 100;
      if (dd > maxDD) maxDD = dd;
    }

    return BacktestResult(
      trades: trades, wins: wins, losses: losses,
      finalBalance: balance, maxDrawdown: maxDD,
    );
  }
}
