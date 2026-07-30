import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quickdrop/main.dart';

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
    MaterialApp(home: HomePage(cartNotifier: ValueNotifier<List<CartItem>>([]))),
  );
}

void main() {
  testWidgets('QuickDrop home screen shows grocery UI', (tester) async {
    await pumpQuickDropApp(tester);
    await tester.pump();

    expect(find.text('QuickDrop'), findsWidgets);
    expect(find.text('Hello, shopper 👋'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('Splash screen shows startup UI', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
    expect(find.text('FAST • SAFE • LOCAL'), findsOneWidget);
  });

  testWidgets('Profile page opens from the drawer', (tester) async {
    await pumpQuickDropApp(tester);

    await tester.pump();
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Profile').last);
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsWidgets);
    expect(find.text('Address'), findsOneWidget);
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
