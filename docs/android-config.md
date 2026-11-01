# Cấu hình Android (làm một lần sau `flutter create`)

> Đã làm sẵn trong repo (PR "Cấu hình Android"). File này giữ lại để giải thích trong báo cáo.

## 1. `android/app/src/main/AndroidManifest.xml`

Thêm các dòng **quyền** ngay dưới thẻ `<manifest ...>` (trước `<application`):

```xml
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
    <uses-permission android:name="android.permission.VIBRATE" />
    <!-- Chỉ Android 9 trở xuống mới cần để lưu ảnh QR -->
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
        android:maxSdkVersion="28" />
```

Đổi tên app hiển thị: trong thẻ `<application`, sửa `android:label="chia_tien"` thành
`android:label="Alo, Trả Tiền!"`.

Thêm 2 receiver cho thông báo hẹn giờ, đặt **bên trong** `<application>`, ngay trước `</application>`:

```xml
        <receiver android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
```

## 2. `android/app/build.gradle.kts`

`flutter_local_notifications` cần bật *desugaring*. Trong khối `android { ... }`:

```kotlin
    compileOptions {
        isCoreLibraryDesugaringEnabled = true      // thêm dòng này
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
```

Trong `defaultConfig { ... }` thêm:

```kotlin
        multiDexEnabled = true
```

Cuối file (ngoài khối `android`), thêm:

```kotlin
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

Nếu project của bạn là `build.gradle` (Groovy, không có `.kts`) thì viết:
`coreLibraryDesugaringEnabled true`, `multiDexEnabled true` và
`coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'`.

## 3. Nếu build báo lỗi phiên bản Android Gradle Plugin

`flutter_local_notifications` cần AGP 8.11.1 trở lên. Mở `android/settings.gradle.kts`, tìm dòng
`id("com.android.application") version "..."` và đổi thành `"8.11.1"` (hoặc cao hơn) nếu đang thấp hơn.
