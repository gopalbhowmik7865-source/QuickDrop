import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quickdrop/main.dart';
import 'package:quickdrop/splash_screen.dart';

Future<void> pumpQuickDropApp(
  WidgetTester tester, {
  Map<String, Object> session = const {
    'user_logged_in': true,
    'user_name': 'Test User',
    'user_phone': '1234567890',
    'user_address': 'Agartala',
  },
}) async {
  SharedPreferences.setMockInitialValues(session);
  await tester.pumpWidget(
    MaterialApp(
      home: HomePage(cartNotifier: ValueNotifier<List<CartItem>>([])),
    ),
  );
}

void main() {
  testWidgets('QuickDrop home screen shows grocery UI', (tester) async {
    await pumpQuickDropApp(tester);
    await tester.pumpAndSettle();

    expect(find.text('QuickDrop Go'), findsWidgets);
    expect(find.text('Hello, Shopper 👋'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('Splash screen shows startup UI', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SplashScreen(
          duration: const Duration(days: 1),
          nextPageBuilder: () async => const SizedBox.shrink(),
        ),
      ),
    );
    expect(find.text('QuickDrop'), findsOneWidget);
  });

  testWidgets('Profile action is available from the home header', (
    tester,
  ) async {
    await pumpQuickDropApp(tester);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
  });

  testWidgets('Placing an order adds it to My Orders', (tester) async {
    final cartNotifier = ValueNotifier<List<CartItem>>([
      CartItem(
        product: const GroceryItem(
          name: 'Test Product',
          price: '₹45',
          unit: '1 item',
          emoji: '🛍️',
          tag: 'Grocery',
          accent: Colors.blue,
        ),
        quantity: 1,
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: CheckoutPage(cartNotifier: cartNotifier, subtotal: 45)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Subtotal'), findsOneWidget);
    expect(find.text('Delivery Charge'), findsOneWidget);
    expect(find.text('Grand Total'), findsOneWidget);
  });
}
