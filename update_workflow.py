with open('.github/workflows/build.yml', 'r', encoding='utf-8') as f:
    wf = f.read()

# Add foreground service permission + service declaration
old_perm = '''          sed -i 's|<application|<uses-permission android:name="android.permission.WAKE_LOCK"/><application|' "$MANIFEST"'''
new_perm = '''          sed -i 's|<application|<uses-permission android:name="android.permission.WAKE_LOCK"/><application|' "$MANIFEST"
          sed -i 's|<application|<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/><application|' "$MANIFEST"
          sed -i 's|<application|<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"/><application|' "$MANIFEST"
          sed -i 's|<application|<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/><application|' "$MANIFEST"'''

if old_perm in wf:
    wf = wf.replace(old_perm, new_perm)
    print("✅ Workflow updated with foreground service permissions")
else:
    print("⚠️ Permission block not found")

with open('.github/workflows/build.yml', 'w', encoding='utf-8') as f:
    f.write(wf)
