import 'dart:math';
import 'engine.dart';
import 'advanced.dart';
import 'strategies.dart';
import 'indicators_v2.dart';
import 'indicators_v3.dart';
import 'auto_filter.dart';

class SignalVote {
  final String name;
  final String category;
  final int vote;        // -100 to +100 (negative = bearish, positive = bullish)
  final double weight;   // 0.2 to 3.0
  SignalVote(this.name, this.category, this.vote, this.weight);
}

class MasterSignalResult {
  final int bullishScore;      // 0-100
  final int bearishScore;      // 0-100
  final String recommendation; // STRONG_LONG, LONG, NONE, SHORT, STRONG_SHORT
  final List<SignalVote> votes;
  final List<String> topBullish;
  final List<String> topBearish;
  MasterSignalResult({
    required this.bullishScore, required this.bearishScore,
    required this.recommendation, required this.votes,
    required this.topBullish, required this.topBearish,
  });
}

class MasterSignal {
  final Map<String, double> weights = {};
  final Map<String, int> wins = {};
  final Map<String, int> losses = {};
  final AutoFilter filter = AutoFilter();

  MasterSignal() {
    for (final name in _allNames) {
      weights[name] = 1.0;
      wins[name] = 0;
      losses[name] = 0;
    }
  }

  static const _allNames = [
    // Trends
    'SMA Cross', 'EMA Cross', 'MACD', 'SuperTrend', 'Ichimoku', 'PSAR', 'Aroon', 'Vortex', 'KST',
    // Momentum
    'RSI', 'Stoch', 'Williams %R', 'CCI', 'MFI', 'ROC', 'TRIX', 'AO', 'UO', 'TSI', 'DPO', 'CMO', 'Fisher', 'Connors RSI',
    // Volume
    'OBV', 'CMF', 'Force Index', 'EOM', 'Volume Surge',
    // Volatility
    'Bollinger', 'Keltner', 'Donchian', 'Squeeze', 'Mass Index', 'Ulcer',
    // Reversal
    'Divergence', 'KDJ', 'RVI', 'Pivot', 'Elder Ray', 'Schaff', 'Coppock',
    // V3 - 15 more
    'Zigzag', 'Heikin-Ashi', 'Alligator', 'Fractals', 'Gator',
    'Accelerator', 'Bulls Power', 'Bears Power', 'Chaikin Osc',
    'BB %B', 'Choppiness', 'Klinger', 'Twiggs MF', 'Elder Impulse', 'SMI',
    'RVI Vigor', 'WaveTrend',
  ];

