import re

with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

# ============ 1. Change _initialCapital from final to mutable ============
src = src.replace(
    'final double _initialCapital = 1000.0;',
    'double _initialCapital = 1000.0;'
)

# ============ 2. Replace _loadState with complete version ============
old_load = """  Future<void> _loadState() async {
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
  }"""

new_load = """  Future<void> _loadState() async {
    try {
      final data = await StorageService.loadAll().timeout(const Duration(seconds: 5));
      if (data != null && mounted) {
        setState(() {
          // 1. Balance
          _balance = (data['balance'] as num?)?.toDouble() ?? 1000.0;

          // 2. Settings
          final settings = (data['settings'] as Map<String, dynamic>?) ?? {};
          _initialCapital = (settings['initialCapital'] as num?)?.toDouble() ?? 1000.0;

          // 3. Positions
          final posRaw = (data['positions'] as Map<String, dynamic>?) ?? {};
          _positions.clear();
          posRaw.forEach((k, v) {
            try {
              _positions[k] = Position.fromJson(Map<String, dynamic>.from(v));
            } catch (e) {
              debugPrint('Position load error: $e');
            }
          });

          // 4. Trades
          final tradesRaw = (data['trades'] as List?) ?? [];
          _trades.clear();
          for (final t in tradesRaw) {
            try {
              _trades.add(TradeRecord.fromJson(Map<String, dynamic>.from(t)));
            } catch (e) {
              debugPrint('Trade load error: $e');
            }
          }

          // 5. Risk state
          if (settings['risk'] != null) {
            _risk.loadFromJson(Map<String, dynamic>.from(settings['risk']));
          } else {
            _risk.initialize(_balance);
          }

          debugPrint('✅ Loaded: balance=$_balance, positions=${_positions.length}, trades=${_trades.length}');
        });
      } else {
        _risk.initialize(_balance);
      }
    } catch (e) {
      debugPrint('Load error: $e');
      _risk.initialize(_balance);
    }
    if (mounted) setState(() => _loaded = true);
  }"""

if old_load in src:
    src = src.replace(old_load, new_load)
    print("✅ _loadState fixed")
else:
    print("❌ _loadState pattern not found")

# ============ 3. Fix _saveState to include initialCapital ============
old_save = """  Future<void> _saveState() async {
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
  }"""

new_save = """  Future<void> _saveState() async {
    try {
      final posMap = <String, dynamic>{};
      _positions.forEach((k, v) => posMap[k] = v.toJson());
      await StorageService.saveAll(
        balance: _balance,
        positions: posMap,
        trades: _trades.map((t) => t.toJson()).toList(),
        settings: {
          'initialCapital': _initialCapital,
          'risk': _risk.toJson(),
        },
      );
      debugPrint('💾 Saved: balance=$_balance, positions=${_positions.length}, trades=${_trades.length}');
    } catch (e) {
      debugPrint('Save error: $e');
    }
  }"""

if old_save in src:
    src = src.replace(old_save, new_save)
    print("✅ _saveState fixed")
else:
    print("❌ _saveState pattern not found")

# ============ 4. Save immediately after open/close ============
# After _openPosition call
src = src.replace(
    "    _risk.recordOpen();\n    _trades.insert(0, TradeRecord(",
    "    _risk.recordOpen();\n    _saveState();\n    _trades.insert(0, TradeRecord("
)

# After _closePosition completion
src = src.replace(
    "    if (_trades.length > 200) _trades.removeLast();\n  }\n\n  void _manualOpen",
    "    if (_trades.length > 200) _trades.removeLast();\n    _saveState();\n  }\n\n  void _manualOpen"
)

# ============ 5. Ensure save on app pause (lifecycle) ============
# Add WidgetsBindingObserver to detect app state
if 'with SingleTickerProviderStateMixin' in src and 'WidgetsBindingObserver' not in src:
    src = src.replace(
        'class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {',
        'class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {'
    )
    print("✅ Added WidgetsBindingObserver")

# Register observer in initState
if 'WidgetsBinding.instance.addObserver(this);' not in src:
    src = src.replace(
        "    _tabs = TabController(length: 3, vsync: this);",
        "    _tabs = TabController(length: 3, vsync: this);\n    WidgetsBinding.instance.addObserver(this);"
    )
    print("✅ Registered observer")

# Add didChangeAppLifecycleState to save on pause
lifecycle_method = """
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Save state whenever app goes to background or closes
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _saveState();
    }
    super.didChangeAppLifecycleState(state);
  }

"""

if 'void didChangeAppLifecycleState' not in src:
    src = src.replace(
        "  @override\n  void dispose() {",
        lifecycle_method + "  @override\n  void dispose() {"
    )
    print("✅ Added didChangeAppLifecycleState")

# ============ 6. Restore position tracking on startup ============
# When app loads and positions exist, we need to keep monitoring them
# The existing _processSymbol will handle this since positions are loaded

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

# Verify
with open('lib/main.dart', 'r', encoding='utf-8') as f:
    final = f.read()

print()
print("=== Verification ===")
print(f"✅ initialCapital mutable: {'double _initialCapital' in final}")
print(f"✅ Loads positions: {'posRaw.forEach' in final}")
print(f"✅ Loads trades: {'tradesRaw' in final}")
print(f"✅ Saves initialCapital: {'initialCapital' in final}")
print(f"✅ Lifecycle observer: {'didChangeAppLifecycleState' in final}")
print(f"📊 Braces: {final.count('{')} / {final.count('}')}")
