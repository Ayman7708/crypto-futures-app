import re

# ============ 1. Fix indicators_v2.dart: make _ema public ============
with open('lib/indicators_v2.dart', 'r', encoding='utf-8') as f:
    v2 = f.read()

# Make _ema public
v2 = v2.replace("  static double? _ema(List<double> arr, int period) {",
                "  static double? emaCalc(List<double> arr, int period) {")
v2 = v2.replace("  static List<double> _emaSeries(List<double> arr, int period) {",
                "  static List<double> emaSeriesCalc(List<double> arr, int period) {")
v2 = v2.replace("_emaSeries(", "emaSeriesCalc(")
v2 = v2.replace("_ema(arr,", "emaCalc(arr,")
v2 = v2.replace("_ema(a,", "emaCalc(a,")
v2 = v2.replace("_ema(c,", "emaCalc(c,")
v2 = v2.replace("_ema(e,", "emaCalc(e,")

with open('lib/indicators_v2.dart', 'w', encoding='utf-8') as f:
    f.write(v2)
print("✅ indicators_v2.dart: _ema → emaCalc, _emaSeries → emaSeriesCalc")

# ============ 2. Fix indicators_v3.dart: same ============
with open('lib/indicators_v3.dart', 'r', encoding='utf-8') as f:
    v3 = f.read()

v3 = v3.replace("  static double? _ema(List<double> arr, int p) {",
                "  static double? emaCalc(List<double> arr, int p) {")
v3 = v3.replace("_ema(", "emaCalc(")
v3 = v3.replace("_sma(", "smaCalc(")
v3 = v3.replace("  static double? smaCalc(List<double> arr, int p) {",
                "  static double? smaCalc(List<double> arr, int p) {")

# Fix the earlier double replace
v3 = v3.replace("  static double? emaCalc(List<double> arr, int p) {",
                "  static double? emaCalc(List<double> arr, int p) {")

with open('lib/indicators_v3.dart', 'w', encoding='utf-8') as f:
    f.write(v3)
print("✅ indicators_v3.dart: _ema → emaCalc, _sma → smaCalc")

# ============ 3. Fix master_signal.dart ============
with open('lib/master_signal.dart', 'r', encoding='utf-8') as f:
    ms = f.read()

# Replace incorrect access to private member
ms = ms.replace("IndicatorsV2._ema(closes, 12)", "IndicatorsV2.emaCalc(closes, 12)")
ms = ms.replace("IndicatorsV2._ema(closes, 26)", "IndicatorsV2.emaCalc(closes, 26)")

with open('lib/master_signal.dart', 'w', encoding='utf-8') as f:
    f.write(ms)
print("✅ master_signal.dart: IndicatorsV2._ema → emaCalc")

# ============ 4. Verify no more _ema calls ============
for f in ['lib/indicators_v2.dart', 'lib/indicators_v3.dart', 'lib/master_signal.dart']:
    with open(f, 'r', encoding='utf-8') as fp:
        c = fp.read()
    bad = re.findall(r'\b_ema\b|\b_emaSeries\b|\b_sma\b', c)
    # _sma is allowed in engine.dart but not in these
    print(f"  {f}: {len(bad)} private refs remaining")

print("\n🎉 Done!")