  MasterSignalResult analyze({
    required List<double> closes,
    required List<double> highs,
    required List<double> lows,
    required List<double> volumes,
    required int smaShort,
    required int smaLong,
  }) {
    if (closes.length < 55) {
      return MasterSignalResult(
        bullishScore: 0, bearishScore: 0, recommendation: 'NONE',
        votes: [], topBullish: [], topBearish: [],
      );
    }

    final votes = <SignalVote>[];

    // ============ TREND INDICATORS ============
    final sma5 = _sma(closes, smaShort);
    final sma20 = _sma(closes, smaLong);
    if (sma5 != null && sma20 != null) {
      votes.add(SignalVote('SMA Cross', 'Trend', sma5 > sma20 ? 60 : -60, weights['SMA Cross']!));
    }
    final ema12 = IndicatorsV2.emaCalc(closes, 12);
    final ema26 = IndicatorsV2.emaCalc(closes, 26);
    if (ema12 != null && ema26 != null) {
      votes.add(SignalVote('EMA Cross', 'Trend', ema12 > ema26 ? 60 : -60, weights['EMA Cross']!));
    }
    final (macd, macdSig, macdHist) = Indicators.macd(closes);
    if (macd != null && macdSig != null) {
      final v = macdHist != null ? (macdHist > 0 ? 70 : -70) : (macd > macdSig ? 40 : -40);
      votes.add(SignalVote('MACD', 'Trend', v, weights['MACD']!));
    }
    final (stVal, stDir) = AdvIndicators.superTrend(highs, lows, closes, 10, 3.0);
    if (stVal != null) {
      votes.add(SignalVote('SuperTrend', 'Trend', stDir == 'BUY' ? 80 : -80, weights['SuperTrend']!));
    }
    final (ichA, ichB, _) = AdvIndicators.ichimoku(highs, lows);
    if (ichA != null && ichB != null) {
      final above = closes.last > ichA && closes.last > ichB;
      final below = closes.last < ichA && closes.last < ichB;
      votes.add(SignalVote('Ichimoku', 'Trend', above ? 70 : (below ? -70 : 0), weights['Ichimoku']!));
    }
    final (_, psarDir) = ExtraIndicators.parabolicSar(highs, lows);
    votes.add(SignalVote('PSAR', 'Trend', psarDir == 'BUY' ? 60 : -60, weights['PSAR']!));
    final aroon = ExtraIndicators.aroon(highs, lows, 14);
    if (aroon != null) {
      votes.add(SignalVote('Aroon', 'Trend', aroon.clamp(-100, 100).toInt(), weights['Aroon']!));
    }
    final vortex = ExtraIndicators.vortex(highs, lows, closes, 14);
    if (vortex != null) {
      votes.add(SignalVote('Vortex', 'Trend', (vortex * 200).clamp(-100, 100).toInt(), weights['Vortex']!));
    }
    final kst = IndicatorsV2.kst(closes);
    if (kst != null) {
      votes.add(SignalVote('KST', 'Trend', kst > 0 ? 60 : -60, weights['KST']!));
    }

    // ============ MOMENTUM INDICATORS ============
    final rsi = Indicators.rsi(closes, 14);
    if (rsi != null) {
      final v = rsi < 30 ? 70 : (rsi > 70 ? -70 : (rsi < 50 ? 30 : -30));
      votes.add(SignalVote('RSI', 'Momentum', v, weights['RSI']!));
    }
    final stoch = Indicators.stochastic(highs, lows, closes, 14);
    if (stoch != null) {
      final v = stoch < 20 ? 70 : (stoch > 80 ? -70 : (stoch < 50 ? 20 : -20));
      votes.add(SignalVote('Stoch', 'Momentum', v, weights['Stoch']!));
    }
    final wr = AdvIndicators.williamsR(highs, lows, closes, 14);
    if (wr != null) {
      final v = wr < -80 ? 70 : (wr > -20 ? -70 : (wr < -50 ? 20 : -20));
      votes.add(SignalVote('Williams %R', 'Momentum', v, weights['Williams %R']!));
    }
    final cci = AdvIndicators.cci(highs, lows, closes, 20);
    if (cci != null) {
      final v = cci < -100 ? 70 : (cci > 100 ? -70 : cci.clamp(-50, 50).toInt());
      votes.add(SignalVote('CCI', 'Momentum', v, weights['CCI']!));
    }
    final mfi = AdvIndicators.mfi(highs, lows, closes, volumes, 14);
    if (mfi != null) {
      final v = mfi < 20 ? 70 : (mfi > 80 ? -70 : (mfi < 50 ? 20 : -20));
      votes.add(SignalVote('MFI', 'Momentum', v, weights['MFI']!));
    }
    final roc = AdvIndicators.roc(closes, 10);
    if (roc != null) {
      votes.add(SignalVote('ROC', 'Momentum', (roc * 10).clamp(-100, 100).toInt(), weights['ROC']!));
    }
    final trix = ExtraIndicators.trix(closes);
    if (trix != null) {
      votes.add(SignalVote('TRIX', 'Momentum', (trix * 30).clamp(-100, 100).toInt(), weights['TRIX']!));
    }
    final ao = ExtraIndicators.awesome(closes);
    if (ao != null) {
      votes.add(SignalVote('AO', 'Momentum', ao > 0 ? 60 : -60, weights['AO']!));
    }
    final uo = ExtraIndicators.ultimate(highs, lows, closes);
    if (uo != null) {
      final v = uo < 30 ? 70 : (uo > 70 ? -70 : (uo - 50).toInt() * 2);
      votes.add(SignalVote('UO', 'Momentum', v, weights['UO']!));
    }
    final tsi = IndicatorsV2.tsi(closes);
    if (tsi != null) {
      final v = tsi > 20 ? 70 : (tsi < -20 ? -70 : tsi.clamp(-50, 50).toInt());
      votes.add(SignalVote('TSI', 'Momentum', v, weights['TSI']!));
    }
    final dpo = IndicatorsV2.dpo(closes);
    if (dpo != null) {
      votes.add(SignalVote('DPO', 'Momentum', dpo > 0 ? 50 : -50, weights['DPO']!));
    }
    final cmo = IndicatorsV2.cmo(closes);
    if (cmo != null) {
      votes.add(SignalVote('CMO', 'Momentum', cmo.clamp(-100, 100).toInt(), weights['CMO']!));
    }
    final fisher = IndicatorsV2.fisher(highs, lows, closes, 10);
    if (fisher != null) {
      votes.add(SignalVote('Fisher', 'Momentum', (fisher * 50).clamp(-100, 100).toInt(), weights['Fisher']!));
    }
    final crsi = IndicatorsV2.connorsRsi(closes);
    if (crsi != null) {
      final v = crsi < 30 ? 60 : (crsi > 70 ? -60 : 0);
      votes.add(SignalVote('Connors RSI', 'Momentum', v, weights['Connors RSI']!));
    }

    // ============ VOLUME INDICATORS ============
    final obv = AdvIndicators.obvTrend(closes, volumes, 20);
    if (obv != null) {
      votes.add(SignalVote('OBV', 'Volume', obv > 0 ? 60 : -60, weights['OBV']!));
    }
    final cmf = ExtraIndicators.cmf(highs, lows, closes, volumes, 20);
    if (cmf != null) {
      votes.add(SignalVote('CMF', 'Volume', (cmf * 300).clamp(-100, 100).toInt(), weights['CMF']!));
    }
    final fi = ExtraIndicators.forceIndex(closes, volumes);
    if (fi != null) {
      votes.add(SignalVote('Force Index', 'Volume', fi > 0 ? 60 : -60, weights['Force Index']!));
    }
    final eom = IndicatorsV2.eom(highs, lows, volumes);
    if (eom != null) {
      votes.add(SignalVote('EOM', 'Volume', (eom * 1000).clamp(-100, 100).toInt(), weights['EOM']!));
    }
    final vs = AdvIndicators.volumeSurge(volumes, 20);
    if (vs > 1.5) {
      final dir = closes.last > closes[closes.length - 2] ? 80 : -80;
      votes.add(SignalVote('Volume Surge', 'Volume', dir, weights['Volume Surge']!));
    }

    // ============ VOLATILITY ============
    final (bl, bm, bu) = Indicators.bollinger(closes, 20, 2);
    if (bl != null && bm != null && bu != null) {
      final v = closes.last <= bl ? 70 : (closes.last >= bu ? -70 : 0);
      votes.add(SignalVote('Bollinger', 'Volatility', v, weights['Bollinger']!));
    }
    final (kl, km, ku) = AdvIndicators.keltner(highs, lows, closes, 20, 2);
    if (kl != null) {
      final v = closes.last <= kl ? 60 : (closes.last >= ku! ? -60 : 0);
      votes.add(SignalVote('Keltner', 'Volatility', v, weights['Keltner']!));
    }
    final (dl, dm, du) = ExtraIndicators.donchian(highs, lows, 20);
    if (dl != null) {
      final v = closes.last <= dl ? 60 : (closes.last >= du! ? 60 : 0);
      votes.add(SignalVote('Donchian', 'Volatility', v, weights['Donchian']!));
    }
    final sq = AdvIndicators.bollingerSqueeze(closes);
    if (sq != null && sq < 0.03) {
      votes.add(SignalVote('Squeeze', 'Volatility', 50, weights['Squeeze']!));
    }
    final mi = IndicatorsV2.massIndex(highs, lows, 25);
    if (mi != null) {
      votes.add(SignalVote('Mass Index', 'Volatility', mi > 27 ? 50 : 0, weights['Mass Index']!));
    }
    final uic = IndicatorsV2.ulcer(closes, 14);
    if (uic != null) {
      votes.add(SignalVote('Ulcer', 'Volatility', uic < 3 ? 50 : (uic > 8 ? -50 : 0), weights['Ulcer']!));
    }

    // ============ REVERSAL ============
    final div = AdvIndicators.rsiDivergence(closes, 14);
    if (div != null) {
      votes.add(SignalVote('Divergence', 'Reversal', (div * 60).toInt(), weights['Divergence']!));
    }
    final (k, d, j) = IndicatorsV2.kdj(highs, lows, closes, 9);
    if (k != null && d != null && j != null) {
      final v = j < 20 ? 70 : (j > 80 ? -70 : 0);
      votes.add(SignalVote('KDJ', 'Reversal', v, weights['KDJ']!));
    }
    final rvi = IndicatorsV2.rvi(closes, 10);
    if (rvi != null) {
      final v = rvi < 30 ? 60 : (rvi > 70 ? -60 : 0);
      votes.add(SignalVote('RVI', 'Reversal', v, weights['RVI']!));
    }
    final (pl, pp, ph) = ExtraIndicators.pivotPoints(highs, lows, closes);
    if (pl != null && ph != null) {
      final v = closes.last <= pl ? 60 : (closes.last >= ph ? -60 : 0);
      votes.add(SignalVote('Pivot', 'Reversal', v, weights['Pivot']!));
    }
    final (bull, bear) = IndicatorsV2.elderRay(highs, lows, closes, 13);
    if (bull != null && bear != null) {
      votes.add(SignalVote('Elder Ray', 'Reversal', bull > 0 ? 60 : -60, weights['Elder Ray']!));
    }
    final schaff = IndicatorsV2.schaffTrend(closes, 23, 50, 10);
    if (schaff != null) {
      votes.add(SignalVote('Schaff', 'Reversal', schaff > 0 ? 60 : -60, weights['Schaff']!));
    }
    final coppock = IndicatorsV2.coppock(closes);
    if (coppock != null) {
      votes.add(SignalVote('Coppock', 'Reversal', coppock > 0 ? 60 : -60, weights['Coppock']!));
    }

    // ============ V3 INDICATORS ============
    final zz = IndicatorsV3.zigzag(closes, 5);
    if (zz != null && zz > 2) {
      votes.add(SignalVote('Zigzag', 'Reversal', 50, weights['Zigzag']!));
    }
    final haDir = IndicatorsV3.heikinAshi(closes, highs, lows, closes);
    votes.add(SignalVote('Heikin-Ashi', 'Trend', haDir == 'BULL' ? 60 : -60, weights['Heikin-Ashi']!));
    final (agJ, agT, agL) = IndicatorsV3.alligator(closes);
    if (agJ != null && agT != null && agL != null) {
      final v = agL > agT && agT > agJ ? 70 : (agL < agT && agT < agJ ? -70 : 0);
      votes.add(SignalVote('Alligator', 'Trend', v, weights['Alligator']!));
    }
    final fr = IndicatorsV3.fractals(highs, lows, 2);
    if (fr > 0) {
      votes.add(SignalVote('Fractals', 'Reversal', closes.last > closes[closes.length - 2] ? 50 : -50, weights['Fractals']!));
    }
    final gat = IndicatorsV3.gator(closes);
    if (gat != null) {
      votes.add(SignalVote('Gator', 'Trend', gat < 1 ? 40 : 0, weights['Gator']!));
    }
    final acc = IndicatorsV3.accelerator(highs, lows, closes);
    if (acc != null) {
      votes.add(SignalVote('Accelerator', 'Momentum', acc > 0 ? 60 : -60, weights['Accelerator']!));
    }
    final bp = IndicatorsV3.bullsPower(highs, closes, 13);
    if (bp != null) {
      votes.add(SignalVote('Bulls Power', 'Momentum', bp > 0 ? 60 : -60, weights['Bulls Power']!));
    }
    final brp = IndicatorsV3.bearsPower(lows, closes, 13);
    if (brp != null) {
      votes.add(SignalVote('Bears Power', 'Momentum', brp > 0 ? -60 : 60, weights['Bears Power']!));
    }
    final chk = IndicatorsV3.chaikinOscillator(highs, lows, closes, volumes, 3, 10);
    if (chk != null) {
      votes.add(SignalVote('Chaikin Osc', 'Volume', chk > 0 ? 60 : -60, weights['Chaikin Osc']!));
    }
    final bbB = IndicatorsV3.bollingerPercentB(closes, 20, 2);
    if (bbB != null) {
      final v = bbB < 0 ? 70 : (bbB > 1 ? -70 : ((bbB - 0.5) * 80).toInt());
      votes.add(SignalVote('BB %B', 'Volatility', v, weights['BB %B']!));
    }
    final chop = IndicatorsV3.choppiness(highs, lows, closes, 14);
    if (chop != null) {
      final v = chop < 38 ? 60 : (chop > 62 ? -30 : 0);
      votes.add(SignalVote('Choppiness', 'Volatility', v, weights['Choppiness']!));
    }
    final klg = IndicatorsV3.klinger(highs, lows, closes, volumes, 34, 55);
    if (klg != null) {
      votes.add(SignalVote('Klinger', 'Volume', klg > 0 ? 60 : -60, weights['Klinger']!));
    }
    final twg = IndicatorsV3.twiggsMoneyFlow(highs, lows, closes, volumes, 21);
    if (twg != null) {
      final v = twg > 50 ? 60 : (twg < 50 ? -30 : 0);
      votes.add(SignalVote('Twiggs MF', 'Volume', v, weights['Twiggs MF']!));
    }
    final ei = IndicatorsV3.elderImpulse(closes, highs, lows, 13);
    votes.add(SignalVote('Elder Impulse', 'Trend', ei == 'GREEN' ? 70 : (ei == 'RED' ? -70 : 0), weights['Elder Impulse']!));
    final smi = IndicatorsV3.smi(highs, lows, closes, 14);
    if (smi != null) {
      final v = smi < -40 ? 70 : (smi > 40 ? -70 : smi.clamp(-60, 60).toInt());
      votes.add(SignalVote('SMI', 'Momentum', v, weights['SMI']!));
    }
    final rviV = IndicatorsV3.rviVigor(closes, highs, lows, closes, 10);
    if (rviV != null) {
      votes.add(SignalVote('RVI Vigor', 'Momentum', (rviV * 200).clamp(-100, 100).toInt(), weights['RVI Vigor']!));
    }
    final (wt, _) = IndicatorsV3.waveTrend(highs, lows, closes, 10);
    if (wt != null) {
      final v = wt < -60 ? 70 : (wt > 60 ? -70 : wt.clamp(-60, 60).toInt());
      votes.add(SignalVote('WaveTrend', 'Momentum', v, weights['WaveTrend']!));
    }

    // ============ FILTER OUT DELETED INDICATORS ============
    final activeVotes = votes.where((v) => filter.isActive(v.name)).toList();

    // Register votes in filter
    for (final v in activeVotes) {
      filter.registerVote(v.name);
    }

    // ============ COMPUTE WEIGHTED SCORES ============
    double bullSum = 0, bullTotalW = 0;
    double bearSum = 0, bearTotalW = 0;
    for (final v in activeVotes) {
      if (v.vote > 0) {
        bullSum += v.vote * v.weight;
        bullTotalW += v.weight;
      } else if (v.vote < 0) {
        bearSum += v.vote.abs() * v.weight;
        bearTotalW += v.weight;
      }
    }
    final bullScore = bullTotalW > 0 ? (bullSum / bullTotalW).clamp(0, 100).toInt() : 0;
    final bearScore = bearTotalW > 0 ? (bearSum / bearTotalW).clamp(0, 100).toInt() : 0;

    // Consensus bonus: if many agree, boost
    int bullCount = activeVotes.where((v) => v.vote > 30).length;
    int bearCount = activeVotes.where((v) => v.vote < -30).length;
    final bullFinal = (bullScore + bullCount * 2).clamp(0, 100);
    final bearFinal = (bearScore + bearCount * 2).clamp(0, 100);

    // Top contributors
    final sortedBull = votes.where((v) => v.vote > 0).toList()
      ..sort((a, b) => (b.vote * b.weight).compareTo(a.vote * a.weight));
    final sortedBear = votes.where((v) => v.vote < 0).toList()
      ..sort((a, b) => (a.vote * a.weight).compareTo(b.vote * b.weight));

    String rec;
    if (bullFinal >= 65) rec = 'STRONG_LONG';
    else if (bullFinal >= 50) rec = 'LONG';
    else if (bearFinal >= 65) rec = 'STRONG_SHORT';
    else if (bearFinal >= 50) rec = 'SHORT';
    else rec = 'NONE';

    return MasterSignalResult(
      bullishScore: bullFinal,
      bearishScore: bearFinal,
      recommendation: rec,
      votes: votes,
      topBullish: sortedBull.take(5).map((v) => '${v.name}(${v.vote})').toList(),
      topBearish: sortedBear.take(5).map((v) => '${v.name}(${v.vote})').toList(),
    );
  }

