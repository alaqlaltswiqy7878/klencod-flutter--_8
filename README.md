# جدولي اليومي — Flutter

مشروع جدول يومي عربي مبني باستخدام Flutter وDart.

## المتطلبات
- Flutter SDK متوافق مع Dart 3.3 أو أحدث.
- Android SDK وJava 17 لعملية بناء Android.
- الاتصال بالإنترنت مطلوب أول مرة لتنزيل الحزم، ثم تعمل المهام الأساسية محليًا.

## فتح المشروع
1. فك ضغط الملف.
2. افتح المجلد الذي يحتوي على `pubspec.yaml` داخل Klencode IDE.
3. شغّل `flutter pub get`.
4. شغّل `flutter analyze`.
5. لبناء APK: `flutter build apk --release`.

## ملاحظات
- بيانات المهام تحفظ محليًا عبر SharedPreferences.
- الإشعارات محلية، لكن وصولها وتوقيتها قد يتأثر بإعدادات Android والبطارية والأذونات.
- اسم التطبيق وأيقونته واسم الحزمة قابلة للتغيير لاحقًا.
- تمت إزالة `flutter_timezone` القديمة المتعارضة مع Flutter الحديث، وتستخدم جدولة الإشعارات منطقة `Asia/Riyadh` لتفادي خطأ `Unresolved reference: Registrar`.
- تم رفع `compileSdk` إلى 36 لأن إصدار `shared_preferences_android` المستخدم يتطلب Android SDK 36.
- لم يتم الادعاء بأن APK تم بناؤه فعليًا ضمن هذه الحزمة؛ يلزم اختبار المشروع داخل بيئة Flutter.
