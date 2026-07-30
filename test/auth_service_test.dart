import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quickdrop/auth_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('login persists across a new service instance', () async {
    final authService = AuthService();

    await authService.loginLocally(
      name: 'Test User',
      phone: '1234567890',
    );

    expect(await authService.isLoggedIn(), isTrue);

    final restartedService = AuthService();
    expect(await restartedService.isLoggedIn(), isTrue);

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    expect(prefs.getBool('user_logged_in'), isTrue);
    expect(prefs.getString('user_phone'), '1234567890');
  });

  test('signOut clears the stored login session', () async {
    final authService = AuthService();

    await authService.loginLocally(
      name: 'Test User',
      phone: '1234567890',
    );
    expect(await authService.isLoggedIn(), isTrue);

    await authService.signOut();

    final restartedService = AuthService();
    expect(await restartedService.isLoggedIn(), isFalse);

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    expect(prefs.getBool('user_logged_in'), isNull);
    expect(prefs.getString('user_phone'), isNull);
  });
}
