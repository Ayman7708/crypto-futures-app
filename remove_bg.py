with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

# 1) Remove background service imports
src = src.replace("import 'package:flutter_background_service/flutter_background_service.dart';\n", "")
src = src.replace("import 'package:flutter_background_service_android/flutter_background_service_android.dart';\n", "")

# 2) Revert _toggleBot to simple version (no background service)
old_toggle = """  void _toggleBot() {
    if (_running) {
      _timer?.cancel();
      setState(() => _running = false);
      _stopBackgroundService();
      NotificationService.show('⏹ إيقاف البوت', 'تم إيقاف التداول الآلي');
    } else {
      setState(() => _running = true);
      _startBackgroundService();
      _tick();
      _timer = Timer.periodic(const Duration(seconds: LOOP_SECONDS), (_) => _tick());
      NotificationService.show('▶ بدء البوت', 'البوت يعمل في الخلفية الآن');
    }
  }"""

new_toggle = """  void _toggleBot() {
    if (_running) {
      _timer?.cancel();
      setState(() => _running = false);
      NotificationService.show('⏹ إيقاف البوت', 'تم إيقاف التداول الآلي');
    } else {
      setState(() => _running = true);
      _tick();
      _timer = Timer.periodic(const Duration(seconds: LOOP_SECONDS), (_) => _tick());
      NotificationService.show('▶ بدء البوت', 'البوت يعمل — لا تغلق التطبيق');
    }
  }"""

if old_toggle in src:
    src = src.replace(old_toggle, new_toggle)
    print("✅ Reverted _toggleBot")

# 3) Remove background service methods (with @pragma)
import re
pattern = r"  Future<void> _startBackgroundService\(\) async \{.*?\n  \}\n\n  Future<void> _stopBackgroundService\(\) async \{.*?\n  \}\n\n  @pragma\('vm:entry-point'\)\n  static void _onBackgroundStart\(ServiceInstance service\) async \{.*?\n  \}\n"
src = re.sub(pattern, "", src, flags=re.DOTALL)

# Fallback: try alternative patterns
if '_startBackgroundService' in src:
    # Find and remove each method individually
    for method_name in ['_startBackgroundService', '_stopBackgroundService', '_onBackgroundStart']:
        m = re.search(rf"  Future<void> {method_name}\(\) async \{{.*?\n  \}}\n\n", src, re.DOTALL)
        if m:
            src = src.replace(m.group(0), "")
            print(f"✅ Removed {method_name}")

if '@pragma' in src:
    m = re.search(r"  @pragma\('vm:entry-point'\)\n  static void _onBackgroundStart.*?\n  \}\n", src, re.DOTALL)
    if m:
        src = src.replace(m.group(0), "")
        print("✅ Removed _onBackgroundStart with pragma")

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

# Verify
with open('lib/main.dart', 'r', encoding='utf-8') as f:
    final = f.read()

print()
print(f"❓ flutter_background_service references: {final.count('flutter_background_service')}")
print(f"❓ _startBackgroundService: {final.count('_startBackgroundService')}")
print(f"❓ _onBackgroundStart: {final.count('_onBackgroundStart')}")
print(f"📊 Braces: {final.count('{')} open / {final.count('}')} close")
print(f"📊 Wakelock still active: {'WakelockPlus.enable()' in final}")
