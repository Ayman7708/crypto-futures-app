with open('lib/main.dart', 'r', encoding='utf-8') as f:
    src = f.read()

checks = []

# Import background service
if "import 'package:flutter_background_service/flutter_background_service.dart';" not in src:
    src = src.replace(
        "import 'package:wakelock_plus/wakelock_plus.dart';",
        "import 'package:wakelock_plus/wakelock_plus.dart';\nimport 'package:flutter_background_service/flutter_background_service.dart';\nimport 'package:flutter_background_service_android/flutter_background_service_android.dart';"
    )
    checks.append(('import bg service', 'flutter_background_service' in src))
else:
    checks.append(('import bg service', True))

# Modify _toggleBot to start/stop background service
old_start = """  void _toggleBot() {
    if (_running) {
      _timer?.cancel();
      setState(() => _running = false);
    } else {
      setState(() => _running = true);
      _tick();
      _timer = Timer.periodic(const Duration(seconds: LOOP_SECONDS), (_) => _tick());
    }
  }"""

new_start = """  void _toggleBot() {
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
  }

  Future<void> _startBackgroundService() async {
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onBackgroundStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: 'crypto_bot_bg',
        initialNotificationTitle: 'بوت التداول يعمل',
        initialNotificationContent: 'المراقبة جارية...',
        foregroundServiceNotificationId: 888,
        foregroundServiceTypes: [AndroidForegroundType.dataSync],
      ),
      iosConfiguration: IosConfiguration(autoStart: true, onForeground: _onBackgroundStart),
    );
    await service.startService();
  }

  Future<void> _stopBackgroundService() async {
    final service = FlutterBackgroundService();
    service.invoke('stopService');
  }

  @pragma('vm:entry-point')
  static void _onBackgroundStart(ServiceInstance service) async {
    // Background service is alive; actual trading happens in main isolate with wakelock
    if (service is AndroidServiceInstance) {
      service.on('stopService').listen((event) {
        service.stopSelf();
      });
      service.setAsForegroundService();
    }
    // Keep-alive loop
    Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (service is AndroidServiceInstance) {
        await service.setForegroundNotificationInfo(
          title: 'بوت التداول يعمل',
          content: 'المراقبة جارية ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
        );
      }
    });
  }"""

if old_start in src:
    src = src.replace(old_start, new_start)
    checks.append(('bg service toggle', '_startBackgroundService' in src))
else:
    checks.append(('bg service toggle', False))

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(src)

print('=== Background Service ===')
for name, ok in checks:
    print(('✅' if ok else '❌') + ' ' + name)
print('==========================')
