import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CryptoBotApp());
}

// ============ CONFIG ============
const List<String> SYMBOLS = [
  'BTCUSDT', 'ETHUSDT', 'BNBUSDT', 'SOLUSDT', 'XRPUSDT', 'DOGEUSDT'
];
const String API_URL = 'https://fapi.binance.com/fapi/v1/ticker/price';
const int LOOP_SECONDS = 10;

// ============ MODELS ============
class Position {
  final String symbol;
  final double entry;
  final double size;
  final double margin;
  Position({required this.symbol, required this.entry, required this.size, required this.margin});
  double pnl(double current) => (current - entry) * size;
}

class TradeRecord {
  final String symbol;
  final String action;
  final double price;
  final double pnl;
  final DateTime time;
  TradeRecord({required this.symbol, required this.action, required this.price, required this.pnl, required this.time});
}

// ============ APP ============
class CryptoBotApp extends StatelessWidget {
  const CryptoBotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Crypto Bot',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0E17),
        primaryColor: const Color(0xFF4ADE80),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF131A26),
          elevation: 0,
        ),
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

// ============ HOME ============
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;

  double _balance = 1000.0;
  final double _initialCapital = 1000.0;
  double _marginPerTrade = 50.0;
  int _leverage = 20;
  int _rsiBuy = 40;
  int _rsiSell = 60;
  int _smaShort = 5;
  int _smaLong = 10;
  bool _running = false;

  final Map<String, Position> _positions = {};
  final Map<String, List<double>> _priceHistory = {};
  final List<TradeRecord> _trades = [];
  final Map<String, double> _livePrices = {};

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    for (final s in SYMBOLS) _priceHistory[s] = [];
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  // ============ BOT LOGIC ============
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
    try {
      final res = await http.get(Uri.parse(API_URL));
      if (res.statusCode != 200) return;
      final List data = json.decode(res.body);
      final Map<String, double> prices = {};
      for (final item in data) {
        final sym = item['symbol'] as String;
        if (SYMBOLS.contains(sym)) {
          prices[sym] = double.parse(item['price'] as String);
        }
      }
      if (!mounted) return;
      setState(() {
        _livePrices.addAll(prices);
        for (final sym in SYMBOLS) {
          final p = prices[sym];
          if (p == null) continue;
          _priceHistory[sym]!.add(p);
          if (_priceHistory[sym]!.length > 100) _priceHistory[sym]!.removeAt(0);
          _process(sym, p);
        }
      });
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  void _process(String symbol, double price) {
    final hist = _priceHistory[symbol]!;
    final ss = _sma(hist, _smaShort);
    final sl = _sma(hist, _smaLong);
    final rsi = _rsi(hist, 14);

    final pos = _positions[symbol];

    // Liquidation check
    if (pos != null) {
      final liqPrice = pos.entry * (1 - 1 / _leverage);
      if (price <= liqPrice) {
        _trades.insert(0, TradeRecord(
          symbol: symbol, action: 'LIQUIDATED', price: price,
          pnl: -pos.margin, time: DateTime.now(),
        ));
        _positions.remove(symbol);
        return;
      }
    }

    if (ss == null || sl == null || rsi == null) return;

    // BUY
    if (ss > sl && rsi < _rsiBuy && !_positions.containsKey(symbol)) {
      if (_balance >= _marginPerTrade) {
        final size = (_marginPerTrade * _leverage) / price;
        _positions[symbol] = Position(
          symbol: symbol, entry: price, size: size, margin: _marginPerTrade,
        );
        _balance -= _marginPerTrade;
        _trades.insert(0, TradeRecord(
          symbol: symbol, action: 'BUY', price: price,
          pnl: 0, time: DateTime.now(),
        ));
      }
    }
    // SELL
    else if (ss < sl && rsi > _rsiSell && _positions.containsKey(symbol)) {
      final p = _positions[symbol]!;
      final pnl = (price - p.entry) * p.size;
      _balance += p.margin + pnl;
      _trades.insert(0, TradeRecord(
        symbol: symbol, action: 'SELL', price: price,
        pnl: pnl, time: DateTime.now(),
      ));
      _positions.remove(symbol);
    }

    if (_trades.length > 100) _trades.removeLast();
  }

  double? _sma(List<double> arr, int period) {
    if (arr.length < period) return null;
    double sum = 0;
    for (int i = arr.length - period; i < arr.length; i++) sum += arr[i];
    return sum / period;
  }

  double? _rsi(List<double> arr, int period) {
    if (arr.length < period + 1) return null;
    double gains = 0, losses = 0;
    for (int i = arr.length - period; i < arr.length; i++) {
      final d = arr[i] - arr[i - 1];
      if (d > 0) { gains += d; } else { losses -= d; }
    }
    final ag = gains / period;
    final al = losses / period;
    if (al == 0) return 100;
    return 100 - (100 / (1 + ag / al));
  }

  // ============ UI ============
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crypto Bot Pro',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _running ? const Color(0xFF4ADE80) : const Color(0xFFEF4444),
                  ),
                ),
                const SizedBox(width: 6),
                Text(_running ? 'يعمل' : 'متوقف',
                    style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ],
            ),
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
            Tab(text: 'الإعدادات'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildBalanceBar(),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _buildDashboard(),
                _buildTrades(),
                _buildSettings(),
              ],
            ),
          ),
          _buildStartButton(),
        ],
      ),
    );
  }

  Widget _buildBalanceBar() {
    final pnl = _balance - _initialCapital;
    final pct = (_initialCapital > 0) ? (pnl / _initialCapital * 100) : 0.0;
    final color = pnl >= 0 ? const Color(0xFF4ADE80) : const Color(0xFFEF4444);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E3A2F), Color(0xFF16241C)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        border: Border(bottom: BorderSide(color: Color(0xFF2A4A3A))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('الرصيد',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 4),
              Text('\$${_balance.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF4ADE80))),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('الربح / الخسارة',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 4),
              Text('${pnl >= 0 ? '+' : ''}\$${pnl.toStringAsFixed(2)}',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold, color: color)),
              Text('${pnl >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
                  style: TextStyle(fontSize: 12, color: color)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: SYMBOLS.length,
      itemBuilder: (context, i) {
        final sym = SYMBOLS[i];
        final price = _livePrices[sym];
        final hist = _priceHistory[sym]!;
        final rsi = _rsi(hist, 14);
        final ss = _sma(hist, _smaShort);
        final sl = _sma(hist, _smaLong);
        final pos = _positions[sym];

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF131A26),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1E2838)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(sym,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
                  Text(price != null ? '\$${price.toStringAsFixed(2)}' : '...',
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 15,
                          color: Color(0xFF60A5FA))),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  _chip('RSI', rsi != null ? rsi.toStringAsFixed(1) : '—'),
                  _chip('SMA$_smaShort', ss != null ? ss.toStringAsFixed(0) : '—'),
                  _chip('SMA$_smaLong', sl != null ? sl.toStringAsFixed(0) : '—'),
                ],
              ),
              if (pos != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1A2332),
                    border: Border(right: BorderSide(color: Color(0xFF4ADE80), width: 3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('مركز مفتوح',
                          style: TextStyle(color: Color(0xFF4ADE80), fontSize: 12)),
                      Text(
                        'دخول: \$${pos.entry.toStringAsFixed(2)} | PnL: ${pos.pnl(price ?? pos.entry) >= 0 ? "+" : ""}\$${pos.pnl(price ?? pos.entry).toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: pos.pnl(price ?? pos.entry) >= 0
                              ? const Color(0xFF4ADE80)
                              : const Color(0xFFEF4444),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _chip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2332),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('$label: $value',
          style: const TextStyle(fontSize: 11, color: Color(0xFF8892A6))),
    );
  }

  Widget _buildTrades() {
    if (_trades.isEmpty) {
      return const Center(
          child: Text('لا توجد صفقات بعد', style: TextStyle(color: Color(0xFF4B5563))));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: _trades.length,
      itemBuilder: (context, i) {
        final t = _trades[i];
        Color color = const Color(0xFF4ADE80);
        String label = '🟢 شراء';
        if (t.action == 'SELL') { color = const Color(0xFFEF4444); label = '🔴 بيع'; }
        if (t.action == 'LIQUIDATED') { color = const Color(0xFFF59E0B); label = '💥 تصفية'; }

        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF1A2332),
            borderRadius: BorderRadius.circular(8),
            border: Border(right: BorderSide(color: color, width: 3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$label ${t.symbol}',
                      style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
                  Text('${t.time.hour}:${t.time.minute.toString().padLeft(2, '0')} • \$${t.price.toStringAsFixed(2)}',
                      style: const TextStyle(color: Color(0xFF8892A6), fontSize: 11)),
                ],
              ),
              if (t.pnl != 0)
                Text('${t.pnl >= 0 ? '+' : ''}\$${t.pnl.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: t.pnl >= 0 ? const Color(0xFF4ADE80) : const Color(0xFFEF4444),
                      fontWeight: FontWeight.bold,
                    )),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSettings() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _settingRow('رأس المال الأولي', _initialCapital.toStringAsFixed(0), null),
        _settingRow('الهامش لكل صفقة', _marginPerTrade.toStringAsFixed(0), (v) {
          setState(() => _marginPerTrade = double.tryParse(v) ?? _marginPerTrade);
        }),
        _settingRow('الرافعة المالية', _leverage.toString(), (v) {
          setState(() => _leverage = int.tryParse(v) ?? _leverage);
        }),
        _settingRow('RSI الشراء (أقل من)', _rsiBuy.toString(), (v) {
          setState(() => _rsiBuy = int.tryParse(v) ?? _rsiBuy);
        }),
        _settingRow('RSI البيع (أكبر من)', _rsiSell.toString(), (v) {
          setState(() => _rsiSell = int.tryParse(v) ?? _rsiSell);
        }),
        _settingRow('SMA القصير', _smaShort.toString(), (v) {
          setState(() => _smaShort = int.tryParse(v) ?? _smaShort);
        }),
        _settingRow('SMA الطويل', _smaLong.toString(), (v) {
          setState(() => _smaLong = int.tryParse(v) ?? _smaLong);
        }),
        const SizedBox(height: 20),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFEF4444),
            padding: const EdgeInsets.all(14),
          ),
          onPressed: () {
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: const Color(0xFF131A26),
                title: const Text('إعادة تعيين', style: TextStyle(color: Colors.white)),
                content: const Text('سيتم مسح كل الصفقات والرصيد. متأكد؟',
                    style: TextStyle(color: Colors.white70)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('إلغاء')),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() {
                        _balance = _initialCapital;
                        _positions.clear();
                        _trades.clear();
                        for (final s in SYMBOLS) _priceHistory[s]!.clear();
                      });
                    },
                    child: const Text('نعم', style: TextStyle(color: Color(0xFFEF4444))),
                  ),
                ],
              ),
            );
          },
          child: const Text('إعادة تعيين كل شيء',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _settingRow(String label, String value, [ValueChanged<String>? onEdit]) {
    return InkWell(
      onTap: onEdit == null ? null : () => _editValue(label, value, onEdit),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF1A2332))),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
            Row(
              children: [
                Text(value,
                    style: const TextStyle(
                        color: Color(0xFF4ADE80), fontWeight: FontWeight.bold)),
                if (onEdit != null) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.edit, size: 14, color: Color(0xFF60A5FA)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editValue(String label, String current, ValueChanged<String> onSave) async {
    final c = TextEditingController(text: current);
    final v = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF131A26),
        title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF0A0E17),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(context, c.text),
            child: const Text('حفظ', style: TextStyle(color: Color(0xFF4ADE80))),
          ),
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
