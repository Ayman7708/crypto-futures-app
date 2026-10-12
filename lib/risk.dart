/// RiskManager - V9 rules
/// Position sizing: 1% risk per trade
/// Daily stop: -5% max
/// Max positions: 3
class RiskManager {
  static const double riskPerTrade = 0.01;
  static const double maxDailyLoss = 0.05;
  static const int maxPositions = 3;
  static const int maxDailyTrades = 10;

  double _startOfDayBalance = 0;
  DateTime _currentDay = DateTime.now();
  int _tradesToday = 0;
  double _dailyPnL = 0;

  void initialize(double balance) {
    _startOfDayBalance = balance;
    _currentDay = DateTime.now();
    _tradesToday = 0;
    _dailyPnL = 0;
  }

  void checkNewDay(double currentBalance) {
    final now = DateTime.now();
    if (now.day != _currentDay.day ||
        now.month != _currentDay.month ||
        now.year != _currentDay.year) {
      _currentDay = now;
      _startOfDayBalance = currentBalance;
      _tradesToday = 0;
      _dailyPnL = 0;
    }
  }

  bool canOpen({
    required int currentPositions,
    required double balance,
  }) {
    checkNewDay(balance);
    if (currentPositions >= maxPositions) return false;
    if (_startOfDayBalance > 0) {
      final lossPct = -_dailyPnL / _startOfDayBalance;
      if (lossPct >= maxDailyLoss) return false;
    }
    if (_tradesToday >= maxDailyTrades) return false;
    return true;
  }

  double calculateMargin({
    required double balance,
    required double entry,
    required double stopLoss,
    required int leverage,
  }) {
    if (entry == stopLoss || entry <= 0) return 0;
    final riskUsdt = balance * riskPerTrade;
    final slDistancePct = (entry - stopLoss).abs() / entry;
    final positionValue = riskUsdt / slDistancePct;
    final margin = positionValue / leverage;
    final maxMargin = balance * 0.10;
    return margin > maxMargin ? maxMargin : margin;
  }

  void recordOpen() {
    _tradesToday++;
  }

  void recordClose(double pnl) {
    _dailyPnL += pnl;
  }

  double get dailyPnL => _dailyPnL;
  int get tradesToday => _tradesToday;

  bool get isDailyLimitHit {
    if (_startOfDayBalance == 0) return false;
    return (-_dailyPnL / _startOfDayBalance) >= maxDailyLoss;
  }

  String get statusMessage {
    if (isDailyLimitHit) {
      return 'حد الخسارة اليومي - انتهى التداول لليوم';
    }
    if (_tradesToday >= maxDailyTrades) {
      return 'تم الوصول للحد الأقصى للصفقات اليومية';
    }
    return 'التداول نشط - $_tradesToday/$maxDailyTrades صفقة';
  }

  Map<String, dynamic> toJson() => {
        'startOfDayBalance': _startOfDayBalance,
        'currentDay': _currentDay.toIso8601String(),
        'tradesToday': _tradesToday,
        'dailyPnL': _dailyPnL,
      };

  void loadFromJson(Map<String, dynamic> j) {
    try {
      _startOfDayBalance = (j['startOfDayBalance'] as num?)?.toDouble() ?? 0;
      _currentDay = DateTime.tryParse(j['currentDay'] ?? '') ?? DateTime.now();
      _tradesToday = (j['tradesToday'] as num?)?.toInt() ?? 0;
      _dailyPnL = (j['dailyPnL'] as num?)?.toDouble() ?? 0;
      final now = DateTime.now();
      if (now.day != _currentDay.day ||
          now.month != _currentDay.month ||
          now.year != _currentDay.year) {
        _currentDay = now;
        _tradesToday = 0;
        _dailyPnL = 0;
      }
    } catch (_) {}
  }
}
