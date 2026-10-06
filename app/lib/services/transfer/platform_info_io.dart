import 'dart:io';

/// True on a real Android device (not in widget tests on a desktop host).
bool get isAndroidDevice => Platform.isAndroid;