  // ============ Learn from trade ============
  void updateFromTrade(List<SignalVote> votes, bool wasWin) {
    final names = <String>[];
    for (final v in votes) {
      names.add(v.name);
      if (wasWin) {
        wins[v.name] = (wins[v.name] ?? 0) + 1;
        weights[v.name] = min(3.0, (weights[v.name] ?? 1.0) * 1.08);
      } else {
        losses[v.name] = (losses[v.name] ?? 0) + 1;
        weights[v.name] = max(0.2, (weights[v.name] ?? 1.0) * 0.93);
      }
    }
    // Feed auto-filter
    filter.updateFromTrade(names, wasWin);
  }

  double? _sma(List<double> arr, int p) {
    if (arr.length < p) return null;
    double s = 0;
    for (int i = arr.length - p; i < arr.length; i++) s += arr[i];
    return s / p;
  }

  Map<String, dynamic> toJson() => {
    'weights': weights, 'wins': wins, 'losses': losses,
    'filter': filter.toJson(),
  };

  void loadFromJson(Map<String, dynamic> j) {
    try {
      if (j['weights'] != null) {
        (j['weights'] as Map).forEach((k, v) {
          weights[k.toString()] = (v as num).toDouble();
        });
      }
      if (j['wins'] != null) {
        (j['wins'] as Map).forEach((k, v) {
          wins[k.toString()] = v as int;
        });
      }
      if (j['losses'] != null) {
        (j['losses'] as Map).forEach((k, v) {
          losses[k.toString()] = v as int;
        });
      }
      if (j['filter'] != null) {
        filter.loadFromJson(Map<String, dynamic>.from(j['filter']));
      }
    } catch (_) {}
  }
}
