import 'dart:async';
import 'package:flutter/material.dart';
import 'engine.dart' hide Candle;
import 'services.dart';
import 'advanced.dart';
import 'api_candles.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  NotificationService.init().catchError((e) => debugPrint('Notif: $e'));
  runApp(const CryptoBotApp());
}

const List<String> SYMBOLS = [
  'BTCUSDT', 'ETHUSDT', 'BNBUSDT', 'SOLUSDT', 'XRPUSDT', 'DOGEUSDT'
];
const int LOOP_SECONDS = 10;

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
  int _leverage = 10;
  int _rsiBuy = 40;
  int _rsiSell = 60;
  int _smaShort = 5;
  int _smaLong = 10;
  double _slPercent = 1.0;
  double _tpPercent = 1.5;
  int _scalpThreshold = 60;
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
  final List<TradeRecord> _trades = [];
  final Map<String, double> _livePrices = {};

  String _apiKey = '';
  String _apiSecret = '';
  String _lastError = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabs = TabController(length: 7, vsync: this);
    for (final s in SYMBOLS) {
      _priceHistory[s] = [];
      _highHistory[s] = [];
      _lowHistory[s] = [];
      _volumeHistory[s] = [];
    }
    _loadState();
    Timer(const Duration(seconds: 6), () {
      if (!_loaded && mounted) setState(() => _loaded = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tabs.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
    final candles = await CandleService.fetchAll(SYMBOLS);
    if (candles == null) {
      if (mounted) setState(() => _lastError = 'API error');
      return;
    }
    if (!mounted) return;
    setState(() {
      _lastError = '';
      for (final sym in SYMBOLS) {
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
    });
    _saveState();
  }

  void _process(String symbol, double price) {
    final hist = _priceHistory[symbol]!;
    if (hist.length < 30) return;
    final pos = _positions[symbol];
    if (pos != null) {
      if (price <= pos.stopLoss) { _closePosition(symbol, price, 'STOP_LOSS'); return; }
      if (price >= pos.takeProfit) { _closePosition(symbol, price, 'TAKE_PROFIT'); return; }
      final liqPrice = pos.entry * (1 - 1 / pos.leverage);
      if (price <= liqPrice) { _closePosition(symbol, price, 'LIQUIDATED'); return; }
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
      if (rsi > 75 || (ss < sl && rsi > 70)) {
        _closePosition(symbol, price, 'SELL');
      }
      return;
    }
    if (_balance < _marginPerTrade) return;

    if (_longBias) {
      if (signal.direction == 'LONG' && signal.score >= 55) {
        _openPosition(symbol, price, isScalp: signal.score >= 70);
        for (final ind in _indicators) {
          ind.tests++;
          if (signal.score >= 70) ind.wins++;
        }
      }
    } else {
      if (_scalpEnabled && signal.direction == 'LONG' && signal.score >= thr) {
        _openPosition(symbol, price, isScalp: true);
        return;
      }
      if (ss > sl && rsi < _rsiBuy) _openPosition(symbol, price, isScalp: false);
    }
    LearningEngine.updateWeights(_indicators, _trades);
  }

  void _openPosition(String symbol, double price, {required bool isScalp}) {
    final size = (_marginPerTrade * _leverage) / price;
    final sl = price * (1 - _slPercent / 100);
    final tp = price * (1 + _tpPercent / 100);
    _positions[symbol] = Position(
      symbol: symbol, entry: price, size: size, margin: _marginPerTrade,
      stopLoss: sl, takeProfit: tp, leverage: _leverage, isScalp: isScalp,
    );
    _balance -= _marginPerTrade;
    _trades.insert(0, TradeRecord(
      symbol: symbol, action: isScalp ? 'SCALP_BUY' : 'BUY',
      price: price, pnl: 0, time: DateTime.now(), isScalp: isScalp,
    ));
    NotificationService.show(
      isScalp ? 'Scalp' : 'Open',
      '$symbol @ \$${price.toStringAsFixed(2)} SL: \$${sl.toStringAsFixed(2)} TP: \$${tp.toStringAsFixed(2)}',
    );
    if (_trades.length > 200) _trades.removeLast();
  }

  void _closePosition(String symbol, double price, String reason) {
    final pos = _positions[symbol];
    if (pos == null) return;
    final pnl = (price - pos.entry) * pos.size;
    _balance += pos.margin + pnl;
    _trades.insert(0, TradeRecord(
      symbol: symbol, action: reason, price: price, pnl: pnl,
      time: DateTime.now(), isScalp: pos.isScalp,
    ));
    _positions.remove(symbol);
    NotificationService.show('Close $symbol', '$reason PnL: \$${pnl.toStringAsFixed(2)}');
    if (_trades.length > 200) _trades.removeLast();
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
        title: const Text('Crypto Bot Pro v2', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
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
              Text(_running ? 'ON' : 'OFF', style: const TextStyle(fontSize: 12)),
            ]),
          ),
        ],
        bottom: TabBar(
          controller: _tabs, isScrollable: true,
          indicatorColor: const Color(0xFF4ADE80),
          labelColor: const Color(0xFF4ADE80), unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: 'Main'), Tab(text: 'Analysis'),
            Tab(text: 'History'), Tab(text: 'Backtest'), Tab(text: 'Testing'),
            Tab(text: 'Approved'), Tab(text: 'Settings'),
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
          const Text('Balance', style: TextStyle(color: Colors.white54, fontSize: 11)),
          Text('\$${_balance.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF4ADE80))),
        ]),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          const Text('PnL', style: TextStyle(color: Colors.white54, fontSize: 11)),
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
        padding: const EdgeInsets.all(10), itemCount: SYMBOLS.length,
        itemBuilder: (context, i) {
          final sym = SYMBOLS[i];
          final price = _livePrices[sym];
          final hist = _priceHistory[sym]!;
          final rsi = Indicators.rsi(hist, 14);
          final ss = Indicators.sma(hist, _smaShort);
          final sl = Indicators.sma(hist, _smaLong);
          final pos = _positions[sym];
          final scalp = _scalpSignals[sym];
          return Container(
            margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF131A26), borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1E2838)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(sym, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Text(price != null ? '\$${price.toStringAsFixed(2)}' : '...',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 15, color: Color(0xFF60A5FA))),
              ]),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                _chip('RSI', rsi != null ? rsi.toStringAsFixed(1) : '-'),
                _chip('SMA$_smaShort', ss != null ? ss.toStringAsFixed(0) : '-'),
                _chip('SMA$_smaLong', sl != null ? sl.toStringAsFixed(0) : '-'),
                if (scalp != null) _chip('Scalp', '${scalp.score}%',
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
                    Text(pos.isScalp ? 'Scalp' : 'Open',
                        style: TextStyle(color: pos.isScalp ? const Color(0xFFF59E0B) : const Color(0xFF4ADE80), fontSize: 12)),
                    Text('E: \$${pos.entry.toStringAsFixed(2)} | PnL: ${pos.pnl(price ?? pos.entry) >= 0 ? "+" : ""}\$${pos.pnl(price ?? pos.entry).toStringAsFixed(2)}',
                        style: TextStyle(fontSize: 11,
                            color: pos.pnl(price ?? pos.entry) >= 0 ? const Color(0xFF4ADE80) : const Color(0xFFEF4444))),
                  ]),
                ),
              ],
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
    return ListView.builder(
      padding: const EdgeInsets.all(10), itemCount: SYMBOLS.length,
      itemBuilder: (context, i) {
        final sym = SYMBOLS[i];
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
            _indRow('Signal', signal?.toStringAsFixed(2) ?? '-'),
            _indRow('Histogram', histogram?.toStringAsFixed(2) ?? '-'),
            _indRow('BB L/M/U',
                lowBB != null ? '${lowBB.toStringAsFixed(0)}/${midBB!.toStringAsFixed(0)}/${upBB!.toStringAsFixed(0)}' : '-'),
            _indRow('Stochastic', stoch?.toStringAsFixed(1) ?? '-'),
            const Divider(color: Color(0xFF1E2838)),
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

  Widget _buildTrades() {
    if (_trades.isEmpty) {
      return const Center(child: Text('No trades yet', style: TextStyle(color: Color(0xFF4B5563))));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(10), itemCount: _trades.length,
      itemBuilder: (context, i) {
        final t = _trades[i];
        Color color = const Color(0xFF4ADE80);
        String label = 'BUY';
        if (t.action == 'SELL') { color = const Color(0xFFEF4444); label = 'SELL'; }
        if (t.action == 'SCALP_BUY') { color = const Color(0xFFF59E0B); label = 'SCALP'; }
        if (t.action == 'STOP_LOSS') { color = const Color(0xFFDC2626); label = 'SL'; }
        if (t.action == 'TAKE_PROFIT') { color = const Color(0xFF16A34A); label = 'TP'; }
        if (t.action == 'LIQUIDATED') { color = const Color(0xFFF59E0B); label = 'LIQ'; }
        return Container(
          margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF1A2332), borderRadius: BorderRadius.circular(8),
            border: Border(right: BorderSide(color: color, width: 3))),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$label ${t.symbol}', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
              Text('${t.time.hour}:${t.time.minute.toString().padLeft(2, '0')} \$${t.price.toStringAsFixed(2)}',
                  style: const TextStyle(color: Color(0xFF8892A6), fontSize: 11)),
            ]),
            if (t.pnl != 0)
              Text('${t.pnl >= 0 ? '+' : ''}\$${t.pnl.toStringAsFixed(2)}',
                  style: TextStyle(color: t.pnl >= 0 ? const Color(0xFF4ADE80) : const Color(0xFFEF4444),
                      fontWeight: FontWeight.bold)),
          ]),
        );
      },
    );
  }

  Widget _buildBacktest() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Backtest on collected data', style: TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 12),
        for (final sym in SYMBOLS)
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
                _indRow('Trades', '${r.trades}'),
                _indRow('Wins', '${r.wins} (${r.winRate.toStringAsFixed(1)}%)'),
                _indRow('Losses', '${r.losses}'),
                _indRow('Final', '\$${r.finalBalance.toStringAsFixed(2)}'),
                _indRow('Profit', '${r.profitPct >= 0 ? '+' : ''}${r.profitPct.toStringAsFixed(2)}%'),
                _indRow('Max DD', '${r.maxDrawdown.toStringAsFixed(2)}%'),
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
                child: Text(ind.approved ? 'Remove' : 'Approve',
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
          child: Text('No approved indicators yet.',
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
        _sectionTitle('Risk Management'),
        _settingRow('Initial Capital', _initialCapital.toStringAsFixed(0),
            (v) => setState(() => _initialCapital = double.tryParse(v) ?? _initialCapital)),
        _settingRow('Margin per Trade', _marginPerTrade.toStringAsFixed(0),
            (v) => setState(() => _marginPerTrade = double.tryParse(v) ?? _marginPerTrade)),
        _settingRow('Leverage', _leverage.toString(),
            (v) => setState(() => _leverage = int.tryParse(v) ?? _leverage)),
        _settingRow('Stop Loss %', _slPercent.toStringAsFixed(2),
            (v) => setState(() => _slPercent = double.tryParse(v) ?? _slPercent)),
        _settingRow('Take Profit %', _tpPercent.toStringAsFixed(2),
            (v) => setState(() => _tpPercent = double.tryParse(v) ?? _tpPercent)),
        const SizedBox(height: 16),
        _sectionTitle('Indicators'),
        _settingRow('RSI Buy', _rsiBuy.toString(),
            (v) => setState(() => _rsiBuy = int.tryParse(v) ?? _rsiBuy)),
        _settingRow('RSI Sell', _rsiSell.toString(),
            (v) => setState(() => _rsiSell = int.tryParse(v) ?? _rsiSell)),
        _settingRow('SMA Short', _smaShort.toString(),
            (v) => setState(() => _smaShort = int.tryParse(v) ?? _smaShort)),
        _settingRow('SMA Long', _smaLong.toString(),
            (v) => setState(() => _smaLong = int.tryParse(v) ?? _smaLong)),
        const SizedBox(height: 16),
        _sectionTitle('Trading Mode'),
        SwitchListTile(
          value: _longBias, onChanged: (v) => setState(() => _longBias = v),
          title: const Text('LONG Bias (Buy heavy)', style: TextStyle(fontSize: 14)),
          subtitle: const Text('Prefer opening BUY positions', style: TextStyle(fontSize: 11)),
          activeColor: const Color(0xFF4ADE80),
        ),
        const SizedBox(height: 8),
        _sectionTitle('Scalping'),
        SwitchListTile(
          value: _scalpEnabled, onChanged: (v) => setState(() => _scalpEnabled = v),
          title: const Text('Auto Scalping', style: TextStyle(fontSize: 14)),
          activeColor: const Color(0xFF4ADE80),
        ),
        _settingRow('Min Score', '$_scalpThreshold/100',
            (v) => setState(() => _scalpThreshold = int.tryParse(v) ?? _scalpThreshold)),
        const SizedBox(height: 16),
        _sectionTitle('Binance API'),
        _settingRow('API Key', _apiKey.isEmpty ? 'Not set' : '***${_apiKey.substring(_apiKey.length > 4 ? _apiKey.length - 4 : 0)}',
            (v) => setState(() => _apiKey = v)),
        _settingRow('API Secret', _apiSecret.isEmpty ? 'Not set' : '******',
            (v) => setState(() => _apiSecret = v)),
        const SizedBox(height: 6),
        const Text('Simulation mode. Live trading coming soon.',
            style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11)),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E2838), padding: const EdgeInsets.all(14)),
          icon: const Icon(Icons.save, color: Color(0xFF4ADE80)),
          label: const Text('Save Settings', style: TextStyle(color: Colors.white)),
          onPressed: () async {
            await _saveState();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Saved'), backgroundColor: Color(0xFF16A34A)),
              );
            }
          },
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), padding: const EdgeInsets.all(14)),
          icon: const Icon(Icons.restart_alt, color: Colors.white),
          label: const Text('Reset All', style: TextStyle(color: Colors.white)),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: const Color(0xFF131A26),
                title: const Text('Reset', style: TextStyle(color: Colors.white)),
                content: const Text('Delete all trades and reset balance?', style: TextStyle(color: Colors.white70)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                  TextButton(onPressed: () => Navigator.pop(context, true),
                      child: const Text('Yes', style: TextStyle(color: Color(0xFFEF4444)))),
                ],
              ),
            );
            if (ok == true) {
              await StorageService.clear();
              setState(() {
                _balance = _initialCapital;
                _positions.clear();
                _trades.clear();
                for (final s in SYMBOLS) {
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
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
          child: Text(_running ? 'STOP BOT' : 'START BOT',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
        ),
      ),
    );
  }
}
