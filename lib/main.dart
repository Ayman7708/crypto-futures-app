import 'dart:async';
import 'package:flutter/material.dart';
import 'engine.dart';
import 'services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
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
    _tabs = TabController(length: 5, vsync: this);
    for (final s in SYMBOLS) {
      _priceHistory[s] = [];
      _highHistory[s] = [];
      _lowHistory[s] = [];
    }
    _loadState();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tabs.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadState() async {
    final data = await StorageService.loadAll();
    if (data != null && mounted) {
      setState(() {
        _balance = (data['balance'] as num).toDouble();
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

        final hist = data['history'] as Map<String, dynamic>;
        hist.forEach((k, v) {
          _priceHistory[k] = (v as List).map((e) => (e as num).toDouble()).toList();
        });

        final posRaw = data['positions'] as Map<String, dynamic>;
        posRaw.forEach((k, v) {
          _positions[k] = Position(
            symbol: k,
            entry: (v['entry'] as num).toDouble(),
            size: (v['size'] as num).toDouble(),
            margin: (v['margin'] as num).toDouble(),
            stopLoss: (v['sl'] as num).toDouble(),
            takeProfit: (v['tp'] as num).toDouble(),
            leverage: (v['leverage'] as num).toInt(),
            isScalp: v['isScalp'] ?? false,
          );
        });

        final tr = data['trades'] as List;
        for (final t in tr) {
          _trades.add(TradeRecord.fromJson(t as Map<String, dynamic>));
        }
        _loaded = true;
      });
    } else {
      setState(() => _loaded = true);
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
      balance: _balance,
      positions: posMap,
      trades: _trades.map((t) => t.toJson()).toList(),
      settings: {
        'initialCapital': _initialCapital, 'margin': _marginPerTrade,
        'leverage': _leverage, 'rsiBuy': _rsiBuy, 'rsiSell': _rsiSell,
        'smaShort': _smaShort, 'smaLong': _smaLong, 'slPercent': _slPercent,
        'tpPercent': _tpPercent, 'scalpThreshold': _scalpThreshold,
        'scalpEnabled': _scalpEnabled, 'apiKey': _apiKey, 'apiSecret': _apiSecret,
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
    final prices = await ApiService.fetchPrices(SYMBOLS);
    if (prices == null) {
      setState(() => _lastError = 'فشل الاتصال بـ Binance API');
      return;
    }
    if (!mounted) return;
    setState(() {
      _lastError = '';
      _livePrices.addAll(prices);
      for (final sym in SYMBOLS) {
        final p = prices[sym];
        if (p == null) continue;
        _priceHistory[sym]!.add(p);
        _highHistory[sym]!.add(p * 1.001);
        _lowHistory[sym]!.add(p * 0.999);
        if (_priceHistory[sym]!.length > 200) {
          _priceHistory[sym]!.removeAt(0);
          _highHistory[sym]!.removeAt(0);
          _lowHistory[sym]!.removeAt(0);
        }
        _process(sym, p);
      }
    });
    _saveState();
  }

  void _process(String symbol, double price) {
    final hist = _priceHistory[symbol]!;
    if (hist.length < 30) return;

    final pos = _positions[symbol];

    // SL / TP check
    if (pos != null) {
      if (price <= pos.stopLoss) {
        _closePosition(symbol, price, 'STOP_LOSS');
        return;
      }
      if (price >= pos.takeProfit) {
        _closePosition(symbol, price, 'TAKE_PROFIT');
        return;
      }
      // Liquidation
      final liqPrice = pos.entry * (1 - 1 / pos.leverage);
      if (price <= liqPrice) {
        _closePosition(symbol, price, 'LIQUIDATED');
        return;
      }
    }

    final ss = Indicators.sma(hist, _smaShort);
    final sl = Indicators.sma(hist, _smaLong);
    final rsi = Indicators.rsi(hist, 14);
    if (ss == null || sl == null || rsi == null) return;

    // Scalp analysis
    final scalp = ScalpAnalyzer.analyze(
      closes: hist, highs: _highHistory[symbol]!, lows: _lowHistory[symbol]!,
      smaShort: _smaShort, smaLong: _smaLong, rsiBuy: _rsiBuy,
    );
    _scalpSignals[symbol] = scalp;

    if (pos != null) {
      // Exit if SMA crosses down and RSI overbought
      if (ss < sl && rsi > _rsiSell) {
        _closePosition(symbol, price, 'SELL');
      }
      return;
    }

    if (_balance < _marginPerTrade) return;

    // Scalp entry (priority)
    if (_scalpEnabled && scalp.direction == 'LONG' && scalp.score >= _scalpThreshold) {
      _openPosition(symbol, price, isScalp: true);
      return;
    }

    // Normal entry
    if (ss > sl && rsi < _rsiBuy) {
      _openPosition(symbol, price, isScalp: false);
    }
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
      isScalp ? '⚡ صفقة إسكالبينج' : '🟢 فتح صفقة',
      '$symbol @ \$${price.toStringAsFixed(2)}\nSL: \$${sl.toStringAsFixed(2)} | TP: \$${tp.toStringAsFixed(2)}',
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

    String emoji = '🔴';
    if (reason == 'TAKE_PROFIT') emoji = '🎯';
    if (reason == 'STOP_LOSS') emoji = '🛑';
    if (reason == 'LIQUIDATED') emoji = '💥';
    if (reason == 'SELL') emoji = '🔵';

    NotificationService.show(
      '$emoji إغلاق صفقة $symbol',
      'السبب: $reason\nPnL: ${pnl >= 0 ? "+" : ""}\$${pnl.toStringAsFixed(2)}',
    );
    if (_trades.length > 200) _trades.removeLast();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // keep running; real background requires foreground service
    super.didChangeAppLifecycleState(state);
  }

  // ==================== UI ====================
  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crypto Bot Pro v2', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        actions: [
          if (_lastError.isNotEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Icon(Icons.wifi_off, color: Color(0xFFEF4444), size: 20),
            ),
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
          labelColor: const Color(0xFF4ADE80),
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: 'الرئيسية'),
            Tab(text: 'التحليل'),
            Tab(text: 'السجل'),
            Tab(text: 'الاختبار'),
            Tab(text: 'الإعدادات'),
          ],
        ),
      ),
      body: Column(children: [
        _buildBalanceBar(),
        Expanded(child: TabBarView(controller: _tabs, children: [
          _buildDashboard(),
          _buildAnalytics(),
          _buildTrades(),
          _buildBacktest(),
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
          const Text('PnL', style: TextStyle(color: Colors.white54, fontSize: 11)),
          Text('${pnl >= 0 ? '+' : ''}\$${pnl.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          Text('${pnl >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
              style: TextStyle(fontSize: 11, color: color)),
        ]),
      ]),
    );
  }

  Widget _buildDashboard() {
    return RefreshIndicator(
      onRefresh: _tick,
      child: ListView.builder(
        padding: const EdgeInsets.all(10),
        itemCount: SYMBOLS.length,
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
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF131A26),
              borderRadius: BorderRadius.circular(12),
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
                _chip('RSI', rsi != null ? rsi.toStringAsFixed(1) : '—'),
                _chip('SMA$_smaShort', ss != null ? ss.toStringAsFixed(0) : '—'),
                _chip('SMA$_smaLong', sl != null ? sl.toStringAsFixed(0) : '—'),
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
                      color: pos.isScalp ? const Color(0xFFF59E0B) : const Color(0xFF4ADE80),
                      width: 3,
                    )),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(pos.isScalp ? '⚡ إسكالبينج' : 'مركز مفتوح',
                        style: TextStyle(color: pos.isScalp ? const Color(0xFFF59E0B) : const Color(0xFF4ADE80), fontSize: 12)),
                    Text('D: \$${pos.entry.toStringAsFixed(2)} | PnL: ${pos.pnl(price ?? pos.entry) >= 0 ? "+" : ""}\$${pos.pnl(price ?? pos.entry).toStringAsFixed(2)}',
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
          style: TextStyle(fontSize: 11, color: color ?? const Color(0xFF8892A6), fontWeight: color != null ? FontWeight.bold : FontWeight.normal)),
    );
  }

  Widget _buildAnalytics() {
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: SYMBOLS.length,
      itemBuilder: (context, i) {
        final sym = SYMBOLS[i];
        final hist = _priceHistory[sym]!;
        if (hist.length < 30) {
          return _card('$sym', 'جاري تحليل البيانات... (${hist.length}/30)');
        }
        final rsi = Indicators.rsi(hist, 14);
        final (macd, signal, histogram) = Indicators.macd(hist);
        final (lowBB, midBB, upBB) = Indicators.bollinger(hist);
        final stoch = Indicators.stochastic(_highHistory[sym]!, _lowHistory[sym]!, hist, 14);
        final scalp = _scalpSignals[sym];

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFF131A26), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF1E2838))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(sym, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            _indRow('RSI (14)', rsi?.toStringAsFixed(2) ?? '—'),
            _indRow('MACD', macd?.toStringAsFixed(2) ?? '—'),
            _indRow('Signal', signal?.toStringAsFixed(2) ?? '—'),
            _indRow('Histogram', histogram?.toStringAsFixed(2) ?? '—'),
            _indRow('BB Lower / Mid / Upper',
                lowBB != null ? '${lowBB.toStringAsFixed(0)} / ${midBB!.toStringAsFixed(0)} / ${upBB!.toStringAsFixed(0)}' : '—'),
            _indRow('Stochastic', stoch?.toStringAsFixed(1) ?? '—'),
            const Divider(color: Color(0xFF1E2838)),
            if (scalp != null) ...[
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Scalp Score', style: TextStyle(color: Colors.white70, fontSize: 12)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: scalp.score >= _scalpThreshold ? const Color(0xFF16A34A) : const Color(0xFF1A2332),
                    borderRadius: BorderRadius.circular(6),
                  ),
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
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF131A26), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF1E2838))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 6),
        Text(body, style: const TextStyle(color: Color(0xFF8892A6), fontSize: 12)),
      ]),
    );
  }

  Widget _buildTrades() {
    if (_trades.isEmpty) {
      return const Center(child: Text('لا توجد صفقات بعد', style: TextStyle(color: Color(0xFF4B5563))));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: _trades.length,
      itemBuilder: (context, i) {
        final t = _trades[i];
        Color color = const Color(0xFF4ADE80);
        String label = '🟢 شراء';
        if (t.action == 'SELL') { color = const Color(0xFFEF4444); label = '🔵 بيع'; }
        if (t.action == 'SCALP_BUY') { color = const Color(0xFFF59E0B); label = '⚡ إسكالبينج'; }
        if (t.action == 'STOP_LOSS') { color = const Color(0xFFDC2626); label = '🛑 SL'; }
        if (t.action == 'TAKE_PROFIT') { color = const Color(0xFF16A34A); label = '🎯 TP'; }
        if (t.action == 'LIQUIDATED') { color = const Color(0xFFF59E0B); label = '💥 تصفية'; }

        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF1A2332),
            borderRadius: BorderRadius.circular(8),
            border: Border(right: BorderSide(color: color, width: 3)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$label ${t.symbol}', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
              Text('${t.time.hour}:${t.time.minute.toString().padLeft(2, '0')} • \$${t.price.toStringAsFixed(2)}',
                  style: const TextStyle(color: Color(0xFF8892A6), fontSize: 11)),
            ]),
            if (t.pnl != 0)
              Text('${t.pnl >= 0 ? '+' : ''}\$${t.pnl.toStringAsFixed(2)}',
                  style: TextStyle(color: t.pnl >= 0 ? const Color(0xFF4ADE80) : const Color(0xFFEF4444), fontWeight: FontWeight.bold)),
          ]),
        );
      },
    );
  }

  Widget _buildBacktest() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('اختبار الاستراتيجية على البيانات المجمعة', style: TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 12),
        for (final sym in SYMBOLS)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFF131A26), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF1E2838))),
            child: Builder(builder: (context) {
              final hist = _priceHistory[sym]!;
              if (hist.length < 40) {
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(sym, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text('بيانات غير كافية (${hist.length}/40)', style: const TextStyle(color: Color(0xFF8892A6), fontSize: 11)),
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
                _indRow('عدد الصفقات', '${r.trades}'),
                _indRow('الرابحة', '${r.wins} (${r.winRate.toStringAsFixed(1)}%)'),
                _indRow('الخاسرة', '${r.losses}'),
                _indRow('الرصيد النهائي', '\$${r.finalBalance.toStringAsFixed(2)}'),
                _indRow('العائد', '${r.profitPct >= 0 ? '+' : ''}${r.profitPct.toStringAsFixed(2)}%'),
                _indRow('أقصى تراجع', '${r.maxDrawdown.toStringAsFixed(2)}%'),
              ]);
            }),
          ),
      ],
    );
  }

  Widget _buildSettings() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('إدارة المخاطر'),
        _settingRow('رأس المال الأولي', _initialCapital.toStringAsFixed(0), (v) => setState(() => _initialCapital = double.tryParse(v) ?? _initialCapital)),
        _settingRow('الهامش لكل صفقة', _marginPerTrade.toStringAsFixed(0), (v) => setState(() => _marginPerTrade = double.tryParse(v) ?? _marginPerTrade)),
        _settingRow('الرافعة المالية', _leverage.toString(), (v) => setState(() => _leverage = int.tryParse(v) ?? _leverage)),
        _settingRow('وقف الخسارة SL %', _slPercent.toStringAsFixed(2), (v) => setState(() => _slPercent = double.tryParse(v) ?? _slPercent)),
        _settingRow('جني الربح TP %', _tpPercent.toStringAsFixed(2), (v) => setState(() => _tpPercent = double.tryParse(v) ?? _tpPercent)),
        const SizedBox(height: 16),
        _sectionTitle('المؤشرات'),
        _settingRow('RSI الشراء', _rsiBuy.toString(), (v) => setState(() => _rsiBuy = int.tryParse(v) ?? _rsiBuy)),
        _settingRow('RSI البيع', _rsiSell.toString(), (v) => setState(() => _rsiSell = int.tryParse(v) ?? _rsiSell)),
        _settingRow('SMA القصير', _smaShort.toString(), (v) => setState(() => _smaShort = int.tryParse(v) ?? _smaShort)),
        _settingRow('SMA الطويل', _smaLong.toString(), (v) => setState(() => _smaLong = int.tryParse(v) ?? _smaLong)),
        const SizedBox(height: 16),
        _sectionTitle('الإسكالبينج'),
        SwitchListTile(
          value: _scalpEnabled, onChanged: (v) => setState(() => _scalpEnabled = v),
          title: const Text('تفعيل الإسكالبينج التلقائي', style: TextStyle(fontSize: 14)),
          activeColor: const Color(0xFF4ADE80),
        ),
        _settingRow('الحد الأدنى للتحليل', '$_scalpThreshold/100', (v) => setState(() => _scalpThreshold = int.tryParse(v) ?? _scalpThreshold)),
        const SizedBox(height: 16),
        _sectionTitle('ربط الحساب (Binance Futures)'),
        _settingRow('API Key', _apiKey.isEmpty ? 'غير مضاف' : '•••${_apiKey.substring(_apiKey.length > 4 ? _apiKey.length - 4 : 0)}', (v) => setState(() => _apiKey = v)),
        _settingRow('API Secret', _apiSecret.isEmpty ? 'غير مضاف' : '••••••••', (v) => setState(() => _apiSecret = v)),
        const SizedBox(height: 6),
        const Text('⚠️ سيتم استخدام المفاتيح في تحديث قادم. حالياً التطبيق في وضع المحاكاة.',
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
                const SnackBar(content: Text('✅ تم حفظ الإعدادات'), backgroundColor: Color(0xFF16A34A)),
              );
            }
          },
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), padding: const EdgeInsets.all(14)),
          icon: const Icon(Icons.restart_alt, color: Colors.white),
          label: const Text('إعادة تعيين كل شيء', style: TextStyle(color: Colors.white)),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: const Color(0xFF131A26),
                title: const Text('إعادة تعيين', style: TextStyle(color: Colors.white)),
                content: const Text('سيتم مسح كل الصفقات والرصيد. متأكد؟', style: TextStyle(color: Colors.white70)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
                  TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('نعم', style: TextStyle(color: Color(0xFFEF4444)))),
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
          decoration: InputDecoration(filled: true, fillColor: const Color(0xFF0A0E17), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('حفظ', style: TextStyle(color: Color(0xFF4ADE80)))),
        ],
      ),
    );
    if (v != null && v.isNotEmpty) onSave(v);
  }

  Widget _buildStartButton() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: const Color(0xFF131A26),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _running ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _toggleBot,
          child: Text(
            _running ? '⏹ إيقاف البوت' : '▶ بدء البوت',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
