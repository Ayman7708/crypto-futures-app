import 'dart:async';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'api_candles.dart';
import 'engine.dart';
import 'indicators.dart';
import 'risk.dart';
import 'services.dart';
import 'backtest.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  NotificationService.init().catchError((e) => debugPrint('Notif: $e'));
  runApp(const CryptoBotApp());
}

const List<String> WATCH_SYMBOLS = [
  'BTCUSDT', 'ETHUSDT', 'BNBUSDT', 'SOLUSDT', 'XRPUSDT',
  'DOGEUSDT', 'ADAUSDT', 'AVAXUSDT', 'LINKUSDT', 'DOTUSDT',
];

const int LOOP_SECONDS = 60;

class CryptoBotApp extends StatelessWidget {
  const CryptoBotApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Swing Trend Bot',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0E17),
        primaryColor: const Color(0xFF4ADE80),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF131A26), elevation: 0),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4ADE80),
          secondary: Color(0xFF60A5FA),
        ),
      ),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;

  double _balance = 1000.0;
  final double _initialCapital = 1000.0;
  final int _leverage = 3;
  bool _running = false;
  bool _loaded = false;
  String _dailyStatus = '';

  final Map<String, Position> _positions = {};
  final List<TradeRecord> _trades = [];
  final Map<String, Signal> _signals = {};
  final Map<String, List<double>> _closes1h = {};
  final Map<String, List<double>> _highs1h = {};
  final Map<String, List<double>> _lows1h = {};
  final Map<String, List<double>> _volumes1h = {};
  final Map<String, List<double>> _closes4h = {};
  final Map<String, double> _prices = {};
  final Map<String, String> _trends = {};

  final RiskManager _risk = RiskManager();
  Timer? _timer;

  // Backtest state
  List<BacktestResult> _backtestResults = [];
  bool _backtesting = false;
  String _backtestMsg = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    for (final s in WATCH_SYMBOLS) {
      _closes1h[s] = [];
      _highs1h[s] = [];
      _lows1h[s] = [];
      _volumes1h[s] = [];
      _closes4h[s] = [];
    }
    _loadState();
    Timer(const Duration(seconds: 4), () {
      if (!_loaded && mounted) setState(() => _loaded = true);
    });
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _timer?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadState() async {
    try {
      final data = await StorageService.loadAll().timeout(const Duration(seconds: 4));
      if (data != null && mounted) {
        setState(() {
          _balance = (data['balance'] as num?)?.toDouble() ?? 1000.0;
          _risk.initialize(_balance);
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _saveState() async {
    try {
      final posMap = <String, dynamic>{};
      _positions.forEach((k, v) => posMap[k] = v.toJson());
      await StorageService.saveAll(
        balance: _balance,
        positions: posMap,
        trades: _trades.map((t) => t.toJson()).toList(),
        settings: {'risk': _risk.toJson()},
      );
    } catch (_) {}
  }

  void _toggleBot() {
    if (_running) {
      _timer?.cancel();
      setState(() => _running = false);
      WakelockPlus.disable();
    } else {
      setState(() => _running = true);
      WakelockPlus.enable();
      _tick();
      _timer = Timer.periodic(const Duration(seconds: LOOP_SECONDS), (_) => _tick());
    }
  }

  Future<void> _tick() async {
    for (final sym in WATCH_SYMBOLS) {
      try {
        // Fetch 4h candles (only every 4h but simple to fetch every loop)
        final c4h = await CandleService.fetchCandles(sym, interval: '4h', limit: 250);
        if (c4h != null && c4h.isNotEmpty) {
          _closes4h[sym] = c4h.map((c) => c.close).toList();
        }
        await Future.delayed(const Duration(milliseconds: 60));

        // Fetch 1h candles
        final c1h = await CandleService.fetchCandles(sym, interval: '1h', limit: 250);
        if (c1h == null || c1h.isEmpty) continue;
        _closes1h[sym] = c1h.map((c) => c.close).toList();
        _highs1h[sym] = c1h.map((c) => c.high).toList();
        _lows1h[sym] = c1h.map((c) => c.low).toList();
        _volumes1h[sym] = c1h.map((c) => c.volume).toList();
        _prices[sym] = c1h.last.close;

        await Future.delayed(const Duration(milliseconds: 60));

        if (!mounted) return;
        setState(() => _processSymbol(sym));
      } catch (e) {
        debugPrint('Tick error $sym: $e');
      }
    }
    if (mounted) _saveState();
  }

  void _processSymbol(String sym) {
    final price = _prices[sym];
    if (price == null) return;

    // Trend
    final trend = StrategyAnalyzer.trend4h(closes4h: _closes4h[sym] ?? []);
    _trends[sym] = trend;

    // Check open position for SL/TP
    final pos = _positions[sym];
    if (pos != null) {
      final slHit = pos.isLong ? price <= pos.stopLoss : price >= pos.stopLoss;
      final tpHit = pos.isLong ? price >= pos.takeProfit : price <= pos.takeProfit;
      if (slHit || tpHit) {
        _closePosition(sym, price, slHit ? 'STOP_LOSS' : 'TAKE_PROFIT');
        return;
      }
    }

    // Analyze for entry
    final signal = StrategyAnalyzer.analyze(
      symbol: sym,
      closes1h: _closes1h[sym] ?? [],
      highs1h: _highs1h[sym] ?? [],
      lows1h: _lows1h[sym] ?? [],
      volumes1h: _volumes1h[sym] ?? [],
      trend: trend,
      leverage: _leverage,
      balance: _balance,
      riskPct: RiskManager.riskPerTrade,
    );
    _signals[sym] = signal;

    _dailyStatus = _risk.statusMessage;

    // Auto-entry if bot is running
    if (_running && pos == null && signal.isValid) {
      if (!_risk.canOpen(currentPositions: _positions.length, balance: _balance)) {
        return;
      }
      _openPosition(sym, signal);
    }
  }

  void _openPosition(String sym, Signal signal) {
    final margin = _risk.calculateMargin(
      balance: _balance,
      entry: signal.entry,
      stopLoss: signal.stopLoss,
      leverage: _leverage,
    );
    if (margin <= 0 || margin > _balance) return;

    final size = (margin * _leverage) / signal.entry;
    _positions[sym] = Position(
      symbol: sym,
      entry: signal.entry,
      size: size,
      margin: margin,
      stopLoss: signal.stopLoss,
      takeProfit: signal.takeProfit,
      leverage: _leverage,
      isLong: signal.direction == 'LONG',
    );
    _balance -= margin;
    _risk.recordOpen();
    _trades.insert(0, TradeRecord(
      symbol: sym,
      action: signal.direction == 'LONG' ? 'BUY' : 'SELL_SHORT',
      price: signal.entry,
      pnl: 0,
      time: DateTime.now(),
      isLong: signal.direction == 'LONG',
    ));
    NotificationService.show(
      signal.direction == 'LONG' ? '🟢 شراء $sym' : '🔴 بيع $sym',
      'سعر: \$${signal.entry.toStringAsFixed(2)} | قوة: ${signal.score}',
    );
  }

  void _closePosition(String sym, double price, String reason) {
    final pos = _positions[sym];
    if (pos == null) return;
    final pnl = pos.pnl(price);
    _balance += pos.margin + pnl;
    _positions.remove(sym);
    _risk.recordClose(pnl);

    _trades.insert(0, TradeRecord(
      symbol: sym,
      action: reason,
      price: price,
      pnl: pnl,
      time: DateTime.now(),
      isLong: pos.isLong,
    ));

    NotificationService.show(
      pnl >= 0 ? '🎯 ربح $sym' : '🛑 خسارة $sym',
      '$reason | PnL: \$${pnl.toStringAsFixed(2)} | الرصيد: \$${_balance.toStringAsFixed(2)}',
    );
    if (_trades.length > 200) _trades.removeLast();
  }

  void _manualOpen(String sym) {
    final sig = _signals[sym];
    if (sig == null || !sig.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد إشارة صالحة'), backgroundColor: Color(0xFFEF4444)),
      );
      return;
    }
    if (_positions.containsKey(sym)) return;
    setState(() => _openPosition(sym, sig));
  }

  void _manualClose(String sym) {
    final price = _prices[sym];
    if (price == null) return;
    setState(() => _closePosition(sym, price, 'MANUAL'));
  }

  Future<void> _runBacktest() async {
    setState(() {
      _backtesting = true;
      _backtestMsg = 'جاري الاختبار... قد يستغرق دقيقة';
      _backtestResults = [];
    });

    try {
      final results = await BacktestEngine.runAll(
        symbols: WATCH_SYMBOLS.take(5).toList(),
        daysToTest: 30,
      );
      if (!mounted) return;
      setState(() {
        _backtestResults = results;
        _backtesting = false;
        _backtestMsg = results.isEmpty ? 'لم تُجمع بيانات كافية' : 'انتهى الاختبار';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _backtesting = false;
        _backtestMsg = 'خطأ: $e';
      });
    }
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
        title: const Text('Swing Trend Bot V9',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        actions: [
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
          controller: _tabs,
          indicatorColor: const Color(0xFF4ADE80),
          labelColor: const Color(0xFF4ADE80),
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: 'الرئيسية'),
            Tab(text: 'السجل'),
            Tab(text: 'الاختبار'),
          ],
        ),
      ),
      body: Column(children: [
        _buildBalanceBar(),
        Expanded(child: TabBarView(controller: _tabs, children: [
          _buildMain(),
          _buildTrades(),
          _buildBacktest(),
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
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('الرصيد', style: TextStyle(color: Colors.white54, fontSize: 11)),
            Text('\$${_balance.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF4ADE80))),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            const Text('الربح / الخسارة', style: TextStyle(color: Colors.white54, fontSize: 11)),
            Text('${pnl >= 0 ? '+' : ''}\$${pnl.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
            Text('${pnl >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
                style: TextStyle(fontSize: 11, color: color)),
          ]),
        ]),
        if (_dailyStatus.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_dailyStatus,
                style: const TextStyle(fontSize: 10, color: Color(0xFF8892A6))),
          ),
      ]),
    );
  }

  Widget _buildMain() {
    return RefreshIndicator(
      onRefresh: _tick,
      child: ListView.builder(
        padding: const EdgeInsets.all(10),
        itemCount: WATCH_SYMBOLS.length,
        itemBuilder: (context, i) {
          final sym = WATCH_SYMBOLS[i];
          final price = _prices[sym];
          final signal = _signals[sym];
          final trend = _trends[sym] ?? '---';
          final pos = _positions[sym];

          final trendColor = trend == 'BULL' ? const Color(0xFF4ADE80)
              : trend == 'BEAR' ? const Color(0xFFEF4444)
              : const Color(0xFF8892A6);
          final dirColor = signal?.direction == 'LONG' ? const Color(0xFF4ADE80)
              : signal?.direction == 'SHORT' ? const Color(0xFFEF4444)
              : const Color(0xFF8892A6);
          final dirLabel = signal?.direction == 'LONG' ? 'شراء'
              : signal?.direction == 'SHORT' ? 'بيع'
              : 'انتظار';

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
                Text(price != null ? '\$${price.toStringAsFixed(price < 1 ? 4 : 2)}' : '...',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 15, color: Color(0xFF60A5FA))),
              ]),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                _chip('اتجاه', trend == 'BULL' ? 'صاعد' : trend == 'BEAR' ? 'هابط' : 'عرضي', trendColor),
                _chip('إشارة', dirLabel, dirColor),
                if (signal != null) _chip('قوة', '${signal.score}', dirColor),
              ]),
              if (signal != null && signal.reason.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(signal.reason,
                    style: const TextStyle(color: Color(0xFF8892A6), fontSize: 10)),
              ],
              if (pos != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2332),
                    border: Border(right: BorderSide(
                      color: pos.isLong ? const Color(0xFF4ADE80) : const Color(0xFFEF4444),
                      width: 3,
                    )),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(pos.isLong ? 'شراء مفتوح' : 'بيع مفتوح',
                        style: TextStyle(
                          color: pos.isLong ? const Color(0xFF4ADE80) : const Color(0xFFEF4444),
                          fontSize: 12,
                        )),
                    Text('دخول: \$${pos.entry.toStringAsFixed(2)} | PnL: ${pos.pnl(price ?? pos.entry) >= 0 ? '+' : ''}\$${pos.pnl(price ?? pos.entry).toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: pos.pnl(price ?? pos.entry) >= 0
                              ? const Color(0xFF4ADE80)
                              : const Color(0xFFEF4444),
                        )),
                  ]),
                ),
              ],
              const SizedBox(height: 8),
              Row(children: [
                const Spacer(),
                if (pos == null)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: signal?.isValid == true
                          ? const Color(0xFF16A34A)
                          : const Color(0xFF1E2838),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.trending_up, size: 14, color: Colors.white),
                    label: const Text('فتح صفقة',
                        style: TextStyle(fontSize: 12, color: Colors.white)),
                    onPressed: signal?.isValid == true ? () => _manualOpen(sym) : null,
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
                    label: const Text('إغلاق',
                        style: TextStyle(fontSize: 12, color: Colors.white)),
                    onPressed: () => _manualClose(sym),
                  ),
              ]),
            ]),
          );
        },
      ),
    );
  }

  Widget _chip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2332),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('$label: $value',
          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildTrades() {
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
          _statBox('مفتوحة', '${_positions.length}', const Color(0xFF60A5FA)),
          _statBox('رابحة', '$wins', const Color(0xFF4ADE80)),
          _statBox('خاسرة', '$losses', const Color(0xFFEF4444)),
          _statBox('نجاح', '${wr.toStringAsFixed(0)}%', const Color(0xFFF59E0B)),
          _statBox('PnL', '${totalPnl >= 0 ? "+" : ""}\$${totalPnl.toStringAsFixed(1)}',
              totalPnl >= 0 ? const Color(0xFF4ADE80) : const Color(0xFFEF4444)),
        ]),
      ),
      Expanded(
        child: _trades.isEmpty
            ? const Center(child: Text('لا توجد صفقات بعد',
                style: TextStyle(color: Color(0xFF4B5563))))
            : ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: _trades.length,
                itemBuilder: (context, i) {
                  final t = _trades[i];
                  Color color = const Color(0xFF4ADE80);
                  String label = 'شراء';
                  if (t.action == 'SELL_SHORT') { color = const Color(0xFFEF4444); label = 'بيع'; }
                  if (t.action == 'STOP_LOSS') { color = const Color(0xFFDC2626); label = 'وقف خسارة'; }
                  if (t.action == 'TAKE_PROFIT') { color = const Color(0xFF16A34A); label = 'جني ربح'; }
                  if (t.action == 'MANUAL') { color = const Color(0xFF60A5FA); label = 'يدوي'; }

                  final isEntry = t.action == 'BUY' || t.action == 'SELL_SHORT';
                  final priceLabel = isEntry ? 'دخول' : 'خروج';

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
                        Text('$label ${t.symbol}',
                            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('${t.time.hour}:${t.time.minute.toString().padLeft(2, '0')} | $priceLabel: \$${t.price.toStringAsFixed(4)}',
                            style: const TextStyle(color: Color(0xFF8892A6), fontSize: 11)),
                      ]),
                      if (t.pnl != 0)
                        Text('${t.pnl >= 0 ? '+' : ''}\$${t.pnl.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: t.pnl >= 0 ? const Color(0xFF4ADE80) : const Color(0xFFEF4444),
                              fontWeight: FontWeight.bold,
                            )),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }

  Widget _statBox(String label, String value, Color color) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(value, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold)),
      Text(label, style: const TextStyle(color: Color(0xFF8892A6), fontSize: 10)),
    ]);
  }

  Widget _buildBacktest() {
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF131A26),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF60A5FA)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('اختبار الاستراتيجية على بيانات تاريخية',
                style: TextStyle(color: Color(0xFF60A5FA), fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            const Text('يختبر آخر 500 شمعة 4h + 1000 شمعة 1h لكل عملة',
                style: TextStyle(color: Color(0xFF8892A6), fontSize: 11)),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _backtesting ? null : _runBacktest,
                child: _backtesting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('▶ تشغيل Backtest', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
            if (_backtestMsg.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_backtestMsg, style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11)),
              ),
          ]),
        ),
        const SizedBox(height: 10),
        if (_backtestResults.isEmpty && !_backtesting)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(30),
              child: Text('اضغط "تشغيل Backtest" لاختبار الاستراتيجية',
                  style: TextStyle(color: Color(0xFF4B5563)), textAlign: TextAlign.center),
            ),
          ),
        for (final r in _backtestResults) _backtestCard(r),
      ],
    );
  }

  Widget _backtestCard(BacktestResult r) {
    final profitColor = r.isProfitable ? const Color(0xFF4ADE80) : const Color(0xFFEF4444);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF131A26),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: profitColor.withOpacity(0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(r.symbol, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: profitColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('${r.profitPct >= 0 ? '+' : ''}${r.profitPct.toStringAsFixed(2)}%',
                style: TextStyle(color: profitColor, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ]),
        const SizedBox(height: 8),
        _btRow('عدد الصفقات', '${r.totalTrades}'),
        _btRow('رابحة / خاسرة', '${r.wins} / ${r.losses}'),
        _btRow('نسبة النجاح', '${r.winRate.toStringAsFixed(1)}%'),
        _btRow('الرصيد النهائي', '\$${r.finalBalance.toStringAsFixed(2)}'),
        _btRow('أقصى تراجع', '${r.maxDrawdown.toStringAsFixed(1)}%'),
        _btRow('Profit Factor', r.profitFactor.toStringAsFixed(2)),
      ]),
    );
  }

  Widget _btRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        Text(value, style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 12, fontFamily: 'monospace')),
      ]),
    );
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
            _running ? 'إيقاف البوت' : 'بدء البوت',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
