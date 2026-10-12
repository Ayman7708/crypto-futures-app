import 'dart:async';
import 'package:flutter/material.dart';
import 'engine.dart' hide Candle;
import 'services.dart';
import 'learning.dart';
import 'strategies.dart';
import 'market_regime.dart';
import 'volatility.dart';
import 'market_symbols.dart';
import 'master_signal.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'advanced.dart';
import 'api_candles.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  NotificationService.init().catchError((e) => debugPrint('Notif: $e'));
  runApp(const CryptoBotApp());
}

// Fallback list used until Binance fetch completes
const List<String> FALLBACK_SYMBOLS = [
  'BTCUSDT', 'ETHUSDT', 'BNBUSDT', 'SOLUSDT', 'XRPUSDT', 'DOGEUSDT',
  'ADAUSDT', 'DOTUSDT', 'LINKUSDT', 'MATICUSDT', 'AVAXUSDT', 'ATOMUSDT',
  'NEARUSDT', 'FILUSDT', 'APTUSDT', 'ARBUSDT', 'OPUSDT', 'INJUSDT',
  'SUIUSDT', 'LTCUSDT',
];
const int LOOP_SECONDS = 5;

class CryptoBotApp extends StatelessWidget {
  const CryptoBotApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Crypto Bot Pro',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0E17),
        primaryColor: const Color(0xFF4ADE80),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF131A26), elevation: 0),
        colorScheme: const ColorScheme.dark(primary: Color(0xFF4ADE80), secondary: Color(0xFF60A5FA)),
      ),
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabs;

  double _balance = 1000.0;
  double _initialCapital = 1000.0;
  double _marginPerTrade = 50.0;
  int _leverage = 5;
  int _rsiBuy = 40;
  int _rsiSell = 60;
  int _smaShort = 5;
  int _smaLong = 10;
  double _slPercent = 2.0;
  double _tpPercent = 5.0;
  int _scalpThreshold = 65;
  bool _scalpEnabled = true;
  bool _running = false;
  bool _loaded = false;

  final Map<String, Position> _positions = {};
  final Map<String, List<double>> _priceHistory = {};
  final Map<String, List<double>> _highHistory = {};
  final Map<String, List<double>> _lowHistory = {};
  final Map<String, List<double>> _volumeHistory = {};
  List<IndicatorDef> _indicators = IndicatorRegistry.defaults();
  bool _longBias = true;
  final Map<String, double> _pumpScores = {};
  final Map<String, ScalpSignal> _scalpSignals = {};
  final Map<String, String> _masterTopStrategies = {};
  final List<TradeRecord> _trades = [];
  final Map<String, double> _livePrices = {};

  String _apiKey = '';
  String _apiSecret = '';
  String _lastError = '';
  Timer? _timer;
  final LearningEngineV2 _learner = LearningEngineV2();
  final MasterEngine _master = MasterEngine();
  MarketAnalysis? _marketAnalysis;
  final Map<String, VolatilityScore> _volScores = {};
  final MasterSignal _masterSignal = MasterSignal();
  final Map<String, MasterSignalResult> _masterResults = {};
  List<String> _allSymbols = [];
  int _maxActiveSymbols = 30;
  bool _loadingSymbols = false;

  List<String> get _activeSymbols {
    if (_allSymbols.isEmpty) return FALLBACK_SYMBOLS;
    // If we have volatility scores, return top N by opportunity
    if (_volScores.isNotEmpty) {
      final sorted = _volScores.values.toList()
        ..sort((a, b) => b.opportunity.compareTo(a.opportunity));
      final active = sorted.take(_maxActiveSymbols).map((v) => v.symbol).toList();
      // Always ensure BTC is included for market analysis
      if (!active.contains('BTCUSDT') && _allSymbols.contains('BTCUSDT')) {
        active.add('BTCUSDT');
      }
      return active;
    }
    return _allSymbols.take(_maxActiveSymbols).toList();
  }
  bool _focusFastCoins = true;
  int _topCoinCount = 10;
  final int _maxPositions = 5;
  final Map<String, DateTime> _lastTradeTime = {};
  static const int _cooldownSeconds = 600;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabs = TabController(length: 7, vsync: this);
    for (final s in _activeSymbols) {
      _priceHistory[s] = [];
      _highHistory[s] = [];
      _lowHistory[s] = [];
      _volumeHistory[s] = [];
    }
    _loadAllSymbols();
    _loadState().then((_) {
      if (mounted && !_running) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && !_running) _toggleBot();
        });
      }
    });
    WakelockPlus.enable();
    Timer(const Duration(seconds: 6), () {
      if (!_loaded && mounted) setState(() => _loaded = true);
    });
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _timer?.cancel();
    _tabs.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  List<String> get _sortedSymbols {
    final list = List<String>.from(_activeSymbols);
    list.sort((a, b) {
      final sa = _pumpScores[a] ?? 0;
      final sb = _pumpScores[b] ?? 0;
      return sb.compareTo(sa);
    });
    return list;
  }

  Future<void> _loadAllSymbols() async {
    if (_loadingSymbols) return;
    setState(() => _loadingSymbols = true);
    try {
      final symbols = await MarketService.fetchAllSymbols(minVolumeUsdt: 50000000);
      if (symbols != null && symbols.isNotEmpty && mounted) {
        setState(() {
          _allSymbols = symbols;
          for (final s in symbols) {
            _priceHistory.putIfAbsent(s, () => []);
            _highHistory.putIfAbsent(s, () => []);
            _lowHistory.putIfAbsent(s, () => []);
            _volumeHistory.putIfAbsent(s, () => []);
          }
        });
        debugPrint('🎯 Loaded ${symbols.length} symbols from Binance');
      }
    } catch (e) {
      debugPrint('Failed to load symbols: $e');
    } finally {
      if (mounted) setState(() => _loadingSymbols = false);
    }
  }

  Future<void> _loadState() async {
    Map<String, dynamic>? data;
    try {
      data = await StorageService.loadAll().timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('Load error: $e');
      data = null;
    }
    if (data != null && mounted) {
      setState(() {
        _balance = (data!['balance'] as num).toDouble();
        final s = data['settings'] as Map<String, dynamic>;
        _initialCapital = (s['initialCapital'] as num?)?.toDouble() ?? 1000;
        _marginPerTrade = (s['margin'] as num?)?.toDouble() ?? 50;
        _leverage = (s['leverage'] as num?)?.toInt() ?? 10;
        _rsiBuy = (s['rsiBuy'] as num?)?.toInt() ?? 40;
        _rsiSell = (s['rsiSell'] as num?)?.toInt() ?? 60;
        _smaShort = (s['smaShort'] as num?)?.toInt() ?? 5;
        _smaLong = (s['smaLong'] as num?)?.toInt() ?? 10;
        _slPercent = (s['slPercent'] as num?)?.toDouble() ?? 1.0;
        _tpPercent = (s['tpPercent'] as num?)?.toDouble() ?? 1.5;
        _scalpThreshold = (s['scalpThreshold'] as num?)?.toInt() ?? 60;
        _scalpEnabled = (s['scalpEnabled'] as bool?) ?? true;
        _apiKey = (s['apiKey'] as String?) ?? '';
        _apiSecret = (s['apiSecret'] as String?) ?? '';
        _longBias = (s['longBias'] as bool?) ?? true;
        if (s['indicators'] != null) {
          final list = (s['indicators'] as List).map((e) => IndicatorDef.fromJson(e as Map<String, dynamic>)).toList();
          if (list.isNotEmpty) _indicators = list;
        }
        if (s['learner'] != null) {
          _learner.loadFromJson(Map<String, dynamic>.from(s['learner']));
        }
        if (s['master'] != null) {
          _master.loadFromJson(Map<String, dynamic>.from(s['master']));
        }
        _focusFastCoins = (s['focusFast'] as bool?) ?? true;
        _topCoinCount = (s['topCoinCount'] as num?)?.toInt() ?? 10;
        if (s['masterSignal'] != null) {
          _masterSignal.loadFromJson(Map<String, dynamic>.from(s['masterSignal']));
        }
        _maxActiveSymbols = (s['maxActive'] as num?)?.toInt() ?? 30;
        if (s['allSymbols'] != null) {
          _allSymbols = (s['allSymbols'] as List).map((e) => e.toString()).toList();
          for (final sym in _allSymbols) {
            _priceHistory.putIfAbsent(sym, () => []);
            _highHistory.putIfAbsent(sym, () => []);
            _lowHistory.putIfAbsent(sym, () => []);
            _volumeHistory.putIfAbsent(sym, () => []);
          }
        }
        final hist = data['history'] as Map<String, dynamic>;
        hist.forEach((k, v) {
          _priceHistory[k] = (v as List).map((e) => (e as num).toDouble()).toList();
        });
        final posRaw = data['positions'] as Map<String, dynamic>;
        posRaw.forEach((k, v) {
          _positions[k] = Position(
            symbol: k, entry: (v['entry'] as num).toDouble(),
            size: (v['size'] as num).toDouble(), margin: (v['margin'] as num).toDouble(),
            stopLoss: (v['sl'] as num).toDouble(), takeProfit: (v['tp'] as num).toDouble(),
            leverage: (v['leverage'] as num).toInt(), isScalp: v['isScalp'] ?? false,
          );
        });
        final tr = data['trades'] as List;
        for (final t in tr) {
          _trades.add(TradeRecord.fromJson(t as Map<String, dynamic>));
        }
        _loaded = true;
      });
    } else {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _saveState() async {
    final posMap = <String, dynamic>{};
    _positions.forEach((k, p) {
      posMap[k] = {
        'entry': p.entry, 'size': p.size, 'margin': p.margin,
        'sl': p.stopLoss, 'tp': p.takeProfit, 'leverage': p.leverage, 'isScalp': p.isScalp,
      };
    });
    await StorageService.saveAll(
      balance: _balance, positions: posMap,
      trades: _trades.map((t) => t.toJson()).toList(),
      settings: {
        'initialCapital': _initialCapital, 'margin': _marginPerTrade,
        'leverage': _leverage, 'rsiBuy': _rsiBuy, 'rsiSell': _rsiSell,
        'smaShort': _smaShort, 'smaLong': _smaLong, 'slPercent': _slPercent,
        'tpPercent': _tpPercent, 'scalpThreshold': _scalpThreshold,
        'scalpEnabled': _scalpEnabled, 'apiKey': _apiKey, 'apiSecret': _apiSecret,
        'longBias': _longBias,
        'indicators': _indicators.map((i) => i.toJson()).toList(),
        'learner': _learner.toJson(),
        'master': _master.toJson(),
        'focusFast': _focusFastCoins,
        'topCoinCount': _topCoinCount,
        'masterSignal': _masterSignal.toJson(),
        'allSymbols': _allSymbols,
        'maxActive': _maxActiveSymbols,
      },
    );
    await StorageService.saveHistory(_priceHistory);
  }

  void _toggleBot() {
    if (_running) {
      _timer?.cancel();
      setState(() => _running = false);
    } else {
      setState(() => _running = true);
      _tick();
      _timer = Timer.periodic(const Duration(seconds: LOOP_SECONDS), (_) => _tick());
    }
  }

  Future<void> _tick() async {
    final candles = await CandleService.fetchAll(_activeSymbols);
    if (candles == null) {
      if (mounted) setState(() => _lastError = 'API error');
      return;
    }
    if (!mounted) return;
    setState(() {
      _lastError = '';
      for (final sym in _activeSymbols) {
        final c = candles[sym];
        if (c == null || c.isEmpty) continue;
        final last = c.last;
        _livePrices[sym] = last.close;
        _priceHistory[sym]!.add(last.close);
        _highHistory[sym]!.add(last.high);
        _lowHistory[sym]!.add(last.low);
        _volumeHistory[sym]!.add(last.volume);
        if (_priceHistory[sym]!.length > 200) {
          _priceHistory[sym]!.removeAt(0);
          _highHistory[sym]!.removeAt(0);
          _lowHistory[sym]!.removeAt(0);
          _volumeHistory[sym]!.removeAt(0);
        }
        _process(sym, last.close);
      }
      // Market regime analysis (BTC + alts)
      final btcHist = _priceHistory['BTCUSDT'];
      if (btcHist != null && btcHist.length >= 50) {
        _learner.detectRegime(
          closes: btcHist,
          highs: _highHistory['BTCUSDT']!,
          lows: _lowHistory['BTCUSDT']!,
        );
        // Build alt map excluding BTC
        final altMap = <String, List<double>>{};
        for (final sym in _activeSymbols) {
          if (sym == 'BTCUSDT') continue;
          final h = _priceHistory[sym];
          if (h != null && h.length >= 50) altMap[sym] = h;
        }
        _marketAnalysis = MarketRegimeAnalyzer.analyze(
          btcCloses: btcHist, altCloses: altMap,
        );
      }
      // Compute volatility score for every symbol
      for (final sym in _activeSymbols) {
        final h = _priceHistory[sym];
        final hh = _highHistory[sym];
        final ll = _lowHistory[sym];
        final vv = _volumeHistory[sym];
        if (h == null || hh == null || ll == null || vv == null) continue;
        if (h.length < 20) continue;
        _volScores[sym] = VolatilityRanker.analyze(
          symbol: sym, closes: h, highs: hh, lows: ll, volumes: vv,
        );
        // Master signal analysis
        if (h.length >= 55) {
          _masterResults[sym] = _masterSignal.analyze(
            closes: h, highs: hh, lows: ll, volumes: vv,
            smaShort: _smaShort, smaLong: _smaLong,
          );
        }
      }
    });
    _saveState();
  }

  void _process(String symbol, double price) {
    final hist = _priceHistory[symbol]!;
    if (hist.length < 30) return;
    final pos = _positions[symbol];
    if (pos != null) {
      final profitPct = pos.isLong
          ? (price - pos.entry) / pos.entry * 100
          : (pos.entry - price) / pos.entry * 100;

      // === 1. Break-even عند +1.5% ===
      if (profitPct >= 1.5) {
        final newSL = pos.entry;
        final better = pos.isLong ? newSL > pos.stopLoss : newSL < pos.stopLoss;
        if (better) {
          _positions[symbol] = Position(
            symbol: symbol, entry: pos.entry, size: pos.size, margin: pos.margin,
            stopLoss: newSL, takeProfit: pos.takeProfit, leverage: pos.leverage,
            isScalp: pos.isScalp, isLong: pos.isLong,
          );
        }
      }

      // === 2. Trailing Stop متدرج (Dynamic) ===
      if (profitPct >= 2.0) {
        double trailDistance;
        if (profitPct < 4.0) {
          trailDistance = 1.5;  // ربح 2-4% → اتبع بمسافة 1.5%
        } else if (profitPct < 6.0) {
          trailDistance = 1.0;  // ربح 4-6% → اتبع بمسافة 1.0%
        } else {
          trailDistance = 0.7;  // ربح 6%+ → اتبع بمسافة 0.7%
        }
        final trailSL = pos.isLong
            ? price * (1 - trailDistance / 100)
            : price * (1 + trailDistance / 100);
        final cur = _positions[symbol]!;
        final trailBetter = pos.isLong ? trailSL > cur.stopLoss : trailSL < cur.stopLoss;
        if (trailBetter) {
          _positions[symbol] = Position(
            symbol: symbol, entry: cur.entry, size: cur.size, margin: cur.margin,
            stopLoss: trailSL, takeProfit: cur.takeProfit, leverage: cur.leverage,
            isScalp: cur.isScalp, isLong: cur.isLong,
          );
        }
      }

      // === 3. Dynamic Take Profit ===
      // TP يرتفع كل ما زاد الربح (للمراكز الرابحة فقط)
      if (profitPct >= 2.0) {
        final curPos = _positions[symbol]!;
        double newTP;
        if (profitPct < 4.0) {
          newTP = pos.entry * (pos.isLong ? 1.05 : 0.95);  // TP عند +5%
        } else if (profitPct < 6.0) {
          newTP = pos.entry * (pos.isLong ? 1.08 : 0.92);  // TP عند +8%
        } else {
          newTP = pos.entry * (pos.isLong ? 1.12 : 0.88);  // TP عند +12%
        }
        final tpBetter = pos.isLong ? newTP > curPos.takeProfit : newTP < curPos.takeProfit;
        if (tpBetter) {
          _positions[symbol] = Position(
            symbol: symbol, entry: curPos.entry, size: curPos.size, margin: curPos.margin,
            stopLoss: curPos.stopLoss, takeProfit: newTP, leverage: curPos.leverage,
            isScalp: curPos.isScalp, isLong: curPos.isLong,
          );
        }
      }

      // === 4. فحوصات الإغلاق ===
      final updatedPos = _positions[symbol]!;
      final slHit = updatedPos.isLong ? price <= updatedPos.stopLoss : price >= updatedPos.stopLoss;
      final tpHit = updatedPos.isLong ? price >= updatedPos.takeProfit : price <= updatedPos.takeProfit;
      final liqHit = updatedPos.isLong ? price <= updatedPos.liquidationPrice : price >= updatedPos.liquidationPrice;
      if (slHit) { _closePosition(symbol, price, 'STOP_LOSS'); return; }
      if (tpHit) { _closePosition(symbol, price, 'TAKE_PROFIT'); return; }
      if (liqHit) { _closePosition(symbol, price, 'LIQUIDATED'); return; }
    }
    final ss = Indicators.sma(hist, _smaShort);
    final sl = Indicators.sma(hist, _smaLong);
    final rsi = Indicators.rsi(hist, 14);
    if (ss == null || sl == null || rsi == null) return;

    final thr = LearningEngine.adaptiveThreshold(_trades, _scalpThreshold);
    final signal = AdvancedAnalyzer.analyze(
      closes: hist,
      highs: _highHistory[symbol]!,
      lows: _lowHistory[symbol]!,
      volumes: _volumeHistory[symbol]!,
      smaShort: _smaShort,
      smaLong: _smaLong,
      rsiBuy: _rsiBuy,
      rsiSell: _rsiSell,
      pumpMinScore: 50,
      scalpMinScore: _longBias ? 55 : thr,
    );
    _scalpSignals[symbol] = ScalpSignal(signal.score, signal.direction, signal.reason);
    _pumpScores[symbol] = signal.pumpProb;

    if (pos != null) {
      // Only exit on extreme conditions: RSI > 85 AND bearish SMA cross
      // This lets winning positions run with trailing stop
      final rsiVeryHigh = rsi > 85;
      final smaBearish = ss < sl;
      if (rsiVeryHigh && smaBearish) {
        _closePosition(symbol, price, 'SELL');
      }
      // If profit is already strong (>= 5%), let trailing handle it
      return;
    }
    if (_balance < _marginPerTrade) return;

    final learnedOK = _learner.shouldEnter(signal.score);
    // === Market-adaptive direction selection ===
    Regime regime = Regime.neutral;
    double longMult = 1.0, shortMult = 1.0;
    int thresholdAdj = 0;
    if (_marketAnalysis != null) {
      regime = _marketAnalysis!.regime;
      final (lm, sm, adj) = MarketRegimeAnalyzer.tradingBias(
        regime, _marketAnalysis!.altseasonScore,
      );
      longMult = lm;
      shortMult = sm;
      thresholdAdj = adj;
    }

    final baseThreshold = (_scalpThreshold + thresholdAdj).clamp(40, 85);
    final effectiveThreshold = _longBias
        ? (baseThreshold / longMult).clamp(40, 85).toInt()
        : (baseThreshold / shortMult).clamp(40, 85).toInt();
    final effectiveThresholdShort = (baseThreshold / shortMult).clamp(40, 85).toInt();

    final canTakeMore = _positions.length < _maxPositions && _canTradeSymbol(symbol);

    // Fast coins filter: only trade top N volatile coins if enabled
    bool isTopCoin = true;
    if (_focusFastCoins && _volScores.isNotEmpty) {
      final top = VolatilityRanker.topSymbols(_volScores, _topCoinCount);
      isTopCoin = top.contains(symbol);
    }

    // Try LONG first (if bias allows)
    final longOK = signal.score >= effectiveThreshold &&
                   longMult > 0.5 &&
                   learnedOK && canTakeMore && isTopCoin;
    if (signal.direction == 'LONG' && longOK) {
      _openPosition(symbol, price, isScalp: signal.score >= 70, isLong: true);
      LearningEngine.updateWeights(_indicators, _trades);
      return;
    }

    // Try SHORT (if regime favors bearish or neutral)
    final shortScore = signal.score; // Reuse same score logic in reverse
    final shortOK = shortScore >= effectiveThresholdShort &&
                    shortMult > 0.5 &&
                    canTakeMore && isTopCoin &&
                    (regime == Regime.bearStrong ||
                     regime == Regime.bearWeak ||
                     (regime == Regime.neutral && shortMult >= 1.0));
    if (shortOK && signal.direction != 'LONG') {
      _openPosition(symbol, price, isScalp: shortScore >= 70, isLong: false);
      LearningEngine.updateWeights(_indicators, _trades);
      return;
    }

    LearningEngine.updateWeights(_indicators, _trades);
  }

  void _manualOpen(String symbol) {
    final price = _livePrices[symbol];
    if (price == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد سعر متاح حالياً'), backgroundColor: Color(0xFFEF4444)),
      );
      return;
    }
    if (_positions.containsKey(symbol)) return;
    if (_balance < _marginPerTrade) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرصيد غير كافٍ'), backgroundColor: Color(0xFFEF4444)),
      );
      return;
    }
    setState(() => _openPosition(symbol, price, isScalp: false));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم فتح صفقة على $symbol'), backgroundColor: const Color(0xFF16A34A)),
    );
  }

  void _manualClose(String symbol) {
    final pos = _positions[symbol];
    if (pos == null) return;
    final price = _livePrices[symbol] ?? pos.entry;
    setState(() => _closePosition(symbol, price, 'MANUAL'));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم إغلاق صفقة $symbol'), backgroundColor: const Color(0xFF16A34A)),
    );
  }

  bool _canTradeSymbol(String symbol) {
    final last = _lastTradeTime[symbol];
    if (last == null) return true;
    return DateTime.now().difference(last).inSeconds >= _cooldownSeconds;
  }

  final Map<String, DateTime> _lastProfitTime = {};

  void _openPosition(String symbol, double price, {required bool isScalp, bool isLong = true}) {
    // Profit lockout: don't reopen same coin for 15 min after a profitable close
    final lastProfit = _lastProfitTime[symbol];
    if (lastProfit != null) {
      final mins = DateTime.now().difference(lastProfit).inMinutes;
      if (mins < 15) return;
    }
    final size = (_marginPerTrade * _leverage) / price;
    final sl = isLong
        ? price * (1 - _slPercent / 100)
        : price * (1 + _slPercent / 100);
    final tp = isLong
        ? price * (1 + _tpPercent / 100)
        : price * (1 - _tpPercent / 100);
    _positions[symbol] = Position(
      symbol: symbol, entry: price, size: size, margin: _marginPerTrade,
      stopLoss: sl, takeProfit: tp, leverage: _leverage, isScalp: isScalp,
      isLong: isLong,
    );
    _lastTradeTime[symbol] = DateTime.now();
    _balance -= _marginPerTrade;
    _trades.insert(0, TradeRecord(
      symbol: symbol, action: isScalp ? 'SCALP_BUY' : 'BUY',
      price: price, pnl: 0, time: DateTime.now(), isScalp: isScalp,
    ));
    NotificationService.show(
      isScalp ? 'إسكالبينج' : 'مفتوح',
      '$symbol @ \$${price.toStringAsFixed(2)} SL: \$${sl.toStringAsFixed(2)} TP: \$${tp.toStringAsFixed(2)}',
    );
    if (_trades.length > 200) _trades.removeLast();
    _saveState();
  }

  void _closePosition(String symbol, double price, String reason) {
    final pos = _positions[symbol];
    if (pos == null) return;
    final pnl = (price - pos.entry) * pos.size;
    if (pnl > 0) _lastProfitTime[symbol] = DateTime.now();
    final wasWin = pnl > 0;
    final reason_str = _scalpSignals[symbol]?.reason ?? '';
    _learner.updateFromTrade(
      wasWin: wasWin, pnl: pnl,
      signalReason: reason_str, direction: 'LONG',
      activeIndicators: {'sma','ema','rsi','macd','bollinger','stoch','adx','vwap','supertrend','volume_surge'},
    );
    // Update each master strategy weight
    for (final s in _master.strategies) {
      _master.updateFromTrade(s.name, wasWin);
    }
    // Update master signal indicator weights
    final mr = _masterResults[symbol];
    if (mr != null) {
      _masterSignal.updateFromTrade(mr.votes, wasWin);
    }
    _balance += pos.margin + pnl;
    _trades.insert(0, TradeRecord(
      symbol: symbol, action: reason, price: price, pnl: pnl,
      time: DateTime.now(), isScalp: pos.isScalp,
    ));
    _positions.remove(symbol);
    NotificationService.show('Close $symbol', '$reason PnL: \$${pnl.toStringAsFixed(2)}');
    if (_trades.length > 200) _trades.removeLast();
    _saveState();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0E17),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF4ADE80))),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('بوت التداول برو v2', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        actions: [
          if (_lastError.isNotEmpty)
            const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.wifi_off, color: Color(0xFFEF4444), size: 20)),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _running ? const Color(0xFF4ADE80) : const Color(0xFFEF4444),
              )),
              const SizedBox(width: 6),
              Text(_running ? 'يعمل' : 'متوقف', style: const TextStyle(fontSize: 12)),
            ]),
          ),
        ],
        bottom: TabBar(
          controller: _tabs, isScrollable: true,
          indicatorColor: const Color(0xFF4ADE80),
          labelColor: const Color(0xFF4ADE80), unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: 'الرئيسية'), Tab(text: 'التحليل'),
            Tab(text: 'السجل'), Tab(text: 'الاختبار'), Tab(text: 'اختبار المؤشرات'),
            Tab(text: 'المعتمدة'), Tab(text: 'الإعدادات'),
          ],
        ),
      ),
      body: Column(children: [
        _buildBalanceBar(),
        Expanded(child: TabBarView(controller: _tabs, children: [
          _buildDashboard(), _buildAnalytics(), _buildTrades(),
          _buildBacktest(), _buildTestingIndicators(), _buildApprovedIndicators(),
          _buildSettings(),
        ])),
        _buildStartButton(),
      ]),
    );
  }

  Widget _buildBalanceBar() {
    final pnl = _balance - _initialCapital;
    final pct = _initialCapital > 0 ? (pnl / _initialCapital * 100) : 0.0;
    final color = pnl >= 0 ? const Color(0xFF4ADE80) : const Color(0xFFEF4444);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF1E3A2F), Color(0xFF16241C)]),
        border: Border(bottom: BorderSide(color: Color(0xFF2A4A3A))),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('الرصيد', style: TextStyle(color: Colors.white54, fontSize: 11)),
          Text('\$${_balance.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF4ADE80))),
        ]),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          const Text('الربح / الخسارة', style: TextStyle(color: Colors.white54, fontSize: 11)),
          Text('${pnl >= 0 ? '+' : ''}\$${pnl.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          Text('${pnl >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%', style: TextStyle(fontSize: 11, color: color)),
        ]),
      ]),
    );
  }

  Widget _buildDashboard() {
    return RefreshIndicator(
      onRefresh: _tick,
      child: ListView.builder(
        padding: const EdgeInsets.all(10), itemCount: _sortedSymbols.length,
        itemBuilder: (context, i) {
          final sym = _sortedSymbols[i];
          final price = _livePrices[sym];
          final hist = _priceHistory[sym]!;
          final rsi = Indicators.rsi(hist, 14);
          final ss = Indicators.sma(hist, _smaShort);
          final sl = Indicators.sma(hist, _smaLong);
          final pos = _positions[sym];
          final scalp = _scalpSignals[sym];
          final pump = _pumpScores[sym] ?? 0.0;
          return Container(
            margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF131A26), borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1E2838)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Row(children: [
                  if (_volScores[sym] != null)
                    Text('${VolatilityRanker.rankEmoji(_volScores[sym]!.rank)} ',
                        style: const TextStyle(fontSize: 13)),
                  Text(sym, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ]),
                Text(price != null ? '\$${price.toStringAsFixed(2)}' : '...',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 15, color: Color(0xFF60A5FA))),
              ]),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                _chip('RSI', rsi != null ? rsi.toStringAsFixed(1) : '-'),
                _chip('SMA$_smaShort', ss != null ? ss.toStringAsFixed(0) : '-'),
                _chip('SMA$_smaLong', sl != null ? sl.toStringAsFixed(0) : '-'),
                if (scalp != null) _chip('إسكالبينج', '${scalp.score}%',
                    color: scalp.score >= _scalpThreshold ? const Color(0xFF4ADE80) : null),
              ]),
              if (pos != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2332),
                    border: Border(right: BorderSide(
                      color: pos.isScalp ? const Color(0xFFF59E0B) : const Color(0xFF4ADE80), width: 3)),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(pos.isScalp ? 'إسكالبينج' : 'مفتوح',
                        style: TextStyle(color: pos.isScalp ? const Color(0xFFF59E0B) : const Color(0xFF4ADE80), fontSize: 12)),
                    Text('E: \$${pos.entry.toStringAsFixed(2)} | PnL: ${pos.pnl(price ?? pos.entry) >= 0 ? "+" : ""}\$${pos.pnl(price ?? pos.entry).toStringAsFixed(2)}',
                        style: TextStyle(fontSize: 11,
                            color: pos.pnl(price ?? pos.entry) >= 0 ? const Color(0xFF4ADE80) : const Color(0xFFEF4444))),
                  ]),
                ),
              ],
              const SizedBox(height: 8),
              Row(children: [
                if (pump >= 60)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16A34A).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('🔥 ${pump.toInt()}%',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF4ADE80), fontWeight: FontWeight.bold)),
                  ),
                const Spacer(),
                if (pos == null)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.trending_up, size: 14, color: Colors.white),
                    label: const Text('فتح صفقة', style: TextStyle(fontSize: 12, color: Colors.white)),
                    onPressed: () => _manualOpen(sym),
                  )
                else
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.close, size: 14, color: Colors.white),
                    label: const Text('إغلاق', style: TextStyle(fontSize: 12, color: Colors.white)),
                    onPressed: () => _manualClose(sym),
                  ),
              ]),
            ]),
          );
        },
      ),
    );
  }

  Widget _chip(String label, String value, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: const Color(0xFF1A2332), borderRadius: BorderRadius.circular(6)),
      child: Text('$label: $value',
          style: TextStyle(fontSize: 11, color: color ?? const Color(0xFF8892A6),
              fontWeight: color != null ? FontWeight.bold : FontWeight.normal)),
    );
  }

  Widget _buildAnalytics() {
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        _buildLearningCard(),
        const SizedBox(height: 10),
        ..._activeSymbols.map((sym) => _buildAnalyticsTile(sym)),
      ],
    );
  }

  Widget _buildLearningCard() {
    final wr = _learner.totalTrades == 0 ? 0.0 : (_learner.totalWins / _learner.totalTrades * 100);
    final top = _learner.getTopIndicators(limit: 3);
    final worst = _learner.getWorstIndicators(limit: 3);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1E2838), Color(0xFF131A26)]),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF60A5FA), width: 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('🧠 نظام التعلم الذكي',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF60A5FA))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0E17), borderRadius: BorderRadius.circular(6)),
            child: Text(_learner.regimeName,
                style: const TextStyle(fontSize: 11, color: Color(0xFF4ADE80))),
          ),
        ]),
        const SizedBox(height: 10),
        _indRow('إجمالي الصفقات', '${_learner.totalTrades}'),
        _indRow('الرابحة / الخاسرة', '${_learner.totalWins} / ${_learner.totalLosses}'),
        _indRow('نسبة النجاح', '${wr.toStringAsFixed(1)}%'),
        _indRow('عتبة الدخول الحالية', '${_learner.entryThreshold.toStringAsFixed(0)}/100'),
        _indRow('الربح التراكمي', '\$${_learner.rollingPnL.toStringAsFixed(2)}'),
        const Divider(color: Color(0xFF1E2838)),
        if (top.isNotEmpty) ...[
          const Text('🏆 أفضل المؤشرات:', style: TextStyle(color: Color(0xFF4ADE80), fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          for (final p in top)
            _indRow(p.id, '${(p.winRate * 100).toStringAsFixed(0)}% (W:${p.wins} L:${p.losses})'),
          const SizedBox(height: 8),
        ],
        if (worst.isNotEmpty) ...[
          const Text('⚠️ أسوأ المؤشرات:', style: TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          for (final p in worst)
            _indRow(p.id, '${(p.winRate * 100).toStringAsFixed(0)}% (W:${p.wins} L:${p.losses})'),
        ],
        if (_learner.losingPatterns.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('🚫 أنماط خاسرة محفوظة: ${_learner.losingPatterns.length}',
              style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11)),
        ],
        const Divider(color: Color(0xFF1E2838)),
        const Text('⚙️ أوزان الاستراتيجيات:', style: TextStyle(color: Color(0xFF60A5FA), fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        ..._master.strategies.map((s) {
          final w = _master.weights[s.name] ?? 1.0;
          final ww = _master.wins[s.name] ?? 0;
          final ll = _master.losses[s.name] ?? 0;
          return _indRow(s.name, 'W:${w.toStringAsFixed(2)} | ${ww}W/${ll}L');
        }),
        Builder(builder: (context) {
          final btcMaster = _masterResults['BTCUSDT'];
          if (btcMaster == null) return const SizedBox.shrink();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Divider(color: Color(0xFF1E2838)),
            const Text('👑 المؤشر الأسطوري (BTC)',
                style: TextStyle(color: Color(0xFFFFD700), fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              Column(children: [
                const Text('صعودي', style: TextStyle(color: Color(0xFF4ADE80), fontSize: 11)),
                Text('${btcMaster.bullishScore}',
                    style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 20, fontWeight: FontWeight.bold)),
              ]),
              Column(children: [
                const Text('هبوطي', style: TextStyle(color: Color(0xFFEF4444), fontSize: 11)),
                Text('${btcMaster.bearishScore}',
                    style: const TextStyle(color: Color(0xFFEF4444), fontSize: 20, fontWeight: FontWeight.bold)),
              ]),
            ]),
            const SizedBox(height: 4),
            Center(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: btcMaster.recommendation.contains('LONG')
                    ? const Color(0xFF16A34A).withOpacity(0.3)
                    : (btcMaster.recommendation.contains('SHORT')
                        ? const Color(0xFFDC2626).withOpacity(0.3)
                        : const Color(0xFF1A2332)),
                borderRadius: BorderRadius.circular(6)),
              child: Text(btcMaster.recommendation,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            )),
            const SizedBox(height: 6),
            if (btcMaster.topBullish.isNotEmpty)
              Text('👆 ${btcMaster.topBullish.join(" • ")}',
                  style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 10)),
            if (btcMaster.topBearish.isNotEmpty)
              Text('👇 ${btcMaster.topBearish.join(" • ")}',
                  style: const TextStyle(color: Color(0xFFEF4444), fontSize: 10)),
          ]);
        }),
        if (_volScores.isNotEmpty) ...[
          const Divider(color: Color(0xFF1E2838)),
          const Text('🔥 ترتيب العملات حسب السرعة:',
              style: TextStyle(color: Color(0xFFFF6B35), fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          ...(() {
            final sorted = _volScores.values.toList()
              ..sort((a, b) => b.opportunity.compareTo(a.opportunity));
            return sorted.take(10).map((v) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    Text(VolatilityRanker.rankEmoji(v.rank),
                        style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Text(v.symbol.replaceAll('USDT', ''),
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ]),
                  Text('${v.opportunity.toStringAsFixed(0)} | ATR:${v.atrPct.toStringAsFixed(2)}% | Vol:${v.volumeSurge.toStringAsFixed(1)}x',
                      style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 10, fontFamily: 'monospace')),
                ],
              ),
            ));
          })(),
        ],
        if (_marketAnalysis != null) ...[
          const Divider(color: Color(0xFF1E2838)),
          const Text('🌍 حالة السوق العامة:',
              style: TextStyle(color: Color(0xFFF59E0B), fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          _indRow('النظام', MarketRegimeAnalyzer.regimeName(_marketAnalysis!.regime)),
          _indRow('اتجاه BTC 30 شمعة', '${_marketAnalysis!.btcTrendPct.toStringAsFixed(2)}%'),
          _indRow('اتجاه العملات البديلة', '${_marketAnalysis!.altTrendPct.toStringAsFixed(2)}%'),
          _indRow('Altseason Score', _marketAnalysis!.altseasonScore.toStringAsFixed(1)),
          _indRow('Dominance Proxy', _marketAnalysis!.btcDominanceProxy.toStringAsFixed(1)),
          const SizedBox(height: 4),
          Text(_marketAnalysis!.description,
              style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 11)),
        ],
      ]),
    );
  }

  Widget _buildAnalyticsTile(String sym) {
    final hist = _priceHistory[sym]!;
    if (hist.length < 30) return _card('$sym', 'Analyzing... (${hist.length}/30)');
    final rsi = Indicators.rsi(hist, 14);
    final (macd, signal, histogram) = Indicators.macd(hist);
    final (lowBB, midBB, upBB) = Indicators.bollinger(hist);
    final stoch = Indicators.stochastic(_highHistory[sym]!, _lowHistory[sym]!, hist, 14);
    final scalp = _scalpSignals[sym];
    final pump = _pumpScores[sym] ?? 0.0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF131A26), borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1E2838))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(sym, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          if (pump >= 60)
            Text('🔥 ${pump.toInt()}%', style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 12, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 8),
        _indRow('RSI (14)', rsi?.toStringAsFixed(2) ?? '-'),
        _indRow('MACD', macd?.toStringAsFixed(2) ?? '-'),
        _indRow('Signal', signal?.toStringAsFixed(2) ?? '-'),
        _indRow('Histogram', histogram?.toStringAsFixed(2) ?? '-'),
        _indRow('BB L/M/U',
            lowBB != null ? '${lowBB.toStringAsFixed(0)}/${midBB!.toStringAsFixed(0)}/${upBB!.toStringAsFixed(0)}' : '-'),
        _indRow('Stochastic', stoch?.toStringAsFixed(1) ?? '-'),
        const Divider(color: Color(0xFF1E2838)),
        if ((_masterTopStrategies[sym] ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('🎯 الاستراتيجيات: ${_masterTopStrategies[sym]}',
                style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11)),
          ),
        if (scalp != null) ...[
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Scalp Score', style: TextStyle(color: Colors.white70, fontSize: 12)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: scalp.score >= _scalpThreshold ? const Color(0xFF16A34A) : const Color(0xFF1A2332),
                borderRadius: BorderRadius.circular(6)),
              child: Text('${scalp.score}/100', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(scalp.reason, style: const TextStyle(color: Color(0xFF8892A6), fontSize: 11)),
        ],
      ]),
    );
  }

  Widget _buildAnalyticsOld() {
    return ListView.builder(
      padding: const EdgeInsets.all(10), itemCount: _activeSymbols.length,
      itemBuilder: (context, i) {
        final sym = _activeSymbols[i];
        final hist = _priceHistory[sym]!;
        if (hist.length < 30) return _card('$sym', 'Analyzing... (${hist.length}/30)');
        final rsi = Indicators.rsi(hist, 14);
        final (macd, signal, histogram) = Indicators.macd(hist);
        final (lowBB, midBB, upBB) = Indicators.bollinger(hist);
        final stoch = Indicators.stochastic(_highHistory[sym]!, _lowHistory[sym]!, hist, 14);
        final scalp = _scalpSignals[sym];
        return Container(
          margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFF131A26), borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1E2838))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(sym, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            _indRow('RSI (14)', rsi?.toStringAsFixed(2) ?? '-'),
            _indRow('MACD', macd?.toStringAsFixed(2) ?? '-'),
            _indRow('الإشارة', signal?.toStringAsFixed(2) ?? '-'),
            _indRow('الهستوجرام', histogram?.toStringAsFixed(2) ?? '-'),
            _indRow('بولنجر L/M/U',
                lowBB != null ? '${lowBB.toStringAsFixed(0)}/${midBB!.toStringAsFixed(0)}/${upBB!.toStringAsFixed(0)}' : '-'),
            _indRow('الستوكاستيك', stoch?.toStringAsFixed(1) ?? '-'),
            const Divider(color: Color(0xFF1E2838)),
            if (scalp != null) ...[
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('درجة الإسكالبينج', style: TextStyle(color: Colors.white70, fontSize: 12)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: scalp.score >= _scalpThreshold ? const Color(0xFF16A34A) : const Color(0xFF1A2332),
                    borderRadius: BorderRadius.circular(6)),
                  child: Text('${scalp.score}/100', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ]),
              const SizedBox(height: 6),
              Text(scalp.reason, style: const TextStyle(color: Color(0xFF8892A6), fontSize: 11)),
            ],
          ]),
        );
      },
    );
  }

  Widget _indRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        Text(value, style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 12, fontFamily: 'monospace')),
      ]),
    );
  }

  Widget _card(String title, String body) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF131A26), borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1E2838))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 6),
        Text(body, style: const TextStyle(color: Color(0xFF8892A6), fontSize: 12)),
      ]),
    );
  }

  Widget _statBox(String label, String value, Color color) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(value, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold)),
      Text(label, style: const TextStyle(color: Color(0xFF8892A6), fontSize: 10)),
    ]);
  }

  Widget _buildTrades() {
    final openCount = _positions.length;
    final closed = _trades.where((t) => t.pnl != 0).toList();
    final wins = closed.where((t) => t.pnl > 0).length;
    final losses = closed.where((t) => t.pnl < 0).length;
    final totalPnl = closed.fold<double>(0, (s, t) => s + t.pnl);
    final wr = closed.isEmpty ? 0.0 : (wins / closed.length * 100);

    return Column(children: [
      Container(
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF131A26),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF60A5FA)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _statBox('مفتوحة', '$openCount', const Color(0xFF60A5FA)),
          _statBox('رابحة', '$wins', const Color(0xFF4ADE80)),
          _statBox('خاسرة', '$losses', const Color(0xFFEF4444)),
          _statBox('نجاح', '${wr.toStringAsFixed(0)}%', const Color(0xFFF59E0B)),
          _statBox('PnL', '${totalPnl >= 0 ? "+" : ""}\$${totalPnl.toStringAsFixed(1)}',
            totalPnl >= 0 ? const Color(0xFF4ADE80) : const Color(0xFFEF4444)),
        ]),
      ),
      Expanded(
        child: _trades.isEmpty
          ? const Center(child: Text('لا توجد صفقات بعد', style: TextStyle(color: Color(0xFF4B5563))))
          : ListView.builder(
              padding: const EdgeInsets.all(10), itemCount: _trades.length,
              itemBuilder: (context, i) {
                final t = _trades[i];
                Color color = const Color(0xFF4ADE80);
                String label = 'شراء';
                if (t.action == 'SELL') { color = const Color(0xFFEF4444); label = 'بيع'; }
                if (t.action == 'SCALP_BUY') { color = const Color(0xFFF59E0B); label = 'إسكالبينج'; }
                if (t.action == 'STOP_LOSS') { color = const Color(0xFFDC2626); label = 'وقف خسارة'; }
                if (t.action == 'TAKE_PROFIT') { color = const Color(0xFF16A34A); label = 'جني ربح'; }
                if (t.action == 'LIQUIDATED') { color = const Color(0xFFF59E0B); label = 'تصفية'; }
                if (t.action == 'MANUAL') { color = const Color(0xFF60A5FA); label = 'يدوي'; }
                final isEntry = t.action == 'BUY' || t.action == 'SCALP_BUY';
                final priceLabel = isEntry ? 'دخول' : 'خروج';
                return Container(
                  margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2332), borderRadius: BorderRadius.circular(8),
                    border: Border(right: BorderSide(color: color, width: 3))),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('$label ${t.symbol}', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
                      Text('${t.time.hour}:${t.time.minute.toString().padLeft(2, '0')} | $priceLabel: \$${t.price.toStringAsFixed(4)}',
                          style: const TextStyle(color: Color(0xFF8892A6), fontSize: 11)),
                    ]),
                    if (t.pnl != 0)
                      Text('${t.pnl >= 0 ? '+' : ''}\$${t.pnl.toStringAsFixed(2)}',
                          style: TextStyle(color: t.pnl >= 0 ? const Color(0xFF4ADE80) : const Color(0xFFEF4444),
                              fontWeight: FontWeight.bold)),
                  ]),
                );
              },
            ),
      ),
    ]);
  }

  Widget _buildBacktest() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('الاختبار على البيانات المجمعة', style: TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 12),
        for (final sym in _activeSymbols)
          Container(
            margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFF131A26), borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1E2838))),
            child: Builder(builder: (context) {
              final hist = _priceHistory[sym]!;
              if (hist.length < 40) {
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(sym, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text('Not enough data (${hist.length}/40)', style: const TextStyle(color: Color(0xFF8892A6), fontSize: 11)),
                ]);
              }
              final r = Backtester.run(
                prices: hist, smaShort: _smaShort, smaLong: _smaLong,
                rsiBuy: _rsiBuy, rsiSell: _rsiSell,
                leverage: _leverage, marginPerTrade: _marginPerTrade,
              );
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(sym, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 6),
                _indRow('الصفقات', '${r.trades}'),
                _indRow('الرابحة', '${r.wins} (${r.winRate.toStringAsFixed(1)}%)'),
                _indRow('الخاسرة', '${r.losses}'),
                _indRow('النهائي', '\$${r.finalBalance.toStringAsFixed(2)}'),
                _indRow('الربح', '${r.profitPct >= 0 ? '+' : ''}${r.profitPct.toStringAsFixed(2)}%'),
                _indRow('أقصى تراجع', '${r.maxDrawdown.toStringAsFixed(2)}%'),
              ]);
            }),
          ),
      ],
    );
  }

  Widget _buildTestingIndicators() {
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: _indicators.length,
      itemBuilder: (context, i) {
        final ind = _indicators[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF131A26),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ind.approved ? const Color(0xFF16A34A) : const Color(0xFF1E2838)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(child: Text(ind.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: ind.winRate >= 55 ? const Color(0xFF16A34A).withOpacity(0.2) : const Color(0xFF1A2332),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('${ind.winRate.toStringAsFixed(1)}%',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                        color: ind.winRate >= 55 ? const Color(0xFF4ADE80) : const Color(0xFF8892A6))),
              ),
            ]),
            const SizedBox(height: 4),
            Text('${ind.platform} | ${ind.category}',
                style: const TextStyle(color: Color(0xFF8892A6), fontSize: 11)),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Tests: ${ind.tests} | W: ${ind.wins} L: ${ind.losses}',
                  style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 11)),
              TextButton(
                onPressed: () => setState(() { ind.approved = !ind.approved; _saveState(); }),
                child: Text(ind.approved ? 'إزالة' : 'اعتماد',
                    style: TextStyle(color: ind.approved ? const Color(0xFFEF4444) : const Color(0xFF4ADE80), fontSize: 12)),
              ),
            ]),
          ]),
        );
      },
    );
  }

  Widget _buildApprovedIndicators() {
    final approved = _indicators.where((i) => i.approved).toList();
    if (approved.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('لا توجد مؤشرات معتمدة بعد',
              textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF4B5563))),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: approved.length,
      itemBuilder: (context, i) {
        final ind = approved[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF131A26),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF16A34A)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ind.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text('${ind.platform} | ${ind.winRate.toStringAsFixed(1)}%',
                  style: const TextStyle(color: Color(0xFF8892A6), fontSize: 11)),
            ]),
            Text('W: ${ind.weight.toStringAsFixed(2)}',
                style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 12)),
          ]),
        );
      },
    );
  }

  Widget _buildSettings() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('إدارة المخاطر'),
        _settingRow('رأس المال الأولي', _initialCapital.toStringAsFixed(0),
            (v) => setState(() => _initialCapital = double.tryParse(v) ?? _initialCapital)),
        _settingRow('الهامش لكل صفقة', _marginPerTrade.toStringAsFixed(0),
            (v) => setState(() => _marginPerTrade = double.tryParse(v) ?? _marginPerTrade)),
        _settingRow('الرافعة المالية', _leverage.toString(),
            (v) => setState(() => _leverage = int.tryParse(v) ?? _leverage)),
        _settingRow('وقف الخسارة %', _slPercent.toStringAsFixed(2),
            (v) => setState(() => _slPercent = double.tryParse(v) ?? _slPercent)),
        _settingRow('جني الربح %', _tpPercent.toStringAsFixed(2),
            (v) => setState(() => _tpPercent = double.tryParse(v) ?? _tpPercent)),
        const SizedBox(height: 16),
        _sectionTitle('المؤشرات'),
        _settingRow('RSI الشراء', _rsiBuy.toString(),
            (v) => setState(() => _rsiBuy = int.tryParse(v) ?? _rsiBuy)),
        _settingRow('RSI البيع', _rsiSell.toString(),
            (v) => setState(() => _rsiSell = int.tryParse(v) ?? _rsiSell)),
        _settingRow('SMA القصير', _smaShort.toString(),
            (v) => setState(() => _smaShort = int.tryParse(v) ?? _smaShort)),
        _settingRow('SMA الطويل', _smaLong.toString(),
            (v) => setState(() => _smaLong = int.tryParse(v) ?? _smaLong)),
        const SizedBox(height: 16),
        _sectionTitle('وضع التداول'),
        SwitchListTile(
          value: _longBias, onChanged: (v) => setState(() => _longBias = v),
          title: const Text('تفضيل الشراء (LONG Bias)', style: TextStyle(fontSize: 14)),
          subtitle: const Text('تفضيل فتح صفقات الشراء', style: TextStyle(fontSize: 11)),
          activeColor: const Color(0xFF4ADE80),
        ),
        const SizedBox(height: 8),
        _sectionTitle('التركيز على العملات السريعة'),
        SwitchListTile(
          value: _focusFastCoins,
          onChanged: (v) => setState(() => _focusFastCoins = v),
          title: const Text('تفعيل التركيز على العملات السريعة', style: TextStyle(fontSize: 14)),
          subtitle: const Text('يتداول فقط أعلى العملات تحركاً', style: TextStyle(fontSize: 11)),
          activeColor: const Color(0xFFFF6B35),
        ),
        _settingRow('عدد العملات النشطة', '$_maxActiveSymbols',
            (v) => setState(() => _maxActiveSymbols = int.tryParse(v) ?? _maxActiveSymbols)),
        _settingRow('عدد العملات المُختارة', '$_topCoinCount من ${_activeSymbols.length}',
            (v) => setState(() => _topCoinCount = int.tryParse(v) ?? _topCoinCount)),
        const SizedBox(height: 8),
        _sectionTitle('الإسكالبينج'),
        SwitchListTile(
          value: _scalpEnabled, onChanged: (v) => setState(() => _scalpEnabled = v),
          title: const Text('الإسكالبينج التلقائي', style: TextStyle(fontSize: 14)),
          activeColor: const Color(0xFF4ADE80),
        ),
        _settingRow('الحد الأدنى للدرجة', '$_scalpThreshold/100',
            (v) => setState(() => _scalpThreshold = int.tryParse(v) ?? _scalpThreshold)),
        const SizedBox(height: 16),
        _sectionTitle('ربط Binance'),
        _settingRow('مفتاح API', _apiKey.isEmpty ? 'غير مضاف' : '***${_apiKey.substring(_apiKey.length > 4 ? _apiKey.length - 4 : 0)}',
            (v) => setState(() => _apiKey = v)),
        _settingRow('سر API', _apiSecret.isEmpty ? 'غير مضاف' : '******',
            (v) => setState(() => _apiSecret = v)),
        const SizedBox(height: 6),
        const Text('وضع المحاكاة. التداول الحي قادم قريباً',
            style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11)),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E2838), padding: const EdgeInsets.all(14)),
          icon: const Icon(Icons.save, color: Color(0xFF4ADE80)),
          label: const Text('حفظ الإعدادات', style: TextStyle(color: Colors.white)),
          onPressed: () async {
            await _saveState();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم الحفظ'), backgroundColor: Color(0xFF16A34A)),
              );
            }
          },
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), padding: const EdgeInsets.all(14)),
          icon: const Icon(Icons.restart_alt, color: Colors.white),
          label: const Text('إعادة تعيين الكل', style: TextStyle(color: Colors.white)),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: const Color(0xFF131A26),
                title: const Text('إعادة تعيين', style: TextStyle(color: Colors.white)),
                content: const Text('حذف كل الصفقات وإعادة الرصيد؟', style: TextStyle(color: Colors.white70)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
                  TextButton(onPressed: () => Navigator.pop(context, true),
                      child: const Text('نعم', style: TextStyle(color: Color(0xFFEF4444)))),
                ],
              ),
            );
            if (ok == true) {
              await StorageService.clear();
              setState(() {
                _balance = _initialCapital;
                _positions.clear();
                _trades.clear();
                for (final s in _activeSymbols) {
                  _priceHistory[s]!.clear();
                  _highHistory[s]!.clear();
                  _lowHistory[s]!.clear();
                }
              });
            }
          },
        ),
      ],
    );
  }

  Widget _sectionTitle(String s) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(s, style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 14)),
      );

  Widget _settingRow(String label, String value, [ValueChanged<String>? onEdit]) {
    return InkWell(
      onTap: onEdit == null ? null : () => _editValue(label, value, onEdit),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF1A2332)))),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          Row(children: [
            Text(value, style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 13)),
            if (onEdit != null) ...[
              const SizedBox(width: 6),
              const Icon(Icons.edit, size: 14, color: Color(0xFF60A5FA)),
            ],
          ]),
        ]),
      ),
    );
  }

  Future<void> _editValue(String label, String current, ValueChanged<String> onSave) async {
    final c = TextEditingController(text: current);
    final v = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF131A26),
        title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 15)),
        content: TextField(
          controller: c, autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(filled: true, fillColor: const Color(0xFF0A0E17),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(context, c.text),
              child: const Text('Save', style: TextStyle(color: Color(0xFF4ADE80)))),
        ],
      ),
    );
    if (v != null && v.isNotEmpty) onSave(v);
  }

  Widget _buildStartButton() {
    return Container(
      padding: const EdgeInsets.all(12), color: const Color(0xFF131A26),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _running ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _toggleBot,
          child: Text(_running ? 'إيقاف البوت' : 'بدء البوت',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
        ),
      ),
    );
  }
}
