# ========== FIX 1: Rename Candle in api_candles.dart ==========
with open('lib/api_candles.dart', 'r') as f:
    ac = f.read()
ac = ac.replace('class Candle {', 'class Kline {')
ac = ac.replace('Candle({', 'Kline({')
ac = ac.replace('List<Candle>', 'List<Kline>')
ac = ac.replace('Candle>', 'Kline>')
ac = ac.replace('Map<String, List<Candle>>', 'Map<String, List<Kline>>')
with open('lib/api_candles.dart', 'w') as f:
    f.write(ac)
print('✅ Fixed api_candles.dart')

# ========== FIX 2: Fix main.dart imports ==========
with open('lib/main.dart', 'r') as f:
    m = f.read()
if "import 'engine.dart' hide Candle;" not in m:
    m = m.replace(
        "import 'engine.dart';",
        "import 'engine.dart' hide Candle;"
    )
with open('lib/main.dart', 'w') as f:
    f.write(m)
print('✅ Fixed main.dart import')

# ========== FIX 3: Fix advanced.dart nullable issues ==========
with open('lib/advanced.dart', 'r') as f:
    ad = f.read()

old_squeeze = """    final (low, mid, up) = Indicators.bollinger(closes, period, mult);
    if (low == null || mid == 0) return null;
    final width = (up! - low) / mid;
    return width;"""
new_squeeze = """    final (low, mid, up) = Indicators.bollinger(closes, period, mult);
    if (low == null || mid == null || up == null) return null;
    if (mid == 0) return null;
    final width = (up - low) / mid;
    return width;"""
if old_squeeze in ad:
    ad = ad.replace(old_squeeze, new_squeeze)
    print('✅ Fixed bollingerSqueeze')

old_pump = """    final (low, mid, up) = Indicators.bollinger(closes, 20, 2);
    if (low != null && mid != 0) {
      final width = (up! - low) / mid;
      if (width < 0.02) score += 20;
      else if (width < 0.04) score += 10;
    }"""
new_pump = """    final (low, mid, up) = Indicators.bollinger(closes, 20, 2);
    if (low != null && mid != null && up != null && mid != 0) {
      final width = (up - low) / mid;
      if (width < 0.02) score += 20;
      else if (width < 0.04) score += 10;
    }"""
if old_pump in ad:
    ad = ad.replace(old_pump, new_pump)
    print('✅ Fixed PumpScanner bollinger')

old_bb = """    final (bL, bM, bU) = Indicators.bollinger(closes, 20, 2);
    if (bL != null && bM != null && bU != null) {
      if (closes.last <= bL) { score += 10; r.add('BB-low'); }
      else if (closes.last < bM) { score += 5; }
    }"""
if old_bb not in ad:
    # try alternate form
    old_bb2 = """    final (lowBB, midBB, upBB) = Indicators.bollinger(closes, 20, 2);
    if (lowBB != null && midBB != null && upBB != null) {
      if (closes.last <= lowBB) { score += 10; r.add('BB-low'); }
      else if (closes.last < midBB) { score += 5; }
    }"""
    if old_bb2 in ad:
        print('✅ BB block found with alt names')

# Learning engine: min/max return num in some cases
old_lw = """      if (wr >= 65) {
        ind.weight = min(2.0, ind.weight * 1.05);
      } else if (wr < 45) {
        ind.weight = max(0.3, ind.weight * 0.95);
      }"""
new_lw = """      if (wr >= 65) {
        ind.weight = min(2.0, ind.weight * 1.05).toDouble();
      } else if (wr < 45) {
        ind.weight = max(0.3, ind.weight * 0.95).toDouble();
      }"""
if old_lw in ad:
    ad = ad.replace(old_lw, new_lw)
    print('✅ Fixed LearningEngine min/max')

old_thr = """    if (wr >= 60) return max(40, base - 5);
    if (wr < 40) return min(85, base + 10);
    return base;"""
new_thr = """    if (wr >= 60) return max(40, base - 5).toInt();
    if (wr < 40) return min(85, base + 10).toInt();
    return base;"""
if old_thr in ad:
    ad = ad.replace(old_thr, new_thr)
    print('✅ Fixed adaptiveThreshold')

with open('lib/advanced.dart', 'w') as f:
    f.write(ad)

print('\n🎉 All fixes applied!')
