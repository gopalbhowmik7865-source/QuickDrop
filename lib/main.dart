import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'dart:developer' as developer;
import 'dart:async';
import 'auth_service.dart';
import 'login_page.dart';
import 'push_notification_service.dart';
import 'profile_page.dart';
import 'firebase_options.dart';
import 'notifications_screen.dart';
import 'screens/location_picker_screen.dart';
import 'category_routing.dart';

final GlobalKey<ScaffoldMessengerState> appScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

late QuickDropNotificationService quickDropNotificationService;

Future<void> _openCustomerOrderDetails(String orderId) async {
  appNavigatorKey.currentState?.push(
    MaterialPageRoute(builder: (_) => OrderDetailsPage(orderId: orderId)),
  );
}

void cartLog(String message, {Object? error, StackTrace? stackTrace}) {
  developer.log(
    message,
    name: 'QuickDropCart',
    error: error,
    stackTrace: stackTrace,
  );
}

String cartErrorLocation(StackTrace stackTrace) {
  final lines = stackTrace.toString().split('\n');
  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.contains('main.dart')) {
      return line;
    }
  }

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isNotEmpty) {
      return line;
    }
  }

  return 'No stack location available';
}

void showCartExceptionSnackbar(
  BuildContext context,
  Object error,
  StackTrace stackTrace,
) {
  final location = cartErrorLocation(stackTrace);
  final snackBar = SnackBar(
    duration: const Duration(seconds: 7),
    content: Text('Add to Cart failed: $error\n$location'),
  );

  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger != null) {
    messenger.showSnackBar(snackBar);
    return;
  }

  appScaffoldMessengerKey.currentState?.showSnackBar(snackBar);
}

String _extractProductImageUrl(Map<String, dynamic> data) {
  final value = data['imageUrl'];
  if (value is String) {
    return value;
  }
  return value?.toString() ?? '';
}

String extractProductImageUrl(Map<String, dynamic> data) =>
    _extractProductImageUrl(data);

class GroceryItem {
  final String? productId;
  final String name;
  final String price;
  final String unit;
  final String emoji;
  final String tag;
  final Color accent;
  final int stock;
  final String imageUrl;

  const GroceryItem({
    this.productId,
    required this.name,
    required this.price,
    required this.unit,
    required this.emoji,
    required this.tag,
    required this.accent,
    this.stock = 999,
    this.imageUrl = '',
  });
}

class CartItem {
  final GroceryItem product;
  int quantity;

  CartItem({required this.product, required this.quantity});
}

class MainCategory {
  final String title;
  final String emoji;
  final Color color;
  final String firestoreCategory;
  final List<String> subcategories;

  const MainCategory({
    required this.title,
    required this.emoji,
    required this.color,
    required this.firestoreCategory,
    required this.subcategories,
  });
}

const List<MainCategory> homeMainCategories = [
  MainCategory(
    title: 'Grocery',
    emoji: '🛒',
    color: Color(0xFFEAF3FF),
    firestoreCategory: 'Grocery',
    subcategories: [
      'Atta, Rice & Dal',
      'Oil, Ghee & Masala',
      'Fruits & Vegetables',
      'Dairy & Eggs',
    ],
  ),
  MainCategory(
    title: 'Food',
    emoji: '🍔',
    color: Color(0xFFFFF3E8),
    firestoreCategory: 'Food',
    subcategories: ['Restaurant Food', 'Fast Food', 'Beverages', 'Sweets'],
  ),
  MainCategory(
    title: 'Gifts',
    emoji: '💐',
    color: Color(0xFFFFECF4),
    firestoreCategory: 'Gifts',
    subcategories: ['Flowers', 'Chocolates', 'Soft Toys', 'Gift Combos'],
  ),
  MainCategory(
    title: 'Gifts & Surprises',
    emoji: '🎁',
    color: Color(0xFFFFECF4),
    firestoreCategory: 'Gifts',
    subcategories: ['Surprise your loved ones'],
  ),
  MainCategory(
    title: 'Cosmetics',
    emoji: '💄',
    color: Color(0xFFF2EEFF),
    firestoreCategory: 'Cosmetics',
    subcategories: ['Bath & Body', 'Hair Care', 'Beauty Products'],
  ),
  MainCategory(
    title: 'Electronics',
    emoji: '📱',
    color: Color(0xFFEAF1FF),
    firestoreCategory: 'Electronics',
    subcategories: [
      'Chargers',
      'Earphones',
      'Power Banks',
      'Mobile Accessories',
    ],
  ),
  MainCategory(
    title: 'Home Service',
    emoji: '🏠',
    color: Color(0xFFEFF6FF),
    firestoreCategory: 'Home Service',
    subcategories: [],
  ),
  MainCategory(
    title: 'Parcel Delivery',
    emoji: '📦',
    color: Color(0xFFFFF7ED),
    firestoreCategory: 'Parcel Delivery',
    subcategories: [],
  ),
];

class _UjjayantaPalaceWatermarkPainter extends CustomPainter {
  _UjjayantaPalaceWatermarkPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.shortestSide * 0.016).clamp(1.0, 1.8)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;

    final base = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.12, h * 0.53, w * 0.66, h * 0.20),
      Radius.circular(w * 0.03),
    );
    canvas.drawRRect(base, paint);

    final roof = Path()
      ..moveTo(w * 0.18, h * 0.53)
      ..lineTo(w * 0.28, h * 0.39)
      ..lineTo(w * 0.40, h * 0.31)
      ..lineTo(w * 0.52, h * 0.39)
      ..lineTo(w * 0.62, h * 0.53);
    canvas.drawPath(roof, paint);

    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.40, h * 0.30), width: w * 0.16, height: h * 0.18),
      paint,
    );
    canvas.drawLine(
      Offset(w * 0.40, h * 0.12),
      Offset(w * 0.40, h * 0.22),
      paint,
    );
    canvas.drawLine(
      Offset(w * 0.38, h * 0.14),
      Offset(w * 0.42, h * 0.14),
      paint,
    );

    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.24, h * 0.40), width: w * 0.11, height: h * 0.12),
      paint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.56, h * 0.40), width: w * 0.11, height: h * 0.12),
      paint,
    );
    canvas.drawLine(Offset(w * 0.24, h * 0.34), Offset(w * 0.24, h * 0.28), paint);
    canvas.drawLine(Offset(w * 0.56, h * 0.34), Offset(w * 0.56, h * 0.28), paint);

    final leftWing = Path()
      ..moveTo(w * 0.12, h * 0.53)
      ..lineTo(w * 0.05, h * 0.46)
      ..lineTo(w * 0.10, h * 0.40)
      ..lineTo(w * 0.18, h * 0.46)
      ..lineTo(w * 0.18, h * 0.53);
    canvas.drawPath(leftWing, paint);

    final rightWing = Path()
      ..moveTo(w * 0.78, h * 0.53)
      ..lineTo(w * 0.88, h * 0.46)
      ..lineTo(w * 0.94, h * 0.40)
      ..lineTo(w * 0.90, h * 0.36)
      ..lineTo(w * 0.82, h * 0.43)
      ..lineTo(w * 0.82, h * 0.53);
    canvas.drawPath(rightWing, paint);

    canvas.drawLine(Offset(w * 0.07, h * 0.73), Offset(w * 0.84, h * 0.73), paint);
    canvas.drawLine(Offset(w * 0.16, h * 0.69), Offset(w * 0.76, h * 0.69), paint);
    canvas.drawLine(Offset(w * 0.24, h * 0.65), Offset(w * 0.68, h * 0.65), paint);

    for (final dx in <double>[0.21, 0.30, 0.40, 0.50, 0.60]) {
      final x = w * dx;
      canvas.drawArc(
        Rect.fromCenter(center: Offset(x, h * 0.61), width: w * 0.045, height: h * 0.08),
        3.14159,
        3.14159,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _UjjayantaPalaceWatermarkPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class Order {
  final String id;
  final List<CartItem> items;
  final int totalAmount;
  final OrderStatus status;
  final String address;

  const Order({
    required this.id,
    required this.items,
    required this.totalAmount,
    required this.status,
    required this.address,
  });

  String get itemSummary {
    return items
        .map((item) => '${item.product.name} x${item.quantity}')
        .join(', ');
  }
}

enum OrderStatus {
  pending,
  accepted,
  packed,
  outForDelivery,
  delivered,
  cancelled,
}

extension OrderStatusX on OrderStatus {
  String get label {
    switch (this) {
      case OrderStatus.pending:
        return 'Pending';
      case OrderStatus.accepted:
        return 'Accepted';
      case OrderStatus.packed:
        return 'Packed';
      case OrderStatus.outForDelivery:
        return 'Out for Delivery';
      case OrderStatus.delivered:
        return 'Delivered';
      case OrderStatus.cancelled:
        return 'Cancelled';
    }
  }
}

const List<OrderStatus> _orderProgressStages = <OrderStatus>[
  OrderStatus.pending,
  OrderStatus.accepted,
  OrderStatus.packed,
  OrderStatus.outForDelivery,
  OrderStatus.delivered,
];

OrderStatus _orderStatusFromValue(dynamic value) {
  final normalized = value?.toString().trim().toLowerCase() ?? '';

  switch (normalized) {
    case 'pending':
      return OrderStatus.pending;
    case 'accepted':
    case 'confirmed':
      return OrderStatus.accepted;
    case 'packed':
      return OrderStatus.packed;
    case 'out for delivery':
    case 'outfordelivery':
    case 'out_for_delivery':
      return OrderStatus.outForDelivery;
    case 'delivered':
      return OrderStatus.delivered;
    case 'cancelled':
    case 'canceled':
      return OrderStatus.cancelled;
    default:
      return OrderStatus.pending;
  }
}

Color _orderStatusColor(OrderStatus status) {
  switch (status) {
    case OrderStatus.pending:
      return Colors.orange;
    case OrderStatus.accepted:
      return Colors.blue;
    case OrderStatus.packed:
      return Colors.deepPurple;
    case OrderStatus.outForDelivery:
      return Colors.teal;
    case OrderStatus.delivered:
      return Colors.green;
    case OrderStatus.cancelled:
      return Colors.red;
  }
}

IconData _orderStatusIcon(OrderStatus status) {
  switch (status) {
    case OrderStatus.pending:
      return Icons.hourglass_top_outlined;
    case OrderStatus.accepted:
      return Icons.verified_outlined;
    case OrderStatus.packed:
      return Icons.inventory_2_outlined;
    case OrderStatus.outForDelivery:
      return Icons.local_shipping_outlined;
    case OrderStatus.delivered:
      return Icons.done_all_outlined;
    case OrderStatus.cancelled:
      return Icons.cancel_outlined;
  }
}

int parsePrice(String price) {
  return int.tryParse(price.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } on FirebaseException catch (error) {
    developer.log(
      'Firebase initialization failed: ${error.message ?? error.toString()}',
      name: 'QuickDrop',
      error: error,
    );
  } catch (error, stackTrace) {
    developer.log(
      'Firebase initialization failed: $error',
      name: 'QuickDrop',
      error: error,
      stackTrace: stackTrace,
    );
  }

  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(quickDropMessagingBackgroundHandler);
  }

  runApp(
    QuickDropApp(firebaseInitialization: Future.value(Firebase.app())),
  );
}

class QuickDropApp extends StatefulWidget {
  const QuickDropApp({super.key, required this.firebaseInitialization});

  final Future<FirebaseApp> firebaseInitialization;

  @override
  State<QuickDropApp> createState() => _QuickDropAppState();
}

class _QuickDropAppState extends State<QuickDropApp> {
  final ValueNotifier<List<CartItem>> cartNotifier =
      ValueNotifier<List<CartItem>>([]);
  final AuthService _authService = AuthService();
  late QuickDropNotificationService _notificationService;
  late Future<void> _startupFuture;

  @override
  void initState() {
    super.initState();
    _startupFuture = _buildStartupFuture();
  }

  Future<void> _buildStartupFuture() async {
    await widget.firebaseInitialization;
    _notificationService = QuickDropNotificationService(
      authService: _authService,
      onOrderTap: _openCustomerOrderDetails,
    );
    quickDropNotificationService = _notificationService;
    await _initializeNotificationsSafely();
  }

  Future<void> _initializeNotificationsSafely() async {
    try {
      await _notificationService.initialize();
    } catch (error, stackTrace) {
      cartLog(
        'Notification service initialization failed during startup.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _retryStartup() {
    setState(() {
      _startupFuture = _buildStartupFuture();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: appScaffoldMessengerKey,
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'QuickDrop Go',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7FAFF),
      ),
      home: FutureBuilder<void>(
        future: _startupFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SplashScreen(loadingText: 'Starting QuickDrop Go...');
          }

          if (snapshot.hasError) {
            return StartupErrorScreen(
              error: snapshot.error,
              onRetry: _retryStartup,
            );
          }

          return AuthGate(
            cartNotifier: cartNotifier,
            authService: _authService,
          );
        },
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.cartNotifier,
    required this.authService,
  });

  final ValueNotifier<List<CartItem>> cartNotifier;
  final AuthService authService;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Future<bool> _isLoggedInFuture;

  @override
  void initState() {
    super.initState();
    _isLoggedInFuture = widget.authService.isLoggedIn();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isLoggedInFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen(loadingText: 'Checking your session...');
        }

        if (snapshot.data == true) {
          return HomePage(cartNotifier: widget.cartNotifier);
        }

        return LoginPage(cartNotifier: widget.cartNotifier);
      },
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key, this.loadingText = 'Loading...'});

  final String loadingText;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0D6EFD), Color(0xFF4DA3FF), Color(0xFF87D4FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -60,
              left: -40,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              bottom: -70,
              right: -30,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(36),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.14),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: Image.asset(
                          'lib/assets/images/file_000000007bc4720796b22bf2c89f8dc7.png',
                          width: 108,
                          height: 108,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'QuickDrop Go',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 38,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.6,
                        shadows: [
                          Shadow(
                            color: Colors.black26,
                            blurRadius: 10,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'FAST • SAFE • LOCAL',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.8,
                      ),
                    ),
                    const SizedBox(height: 36),
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.8,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      loadingText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Any Item Delivered in 30 Minutes',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Agartala, Tripura',
                      style: TextStyle(color: Colors.white70, fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StartupErrorScreen extends StatelessWidget {
  const StartupErrorScreen({
    super.key,
    required this.error,
    required this.onRetry,
  });

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFEAF3FF), Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.cloud_off_outlined,
                  size: 56,
                  color: Colors.blue,
                ),
                const SizedBox(height: 14),
                const Text(
                  'Unable to start QuickDrop Go',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  (error ?? 'Unknown startup error').toString(),
                  style: const TextStyle(color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final ValueNotifier<List<CartItem>> cartNotifier;

  const HomePage({super.key, required this.cartNotifier});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const bool _isFlutterTest = bool.fromEnvironment('FLUTTER_TEST');
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final PageController _bannerController = PageController(viewportFraction: 1);
  Timer? _bannerTimer;

  bool _enableProductStream = false;
  int _bannerIndex = 0;
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _enableProductStream = true;
      });
    });
    if (!_isFlutterTest) {
      _startBannerAutoSlide();
    }
  }

  void _startBannerAutoSlide() {
    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_bannerController.hasClients) {
        return;
      }
      final nextPage = (_bannerIndex + 1) % 3;
      _bannerController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _openCategoryPage(MainCategory category) {
    if (category.title == 'Gifts & Surprises') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GiftCategoryPage(cartNotifier: widget.cartNotifier),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CategoryProductsPage(
          cartNotifier: widget.cartNotifier,
          title: category.title,
          firestoreCategory: category.firestoreCategory,
          accent: Colors.blue.shade700,
          subcategories: category.subcategories,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _bannerController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String _priceText(dynamic value) {
    if (value is num) {
      if (value % 1 == 0) {
        return '₹${value.toInt()}';
      }
      return '₹${value.toStringAsFixed(2)}';
    }

    final parsed = double.tryParse(
      value?.toString().replaceAll(RegExp(r'[^0-9.]'), '') ?? '',
    );
    if (parsed != null) {
      if (parsed % 1 == 0) {
        return '₹${parsed.toInt()}';
      }
      return '₹${parsed.toStringAsFixed(2)}';
    }

    return value?.toString() ?? '₹0';
  }

  double? _toDouble(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString().replaceAll(RegExp(r'[^0-9.]'), ''));
  }

  int _discountPercent({double? price, double? oldPrice, dynamic discount}) {
    final fromField = _toDouble(discount);
    if (fromField != null && fromField > 0) {
      return fromField.round();
    }

    if (oldPrice != null && price != null && oldPrice > price && oldPrice > 0) {
      return (((oldPrice - price) / oldPrice) * 100).round();
    }
    return 0;
  }

  int _bestSellerScore(Map<String, dynamic> data) {
    final sold = (_toDouble(data['sold']) ??
            _toDouble(data['soldCount']) ??
            _toDouble(data['sales']) ??
            _toDouble(data['orders']) ??
            0)
        .round();
    final rating = ((_toDouble(data['rating']) ?? 0) * 100).round();
    final reviews = (_toDouble(data['reviewCount']) ?? 0).round();
    return sold * 8 + rating + reviews;
  }

  bool _isOfferItem(Map<String, dynamic> data, _HomeProductItem item) {
    if (item.discountPercent > 0) {
      return true;
    }

    final hasOfferTag = [
      data['offerTag'],
      data['label'],
      data['badge'],
      data['tag'],
      data['offer'],
    ].any((value) {
      final text = value?.toString().toLowerCase() ?? '';
      return text.contains('offer') ||
          text.contains('deal') ||
          text.contains('sale') ||
          text.contains('%');
    });

    return hasOfferTag;
  }

  GroceryItem _productFromDoc(Map<String, dynamic> data, {String? productId}) {
    final name = data['name']?.toString() ?? 'Product';
    final category = data['category']?.toString() ?? 'General';
    final stock = (data['stock'] as num?)?.toInt() ?? 999;
    final imageUrl = _extractProductImageUrl(data);

    Color accent;
    final normalized = category.toLowerCase();
    if (normalized.contains('food')) {
      accent = Colors.orange.shade700;
    } else if (normalized.contains('grocery')) {
      accent = Colors.blue.shade700;
    } else if (normalized.contains('gift')) {
      accent = Colors.pink.shade700;
    } else if (normalized.contains('electronic')) {
      accent = Colors.indigo.shade700;
    } else if (normalized.contains('beauty') || normalized.contains('cosmetic')) {
      accent = Colors.purple.shade700;
    } else {
      accent = Colors.blue.shade700;
    }

    return GroceryItem(
      productId: productId,
      name: name,
      price: _priceText(data['price']),
      unit: '1 item',
      emoji: '🛍️',
      tag: category,
      accent: accent,
      stock: stock,
      imageUrl: imageUrl,
    );
  }

  void _addToCart(GroceryItem item) {
    cartLog(
      'Home addToCart invoked for ${item.name} (id=${item.productId}, stock=${item.stock})',
    );

    try {
      if (item.stock <= 0) {
        appScaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('This product is out of stock')),
        );
        return;
      }

      final currentCart = List<CartItem>.from(widget.cartNotifier.value);

      final existingIndex = currentCart.indexWhere(
        (entry) =>
            (entry.product.productId != null &&
                item.productId != null &&
                entry.product.productId == item.productId) ||
            entry.product.name == item.name,
      );

      if (existingIndex >= 0) {
        currentCart[existingIndex].quantity += 1;
      } else {
        currentCart.add(CartItem(product: item, quantity: 1));
      }

      widget.cartNotifier.value = currentCart;

      appScaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('${item.name} added to cart')),
      );
    } catch (error, stackTrace) {
      showCartExceptionSnackbar(context, error, stackTrace);
    }
  }

  void _onBottomNavTap(int index) {
    switch (index) {
      case 1:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GroceryPage(cartNotifier: widget.cartNotifier),
          ),
        );
        break;
      case 2:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const OrdersPage()),
        );
        break;
      case 3:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CartPage(cartNotifier: widget.cartNotifier),
          ),
        );
        break;
      case 4:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AuthProfilePage()),
        );
        break;
      default:
        break;
    }
  }

  Widget _categoryMainCard(BuildContext context, MainCategory category) {
    return InkWell(
      onTap: () {
        _openCategoryPage(category);
      },
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFF1F5F9)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              spreadRadius: 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: category.color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  category.emoji,
                  style: const TextStyle(fontSize: 30),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              category.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: Color(0xFF10213E),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _homeGiftPromoBanner(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bannerHeight = (constraints.maxWidth * 0.24)
            .clamp(180.0, 220.0)
            .toDouble();

        Widget placeholder({required bool loading}) {
          return Container(
            height: bannerHeight,
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.blue.shade100),
            ),
            alignment: Alignment.center,
            child: loading
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.image_not_supported_outlined,
                        color: Colors.blue.shade300,
                        size: 34,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Banner image unavailable',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
          );
        }

        return Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: SizedBox(
                height: bannerHeight,
                child: PageView(
                  controller: _bannerController,
                  onPageChanged: (index) {
                    if (!mounted) {
                      return;
                    }
                    setState(() {
                      _bannerIndex = index;
                    });
                  },
                  children: [
                    InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GiftCategoryPage(
                              cartNotifier: widget.cartNotifier,
                            ),
                          ),
                        );
                      },
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.asset(
                            'assets/banners/gift_banner.jpg',
                            fit: BoxFit.cover,
                            frameBuilder: (
                              context,
                              child,
                              frame,
                              wasSynchronouslyLoaded,
                            ) {
                              if (wasSynchronouslyLoaded || frame != null) {
                                return child;
                              }
                              return placeholder(loading: true);
                            },
                            errorBuilder: (_, _, _) => placeholder(loading: false),
                          ),
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    Colors.black.withValues(alpha: 0.55),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 14,
                            right: 14,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(999),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Text(
                                'Premium Picks',
                                style: TextStyle(
                                  color: Colors.blue.shade800,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 16,
                            bottom: 16,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(999),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Text(
                                'Gifts & Surprises',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1F2A44),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            const Color(0xFF2563EB),
                            const Color(0xFF1D4ED8),
                            const Color(0xFF60A5FA),
                          ],
                        ),
                      ),
                      padding: const EdgeInsets.all(22),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'POPULAR PICKS',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                          SizedBox(height: 10),
                          Text(
                            'Fresh items delivered\nin 30 minutes',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                            ),
                          ),
                          Spacer(),
                          Text(
                            'Open Popular Products below',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                          colors: [
                            const Color(0xFF1D4ED8),
                            const Color(0xFF2563EB),
                            const Color(0xFF93C5FD),
                          ],
                        ),
                      ),
                      padding: const EdgeInsets.all(22),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TODAY ONLY',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                          SizedBox(height: 10),
                          Text(
                            'Smart savings on\nselected products',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                            ),
                          ),
                          Spacer(),
                          Text(
                            'Check Today\'s Offers below',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                3,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  height: 8,
                  width: _bannerIndex == index ? 24 : 8,
                  decoration: BoxDecoration(
                    color: _bannerIndex == index
                        ? Colors.blue.shade700
                        : Colors.blue.shade200,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F2B5B),
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.blueGrey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProductSection({
    required String title,
    required String subtitle,
    required List<_HomeProductItem> items,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(title, subtitle),
        const SizedBox(height: 14),
        if (items.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.blue.shade50),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.shade100.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Text(
              'No products available right now.',
              style: TextStyle(
                color: Colors.blueGrey.shade500,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          SizedBox(
            height: 205,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemBuilder: (context, index) {
                return SizedBox(
                  width: 136,
                  child: _buildPremiumProductCard(items[index]),
                );
              },
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemCount: items.length,
            ),
          ),
      ],
    );
  }

  Widget _buildPremiumProductCard(_HomeProductItem item) {
    final outOfStock = item.product.stock <= 0;
    final resolvedImageUrl = item.product.imageUrl;

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade50),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade100.withValues(alpha: 0.48),
            blurRadius: 24,
            spreadRadius: 1,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 81,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: resolvedImageUrl.isNotEmpty
                      ? Container(
                          width: double.infinity,
                          height: 81,
                          color: Colors.blue.shade50,
                          alignment: Alignment.center,
                          child: Image.network(
                            resolvedImageUrl,
                            width: 54,
                            height: 54,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.shopping_bag_outlined,
                              color: Colors.blue.shade400,
                              size: 30,
                            ),
                          ),
                        )
                      : Container(
                          width: double.infinity,
                          height: 81,
                          color: Colors.blue.shade50,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.shopping_bag_outlined,
                            color: Colors.blue.shade400,
                            size: 30,
                          ),
                        ),
                ),
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      item.product.tag,
                      style: TextStyle(
                        color: item.product.accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 9,
                      ),
                    ),
                  ),
                ),
                if (item.discountPercent > 0)
                  Positioned(
                    left: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE84141),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${item.discountPercent}% OFF',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.product.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1C2D4D),
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Text(
                item.product.price,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0D5ED9),
                ),
              ),
              if (item.oldPrice != null) ...[
                const SizedBox(width: 6),
                Text(
                  '₹${item.oldPrice!.toStringAsFixed(item.oldPrice! % 1 == 0 ? 0 : 2)}',
                  style: const TextStyle(
                    color: Colors.grey,
                    decoration: TextDecoration.lineThrough,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            outOfStock ? 'Out of stock' : 'In stock: ${item.product.stock}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: outOfStock ? Colors.red.shade600 : Colors.green.shade700,
            ),
          ),
          const SizedBox(height: 3),
          SizedBox(
            height: 30,
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: outOfStock
                  ? null
                  : () {
                      _addToCart(item.product);
                    },
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: EdgeInsets.zero,
              ),
              icon: const Icon(Icons.add_shopping_cart, size: 14),
              label: Text(outOfStock ? 'Out of Stock' : 'Add to Cart'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<CartItem>>(
      valueListenable: widget.cartNotifier,
      builder: (context, cartItems, _) {
        final canUseFirestore = _enableProductStream && Firebase.apps.isNotEmpty;
        final totalItems = cartItems.fold<int>(
          0,
          (totalCount, item) => totalCount + item.quantity,
        );

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: const Color(0xFFF3F8FF),
          drawer: Drawer(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                DrawerHeader(
                  decoration: BoxDecoration(color: Colors.blue.shade700),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'QuickDrop Go',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Fast delivery for your daily needs',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.home_outlined),
                  title: const Text('Home'),
                  onTap: () => Navigator.pop(context),
                ),
                ListTile(
                  leading: const Icon(Icons.shopping_basket_outlined),
                  title: const Text('Grocery'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            GroceryPage(cartNotifier: widget.cartNotifier),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.shopping_cart_outlined),
                  title: const Text('Cart'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            CartPage(cartNotifier: widget.cartNotifier),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Profile'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AuthProfilePage(),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text('My Orders'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OrdersPage()),
                    );
                  },
                ),
              ],
            ),
          ),
          body: SafeArea(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: canUseFirestore
                  ? FirebaseFirestore.instance.collection('products').snapshots()
                  : null,
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? [];
                final allProducts = docs
                    .map((doc) {
                      final data = doc.data();
                      final product = _productFromDoc(data, productId: doc.id);
                      final priceValue = _toDouble(data['price']) ??
                          _toDouble(product.price) ??
                          parsePrice(product.price).toDouble();
                      final oldPrice = _toDouble(data['oldPrice']) ??
                          _toDouble(data['old_price']) ??
                          _toDouble(data['mrp']) ??
                          _toDouble(data['originalPrice']) ??
                          _toDouble(data['strikePrice']) ??
                          _toDouble(data['compareAtPrice']);

                      return _HomeProductItem(
                        product: product,
                        oldPrice: oldPrice != null &&
                                priceValue > 0 &&
                                oldPrice > priceValue
                            ? oldPrice
                            : null,
                        discountPercent: _discountPercent(
                          price: priceValue,
                          oldPrice: oldPrice,
                          discount: data['discount'] ?? data['discountPercent'],
                        ),
                        bestSellerScore: _bestSellerScore(data),
                        raw: data,
                      );
                    })
                    .toList();

                final popularItems = allProducts.take(8).toList();

                final bestSellerItems = List<_HomeProductItem>.from(allProducts)
                  ..sort(
                    (a, b) => b.bestSellerScore.compareTo(a.bestSellerScore),
                  );

                final offerItems = allProducts
                    .where((item) => _isOfferItem(item.raw, item))
                    .toList();

                final offersSectionItems = offerItems.isNotEmpty
                    ? offerItems.take(8).toList()
                    : allProducts.take(8).toList();

                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF60A5FA),
                              Color(0xFF3B82F6),
                              Color(0xFF1D4ED8),
                            ],
                            stops: [0.0, 0.52, 1.0],
                          ),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(28),
                            bottom: Radius.circular(30),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF1D4ED8).withValues(alpha: 0.24),
                              blurRadius: 22,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: SafeArea(
                          bottom: false,
                          child: Stack(
                            children: [
                              Positioned(
                                right: 0,
                                top: -80,
                                child: Opacity(
                                  opacity: 0.11,
                                  child: Image.asset(
                                    'assets/banners/agartala_palace.png',
                                    width: 700,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 16,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: const [
                                          Text.rich(
                                            TextSpan(
                                              children: [
                                                TextSpan(
                                                  text: 'QuickDrop ',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 24,
                                                    fontWeight: FontWeight.w800,
                                                    letterSpacing: 0.25,
                                                  ),
                                                ),
                                                TextSpan(
                                                  text: 'Go',
                                                  style: TextStyle(
                                                    color: Color(0xFFFFC107),
                                                    fontSize: 24,
                                                    fontWeight: FontWeight.w800,
                                                    letterSpacing: 0.25,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                            SizedBox(height: 3),
                                          Text(
                                            'Deliver to',
                                            style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                            SizedBox(height: 3),
                                          Text(
                                            '📍 Agartala, Tripura',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Row(
                                      children: [
                                        Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            InkWell(
                                              onTap: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) => const NotificationsScreen(),
                                                  ),
                                                );
                                              },
                                              borderRadius: BorderRadius.circular(14),
                                              child: Container(
                                                padding: const EdgeInsets.all(10),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius: BorderRadius.circular(999),
                                                  border: Border.all(
                                                    color: const Color(0xFFE5E7EB),
                                                  ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black.withValues(alpha: 0.08),
                                                      blurRadius: 10,
                                                      offset: const Offset(0, 4),
                                                    ),
                                                  ],
                                                ),
                                                child: const Icon(
                                                  Icons.notifications_none_rounded,
                                                  color: Color(0xFF1D4ED8),
                                                  size: 22,
                                                ),
                                              ),
                                            ),
                                            Positioned(
                                              top: 8,
                                              right: 8,
                                              child: Container(
                                                width: 8,
                                                height: 8,
                                                decoration: const BoxDecoration(
                                                  color: Colors.red,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(width: 10),
                                        InkWell(
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => const AuthProfilePage(),
                                              ),
                                            );
                                          },
                                          borderRadius: BorderRadius.circular(14),
                                          child: Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.circular(999),
                                              border: Border.all(
                                                color: const Color(0xFFE5E7EB),
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withValues(alpha: 0.08),
                                                  blurRadius: 10,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ],
                                            ),
                                            child: const Icon(
                                              Icons.person_outline_rounded,
                                              color: Color(0xFF1D4ED8),
                                              size: 22,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'Hello, Shopper 👋',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'What would you like to get today?',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.92),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF97316),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: const Text(
                                        '🚚 20–30 min',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(999),
                                        border: Border.all(color: const Color(0xFFE5E7EB)),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.06),
                                            blurRadius: 8,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.verified_rounded,
                                            size: 14,
                                            color: Color(0xFF2563EB),
                                          ),
                                          SizedBox(width: 5),
                                          Text(
                                            'Trusted Service',
                                            style: TextStyle(
                                              color: Color(0xFF1D4ED8),
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(minHeight: 60),
                                  child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(30),
                                    border: Border.all(
                                      color: const Color(0xFFE5E7EB),
                                      width: 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.06),
                                        blurRadius: 18,
                                        spreadRadius: 0,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: TextField(
                                    controller: _searchController,
                                    onChanged: (value) {
                                      setState(() {
                                        searchQuery = value.toLowerCase().trim();
                                      });
                                    },
                                    decoration: InputDecoration(
                                      hintText: 'Search groceries, food, gifts...',
                                      hintStyle: TextStyle(
                                        color: Colors.grey.shade500.withValues(alpha: 0.95),
                                        fontSize: 19,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      prefixIcon: const Icon(
                                        Icons.search_rounded,
                                        color: Color(0xFF1D4ED8),
                                        size: 28,
                                      ),
                                      suffixIconConstraints: const BoxConstraints(
                                        minWidth: 96,
                                      ),
                                      suffixIcon: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (!searchQuery.isEmpty)
                                            IconButton(
                                              onPressed: () {
                                                _searchController.clear();
                                                setState(() {
                                                  searchQuery = '';
                                                });
                                              },
                                              icon: const Icon(
                                                Icons.close_rounded,
                                                color: Color(0xFF2563EB),
                                              ),
                                            ),
                                          const Padding(
                                            padding: EdgeInsets.only(right: 12),
                                            child: SizedBox(
                                              width: 36,
                                              height: 36,
                                              child: DecoratedBox(
                                                decoration: BoxDecoration(
                                                  color: Color(0xFFF3F7FF),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  Icons.mic_rounded,
                                                  size: 22,
                                                  color: Color(0xFF1D4ED8),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      filled: true,
                                      fillColor: Colors.white,
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 14,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(30),
                                        borderSide: const BorderSide(
                                          color: Color(0xFFE5E7EB),
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(30),
                                        borderSide: const BorderSide(
                                          color: Color(0xFFE5E7EB),
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(30),
                                        borderSide: const BorderSide(
                                          color: Color(0xFFE5E7EB),
                                          width: 1.2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _homeGiftPromoBanner(context),
                      ),
                      const SizedBox(height: 22),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Categories',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              const crossAxisCount = 4;

                              return GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: homeMainCategories.length,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: crossAxisCount,
                                      mainAxisSpacing: 4,
                                      crossAxisSpacing: 12,
                                      childAspectRatio: 1.0,
                                    ),
                                itemBuilder: (context, index) {
                                  final category = homeMainCategories[index];
                                  return TweenAnimationBuilder<double>(
                                    tween: Tween<double>(begin: 0.92, end: 1),
                                    duration: Duration(
                                      milliseconds: 300 + (index * 40),
                                    ),
                                    curve: Curves.easeOutCubic,
                                    builder: (context, value, child) {
                                      return Transform.scale(
                                        scale: value,
                                        child: Opacity(
                                          opacity: value.clamp(0, 1),
                                          child: child,
                                        ),
                                      );
                                    },
                                    child: InkWell(
                                      onTap: () {
                                        _openCategoryPage(category);
                                      },
                                      borderRadius: BorderRadius.circular(16),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          Container(
                                            width: 72,
                                            height: 72,
                                            decoration: const BoxDecoration(
                                              color: Color(0xFFF3F4F6),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Center(
                                              child: Image.asset(
                                                switch (category.title) {
                                                  'Grocery' =>
                                                    'assets/banners/grocery.png',
                                                  'Food' =>
                                                    'assets/banners/food.png',
                                                  'Gifts' =>
                                                    'assets/banners/gifts.png',
                                                  'Gifts & Surprises' =>
                                                    'assets/banners/gifts_surprises.png',
                                                  'Cosmetics' =>
                                                    'assets/banners/cosmetics.png',
                                                  'Electronics' =>
                                                    'assets/banners/electronics.png',
                                                  'Home Service' =>
                                                    'assets/banners/home_service.png',
                                                  'Parcel Delivery' =>
                                                    'assets/banners/parcel_delivery.png',
                                                  _ => 'assets/banners/grocery.png',
                                                },
                                                width: 60,
                                                height: 60,
                                                fit: BoxFit.contain,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            category.title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF1F2937),
                                              height: 1.2,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                        if (!canUseFirestore)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(
                              children: [
                                _buildProductSection(
                                  title: 'Popular Products',
                                  subtitle: 'Trending choices from live inventory',
                                  items: const [],
                                ),
                                const SizedBox(height: 24),
                                _buildProductSection(
                                  title: 'Best Sellers',
                                  subtitle: 'Top performing products customers love',
                                  items: const [],
                                ),
                              ],
                            ),
                          )
                        else if (snapshot.connectionState == ConnectionState.waiting)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (snapshot.hasError)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Unable to load products right now.',
                              style: TextStyle(
                                color: Colors.black54,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            children: [
                              _buildProductSection(
                                title: 'Popular Products',
                                subtitle: 'Trending choices from live inventory',
                                items: popularItems,
                              ),
                              const SizedBox(height: 24),
                              _buildProductSection(
                                title: 'Best Sellers',
                                subtitle: 'Top performing products customers love',
                                items: bestSellerItems.take(5).toList(),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 24),
                    ],
                  ),
                );
              },
            ),
          ),
          bottomNavigationBar: Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.shade100,
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                _bottomNavItem(
                  icon: Icons.home_rounded,
                  label: 'Home',
                  selected: true,
                  onTap: () => _onBottomNavTap(0),
                ),
                _bottomNavItem(
                  icon: Icons.grid_view_rounded,
                  label: 'Categories',
                  selected: false,
                  onTap: () => _onBottomNavTap(1),
                ),
                _bottomNavItem(
                  icon: Icons.receipt_long_rounded,
                  label: 'Orders',
                  selected: false,
                  onTap: () => _onBottomNavTap(2),
                ),
                _bottomNavItem(
                  icon: Icons.shopping_cart_rounded,
                  label: 'Cart',
                  selected: false,
                  badge: totalItems > 0 ? totalItems.toString() : null,
                  onTap: () => _onBottomNavTap(3),
                ),
                _bottomNavItem(
                  icon: Icons.person_rounded,
                  label: 'Profile',
                  selected: false,
                  onTap: () => _onBottomNavTap(4),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _bottomNavItem({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    String? badge,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: selected ? Colors.blue.shade50 : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      icon,
                      color: selected
                          ? Colors.blue.shade700
                          : Colors.grey.shade600,
                      size: 23,
                    ),
                    if (badge != null)
                      Positioned(
                        right: -8,
                        top: -7,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade500,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            badge,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected ? Colors.blue.shade700 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeProductItem {
  final GroceryItem product;
  final double? oldPrice;
  final int discountPercent;
  final int bestSellerScore;
  final Map<String, dynamic> raw;

  const _HomeProductItem({
    required this.product,
    required this.oldPrice,
    required this.discountPercent,
    required this.bestSellerScore,
    required this.raw,
  });
}

class _PinnedCategoryHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _PinnedCategoryHeaderDelegate({
    required this.child,
    required this.minHeight,
    required this.maxHeight,
  });

  final Widget child;
  final double minHeight;
  final double maxHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox.expand(child: child);
  }

  @override
  double get minExtent => minHeight;

  @override
  double get maxExtent => maxHeight;

  @override
  bool shouldRebuild(covariant _PinnedCategoryHeaderDelegate oldDelegate) {
    return child != oldDelegate.child ||
        minHeight != oldDelegate.minHeight ||
        maxHeight != oldDelegate.maxHeight;
  }
}

class CategoryProductsPage extends StatefulWidget {
  final ValueNotifier<List<CartItem>> cartNotifier;
  final String title;
  final String firestoreCategory;
  final Color accent;
  final List<String> subcategories;
  final String? selectedSubcategory;

  const CategoryProductsPage({
    super.key,
    required this.cartNotifier,
    required this.title,
    required this.firestoreCategory,
    required this.accent,
    required this.subcategories,
    this.selectedSubcategory,
  });

  @override
  State<CategoryProductsPage> createState() => _CategoryProductsPageState();
}

class _CategoryProductsPageState extends State<CategoryProductsPage> {
  String? _selectedSubcategory;
  String? _selectedChildCategory;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _selectedSubcategory = widget.selectedSubcategory;
    _scrollController = ScrollController();
  }

  @override
  void didUpdateWidget(covariant CategoryProductsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedSubcategory != widget.selectedSubcategory) {
      _selectedSubcategory = widget.selectedSubcategory;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  String _priceText(dynamic value) {
    if (value is num) {
      if (value % 1 == 0) {
        return '₹${value.toInt()}';
      }
      return '₹${value.toStringAsFixed(2)}';
    }

    final parsed = double.tryParse(value?.toString() ?? '');
    if (parsed != null) {
      if (parsed % 1 == 0) {
        return '₹${parsed.toInt()}';
      }
      return '₹${parsed.toStringAsFixed(2)}';
    }

    return value?.toString() ?? '₹0';
  }

  Color _categoryAccent(String category) {
    final normalized = category.toLowerCase();
    if (normalized.contains('food')) return Colors.orange.shade700;
    if (normalized.contains('grocery')) return Colors.blue.shade700;
    if (normalized.contains('gift')) return Colors.pink.shade700;
    if (normalized.contains('electronic')) return Colors.indigo.shade700;
    if (normalized.contains('beauty')) return Colors.purple.shade700;
    if (normalized.contains('household')) return Colors.teal.shade700;
    if (normalized.contains('pet')) return Colors.brown.shade700;
    if (normalized.contains('party')) return Colors.amber.shade800;
    if (normalized.contains('print')) return Colors.cyan.shade700;
    return Colors.blue.shade700;
  }

  GroceryItem _productFromDoc(Map<String, dynamic> data, {String? productId}) {
    final name = data['name']?.toString() ?? 'Product';
    final category = data['category']?.toString() ?? 'General';
    final stock = (data['stock'] as num?)?.toInt() ?? 999;
    final imageUrl = _extractProductImageUrl(data);

    return GroceryItem(
      productId: productId,
      name: name,
      price: _priceText(data['price']),
      unit: '1 item',
      emoji: '🛍️',
      tag: category,
      accent: _categoryAccent(category),
      stock: stock,
      imageUrl: imageUrl,
    );
  }

  bool _matchesCategory(
    Map<String, dynamic> data, {
    required List<String> availableSubcategories,
  }) {
    return matchesCategoryAndSubcategory(
      data,
      firestoreCategory: widget.firestoreCategory,
      selectedSubcategory: _selectedSubcategory,
      selectedChildCategory: _selectedChildCategory,
      availableSubcategories: availableSubcategories,
    );
  }

  void _openSubcategory(String? subcategory) {
    if (subcategory == null || subcategory.isEmpty) {
      if (_selectedSubcategory == null) {
        return;
      }
      setState(() {
        _selectedSubcategory = null;
        _selectedChildCategory = null;
      });
      _scrollToTop();
      return;
    }

    if (subcategory == _selectedSubcategory) {
      setState(() {
        _selectedSubcategory = null;
        _selectedChildCategory = null;
      });
      _scrollToTop();
      return;
    }

    setState(() {
      _selectedSubcategory = subcategory;
      _selectedChildCategory = null;
    });
    _scrollToTop();
  }

  void _openChildCategory(String? childCategory) {
    if (childCategory == null || childCategory.isEmpty) {
      if (_selectedChildCategory == null) {
        return;
      }
      setState(() {
        _selectedChildCategory = null;
      });
      _scrollToTop();
      return;
    }

    if (childCategory == _selectedChildCategory) {
      setState(() {
        _selectedChildCategory = null;
      });
      _scrollToTop();
      return;
    }

    setState(() {
      _selectedChildCategory = childCategory;
    });
    _scrollToTop();
  }

  void _addToCart(GroceryItem item) {
    cartLog(
      'Category addToCart invoked for ${item.name} (id=${item.productId}, stock=${item.stock})',
    );
    try {
      if (item.stock <= 0) {
        cartLog(
          'Category addToCart blocked due to stock <= 0 for ${item.name}',
        );
        appScaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('This product is out of stock')),
        );
        return;
      }

      final currentCart = List<CartItem>.from(widget.cartNotifier.value);
      cartLog('Category cart size before add: ${currentCart.length}');

      final existingIndex = currentCart.indexWhere(
        (entry) =>
            (entry.product.productId != null &&
                item.productId != null &&
                entry.product.productId == item.productId) ||
            entry.product.name == item.name,
      );
      cartLog('Category existing index: $existingIndex');

      if (existingIndex >= 0) {
        currentCart[existingIndex].quantity += 1;
        cartLog(
          'Category incremented quantity to ${currentCart[existingIndex].quantity} for ${item.name}',
        );
      } else {
        currentCart.add(CartItem(product: item, quantity: 1));
        cartLog('Category appended new cart item for ${item.name}');
      }

      widget.cartNotifier.value = currentCart;
      cartLog('Category cart size after add: ${widget.cartNotifier.value.length}');

      appScaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('${item.name} added to cart')),
      );
    } catch (error, stackTrace) {
      final location = cartErrorLocation(stackTrace);
      cartLog(
        'Category addToCart exception for ${item.name} at $location',
        error: error,
        stackTrace: stackTrace,
      );

      final snackBar = SnackBar(
        duration: const Duration(seconds: 7),
        content: Text('Add to Cart failed: $error\n$location'),
      );
      appScaffoldMessengerKey.currentState?.showSnackBar(snackBar);
    }
  }

  Widget _buildProductCard(BuildContext context, GroceryItem item) {
    final isGroceryPage = widget.firestoreCategory == 'Grocery';
    final outOfStock = item.stock <= 0;
    final resolvedImageUrl = item.imageUrl;

    return Container(
      padding: EdgeInsets.all(isGroceryPage ? 10 : 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade100,
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: Colors.blue.shade50),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: item.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  item.tag,
                  style: TextStyle(
                    color: item.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(Icons.shopping_bag_outlined, color: Colors.blue.shade600),
            ],
          ),
          SizedBox(height: isGroceryPage ? 8 : 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: resolvedImageUrl.isNotEmpty
                ? Image.network(
                    resolvedImageUrl,
                    height: isGroceryPage ? 100 : 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      print('Image.network failed for $resolvedImageUrl: $error');
                      return Container(
                        height: isGroceryPage ? 100 : 180,
                        width: double.infinity,
                        color: Colors.blue.shade50,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.shopping_bag_outlined,
                          color: Colors.blue.shade400,
                          size: 30,
                        ),
                      );
                    },
                  )
                : Container(
                  height: isGroceryPage ? 100 : 180,
                    width: double.infinity,
                    color: Colors.blue.shade50,
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.shopping_bag_outlined,
                      color: Colors.blue.shade400,
                      size: 30,
                    ),
                  ),
          ),
          SizedBox(height: isGroceryPage ? 8 : 10),
          Text(
            item.name,
            maxLines: isGroceryPage ? 2 : null,
            overflow: isGroceryPage ? TextOverflow.ellipsis : null,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: isGroceryPage ? 3 : 4),
          Text(
            item.price,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          SizedBox(height: isGroceryPage ? 3 : 4),
          Text(
            outOfStock ? 'Out of Stock' : 'Stock: ${item.stock}',
            style: TextStyle(
              color: outOfStock ? Colors.red.shade700 : Colors.grey,
              fontSize: 12,
              fontWeight: outOfStock ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          const Spacer(),
          SizedBox(
            height: isGroceryPage ? 30 : null,
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: outOfStock
                  ? null
                  : () {
                      _addToCart(item);
                    },
              icon: const Icon(Icons.add_shopping_cart, size: 16),
              label: Text(outOfStock ? 'Out of Stock' : 'Add to Cart'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final childCategories = buildChildCategoryOptions(_selectedSubcategory);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final crossAxisCount = screenWidth > 700 ? 3 : 2;
    final isGroceryPage = widget.firestoreCategory == 'Grocery';
    final headerHeight = childCategories.isNotEmpty ? 156.0 : 92.0;

    return Scaffold(
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('products').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            final error = snapshot.error;
            if (error is FirebaseException) {
              developer.log(
                'Products stream failed: ${error.message ?? error.toString()}',
                name: 'QuickDrop',
                error: error,
              );
            } else {
              developer.log(
                'Products stream failed: $error',
                name: 'QuickDrop',
                error: error,
              );
            }

            return const Center(
              child: Text(
                'Unable to load products for this category.',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];
          final availableSubcategories = buildSubcategoriesForCategory(
            docs.map((doc) => doc.data()),
            firestoreCategory: widget.firestoreCategory,
          );
          final filteredDocs = docs.where((doc) {
            return _matchesCategory(
              doc.data(),
              availableSubcategories: availableSubcategories,
            );
          }).toList();

          final tabContent = Container(
            width: double.infinity,
            color: Colors.blue.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (availableSubcategories.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        InkWell(
                          onTap: () => _openSubcategory(null),
                          borderRadius: BorderRadius.circular(999),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _selectedSubcategory == null
                                  ? Colors.blue.shade700
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: Colors.blue.shade100),
                            ),
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              style: TextStyle(
                                color: _selectedSubcategory == null
                                    ? Colors.white
                                    : Colors.blue.shade800,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              child: const Text('All'),
                            ),
                          ),
                        ),
                        ...availableSubcategories.map(
                          (name) => InkWell(
                            onTap: () => _openSubcategory(name),
                            borderRadius: BorderRadius.circular(999),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _selectedSubcategory == name
                                    ? Colors.blue.shade700
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: Colors.blue.shade100),
                              ),
                              child: AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                style: TextStyle(
                                  color: _selectedSubcategory == name
                                      ? Colors.white
                                      : Colors.blue.shade800,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                child: Text(name),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (childCategories.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Child Category',
                          style: TextStyle(
                            color: Colors.blue.shade800,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            InkWell(
                              onTap: () => _openChildCategory(null),
                              borderRadius: BorderRadius.circular(999),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: _selectedChildCategory == null
                                      ? Colors.blue.shade700
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: Colors.blue.shade100),
                                ),
                                child: AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOutCubic,
                                  style: TextStyle(
                                    color: _selectedChildCategory == null
                                        ? Colors.white
                                        : Colors.blue.shade800,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  child: const Text('All'),
                                ),
                              ),
                            ),
                            ...childCategories.map(
                              (name) => InkWell(
                                onTap: () => _openChildCategory(name),
                                borderRadius: BorderRadius.circular(999),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOutCubic,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _selectedChildCategory == name
                                        ? Colors.blue.shade700
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: Colors.blue.shade100),
                                  ),
                                  child: AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 220),
                                    curve: Curves.easeOutCubic,
                                    style: TextStyle(
                                      color: _selectedChildCategory == name
                                          ? Colors.white
                                          : Colors.blue.shade800,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    child: Text(name),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );

          return CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverAppBar(
                pinned: true,
                title: Text(widget.title),
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
                automaticallyImplyLeading: true,
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _PinnedCategoryHeaderDelegate(
                  child: tabContent,
                  minHeight: availableSubcategories.isEmpty && childCategories.isEmpty
                      ? 0
                      : headerHeight,
                  maxHeight: availableSubcategories.isEmpty && childCategories.isEmpty
                      ? 0
                      : headerHeight,
                ),
              ),
              if (filteredDocs.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                    child: Text(
                      'No products available in ${widget.title}${_selectedSubcategory == null ? '' : ' / $_selectedSubcategory'}${_selectedChildCategory == null ? '' : ' / $_selectedChildCategory'} right now.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    isGroceryPage ? 24 : 16,
                    16,
                    isGroceryPage ? 24 : 16,
                    16,
                  ),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: 3.2,
                      crossAxisSpacing: 12,
                      mainAxisExtent:
                          widget.firestoreCategory == 'Grocery' ? 306 : 108,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final doc = filteredDocs[index];
                        final item = _productFromDoc(
                          doc.data(),
                          productId: doc.id,
                        );
                        return _buildProductCard(context, item);
                      },
                      childCount: filteredDocs.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class GroceryPage extends StatelessWidget {
  final ValueNotifier<List<CartItem>> cartNotifier;

  const GroceryPage({super.key, required this.cartNotifier});

  @override
  Widget build(BuildContext context) {
    return CategoryProductsPage(
      cartNotifier: cartNotifier,
      title: 'Grocery',
      firestoreCategory: 'Grocery',
      accent: Colors.blue.shade700,
      subcategories: grocerySubcategories,
    );
  }
}

class FoodPage extends StatelessWidget {
  final ValueNotifier<List<CartItem>> cartNotifier;

  const FoodPage({super.key, required this.cartNotifier});

  @override
  Widget build(BuildContext context) {
    return CategoryProductsPage(
      cartNotifier: cartNotifier,
      title: 'Food',
      firestoreCategory: 'Food',
      accent: Colors.orange.shade700,
      subcategories: foodSubcategories,
    );
  }
}

class GiftsPage extends StatelessWidget {
  final ValueNotifier<List<CartItem>> cartNotifier;

  const GiftsPage({super.key, required this.cartNotifier});

  @override
  Widget build(BuildContext context) {
    return CategoryProductsPage(
      cartNotifier: cartNotifier,
      title: 'Gifts',
      firestoreCategory: 'Gifts',
      accent: Colors.pink.shade700,
      subcategories: giftSubcategories,
    );
  }
}

class CosmeticsPage extends StatelessWidget {
  final ValueNotifier<List<CartItem>> cartNotifier;

  const CosmeticsPage({super.key, required this.cartNotifier});

  @override
  Widget build(BuildContext context) {
    return CategoryProductsPage(
      cartNotifier: cartNotifier,
      title: 'Cosmetics',
      firestoreCategory: 'Cosmetics',
      accent: Colors.purple.shade700,
      subcategories: const ['Bath & Body', 'Hair Care', 'Beauty Products'],
    );
  }
}

class ElectronicsPage extends StatelessWidget {
  final ValueNotifier<List<CartItem>> cartNotifier;

  const ElectronicsPage({super.key, required this.cartNotifier});

  @override
  Widget build(BuildContext context) {
    return CategoryProductsPage(
      cartNotifier: cartNotifier,
      title: 'Electronics',
      firestoreCategory: 'Electronics',
      accent: Colors.indigo.shade700,
      subcategories: const [
        'Chargers',
        'Earphones',
        'Power Banks',
        'Mobile Accessories',
      ],
    );
  }
}

class ParcelPage extends StatelessWidget {
  final ValueNotifier<List<CartItem>> cartNotifier;

  const ParcelPage({super.key, required this.cartNotifier});

  @override
  Widget build(BuildContext context) {
    return CategoryProductsPage(
      cartNotifier: cartNotifier,
      title: 'Local Parcel',
      firestoreCategory: 'Local Parcel',
      accent: Colors.teal.shade700,
      subcategories: const ['Documents', 'Fragile Items', 'Gift Delivery'],
    );
  }
}

const List<String> giftSections = [
  'Gift Boxes',
  'Teddy Bears',
  'Chocolates',
  'Flowers',
  'Cakes',
  'Gift Combos',
  'Custom Photo Frame',
];

class GiftCategoryPage extends StatefulWidget {
  final ValueNotifier<List<CartItem>> cartNotifier;

  const GiftCategoryPage({super.key, required this.cartNotifier});

  @override
  State<GiftCategoryPage> createState() => _GiftCategoryPageState();
}

class _GiftCategoryPageState extends State<GiftCategoryPage> {
  final TextEditingController _customMessageController =
      TextEditingController();
  final TextEditingController _photoUrlController = TextEditingController();

  String _selectedFrameSize = 'Medium';
  String _selectedSection = 'Gift Combos';
  String _uploadedPhotoUrl = '';

  bool _giftWrapping = false;
  bool _greetingCard = false;
  bool _handwrittenMessage = false;
  bool _secretSurpriseDelivery = false;

  String _priceText(dynamic value) {
    if (value is num) {
      if (value % 1 == 0) {
        return '₹${value.toInt()}';
      }
      return '₹${value.toStringAsFixed(2)}';
    }

    final parsed = double.tryParse(value?.toString() ?? '');
    if (parsed != null) {
      if (parsed % 1 == 0) {
        return '₹${parsed.toInt()}';
      }
      return '₹${parsed.toStringAsFixed(2)}';
    }

    return value?.toString() ?? '₹0';
  }

  Set<String> _giftCategoryAliases() {
    return {'gift', 'gifts'};
  }

  Set<String> _sectionAliases(String section) {
    switch (section.toLowerCase()) {
      case 'gift boxes':
        return {'gift boxes', 'gift box'};
      case 'teddy bears':
        return {'teddy bears', 'teddy bear', 'soft toys', 'soft toy'};
      case 'chocolates':
        return {'chocolates', 'chocolate'};
      case 'flowers':
        return {'flowers', 'flower'};
      case 'cakes':
        return {'cakes', 'cake'};
      case 'gift combos':
        return {'gift combos', 'gift combo', 'combos', 'combo'};
      case 'custom photo frame':
        return {'custom photo frame', 'photo frame'};
      default:
        return {section.toLowerCase()};
    }
  }

  bool _matchesSelectedSection(Map<String, dynamic> data) {
    final category = (data['category']?.toString() ?? '').trim().toLowerCase();
    if (!_giftCategoryAliases().contains(category)) {
      return false;
    }

    final subcategory = (data['subcategory']?.toString() ?? '')
        .trim()
        .toLowerCase();
    final aliases = _sectionAliases(_selectedSection);

    if (aliases.contains(subcategory)) {
      return true;
    }

    final name = (data['name']?.toString() ?? '').toLowerCase();
    return aliases.any((alias) => name.contains(alias));
  }

  GroceryItem _productFromDoc(Map<String, dynamic> data, {String? productId}) {
    final name = data['name']?.toString() ?? 'Gift Product';
    final category = data['category']?.toString() ?? 'Gifts';
    final stock = (data['stock'] as num?)?.toInt() ?? 999;

    final imageUrl = _extractProductImageUrl(data);

    return GroceryItem(
      productId: productId,
      name: name,
      price: _priceText(data['price']),
      unit: data['unit']?.toString() ?? '1 item',
      emoji: '🎁',
      tag: category,
      accent: Colors.pink.shade700,
      stock: stock,
      imageUrl: imageUrl,
    );
  }

  void _addToCart(GroceryItem item) {
    try {
      if (item.stock <= 0) {
        appScaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('This product is out of stock')),
        );
        return;
      }

      final currentCart = List<CartItem>.from(widget.cartNotifier.value);

      final existingIndex = currentCart.indexWhere(
        (entry) =>
            (entry.product.productId != null &&
                item.productId != null &&
                entry.product.productId == item.productId) ||
            entry.product.name == item.name,
      );

      if (existingIndex >= 0) {
        currentCart[existingIndex].quantity += 1;
      } else {
        currentCart.add(CartItem(product: item, quantity: 1));
      }

      widget.cartNotifier.value = currentCart;

      appScaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('${item.name} added to cart')),
      );
    } catch (error, stackTrace) {
      showCartExceptionSnackbar(context, error, stackTrace);
    }
  }

  List<GroceryItem> _selectedAddonItems() {
    final items = <GroceryItem>[];

    if (_giftWrapping) {
      items.add(
        GroceryItem(
          name: 'Gift Wrapping',
          price: '₹49',
          unit: '1 service',
          emoji: '🎀',
          tag: 'Gift Add-on',
          accent: Colors.blue.shade700,
        ),
      );
    }

    if (_greetingCard) {
      items.add(
        GroceryItem(
          name: 'Greeting Card',
          price: '₹29',
          unit: '1 card',
          emoji: '💌',
          tag: 'Gift Add-on',
          accent: Colors.blue.shade700,
        ),
      );
    }

    if (_handwrittenMessage) {
      final customText = _customMessageController.text.trim();
      items.add(
        GroceryItem(
          name: customText.isEmpty
              ? 'Handwritten Message'
              : 'Handwritten Message: $customText',
          price: '₹19',
          unit: '1 message',
          emoji: '✍️',
          tag: 'Gift Add-on',
          accent: Colors.blue.shade700,
        ),
      );
    }

    if (_secretSurpriseDelivery) {
      items.add(
        GroceryItem(
          name: 'Secret Surprise Delivery',
          price: '₹79',
          unit: '1 service',
          emoji: '🤫',
          tag: 'Gift Add-on',
          accent: Colors.blue.shade700,
        ),
      );
    }

    return items;
  }

  void _addProductWithAddons(GroceryItem item) {
    _addToCart(item);
    for (final addon in _selectedAddonItems()) {
      _addToCart(addon);
    }
  }

  Future<void> _openUploadDialog() async {
    _photoUrlController.text = _uploadedPhotoUrl;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Upload Photo'),
          content: TextField(
            controller: _photoUrlController,
            decoration: const InputDecoration(
              hintText: 'Paste image URL (Firebase Storage ready)',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _uploadedPhotoUrl = _photoUrlController.text.trim();
                });
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Photo attached successfully')),
                );
              },
              child: const Text('Attach'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _addCustomFrameToCart() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('products')
          .where('category', whereIn: const ['Gift', 'Gifts', 'gift', 'gifts'])
          .get();

      final matchingDocs = snapshot.docs.where((doc) {
        final name = (doc.data()['name']?.toString() ?? '').toLowerCase();
        return name.contains('custom photo frame');
      }).toList();

      if (matchingDocs.isEmpty) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No products available')));
        return;
      }

      final data = matchingDocs.first.data();
      final customFrameProduct = _productFromDoc(
        data,
        productId: matchingDocs.first.id,
      );
      final customFrameWithSelectedSize = GroceryItem(
        productId: customFrameProduct.productId,
        name: customFrameProduct.name,
        price: customFrameProduct.price,
        unit: _selectedFrameSize,
        emoji: '🖼️',
        tag: customFrameProduct.tag,
        accent: customFrameProduct.accent,
        stock: customFrameProduct.stock,
        imageUrl: _uploadedPhotoUrl.isNotEmpty
            ? _uploadedPhotoUrl
            : customFrameProduct.imageUrl,
      );

      _addProductWithAddons(customFrameWithSelectedSize);
    } on FirebaseException catch (error) {
      developer.log(
        'Custom frame product lookup failed: ${error.message ?? error.toString()}',
        name: 'QuickDrop',
        error: error,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text('Unable to load product: ${error.message ?? error}'),
        ),
      );
    } catch (error, stackTrace) {
      developer.log(
        'Custom frame product lookup failed: $error',
        name: 'QuickDrop',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to load product: $error')));
    }
  }

  @override
  void dispose() {
    _customMessageController.dispose();
    _photoUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gifts & Surprises'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: const Text(
                'Surprise your loved ones',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2A44),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Gift Categories',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: giftSections
                  .map(
                    (section) => ChoiceChip(
                      label: Text(section),
                      selected: _selectedSection == section,
                      selectedColor: Colors.blue.shade100,
                      onSelected: (_) {
                        setState(() {
                          _selectedSection = section;
                        });
                      },
                      labelStyle: TextStyle(
                        color: Colors.blue.shade800,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 20),
            const Text(
              'Gift Products',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('products')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                final items = docs
                    .where((doc) => _matchesSelectedSection(doc.data()))
                    .map(
                      (doc) => _productFromDoc(doc.data(), productId: doc.id),
                    )
                    .toList();

                if (items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No products available',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.52,
                  ),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final outOfStock = item.stock <= 0;

                    final resolvedImageUrl = item.imageUrl;

                    return InkWell(
                      onTap: outOfStock
                          ? null
                          : () => _addProductWithAddons(item),
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: item.accent.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    item.tag,
                                    style: TextStyle(
                                      color: item.accent,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.shopping_bag_outlined,
                                  color: Colors.blue.shade600,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: resolvedImageUrl.isNotEmpty
                                  ? Image.network(
                                      resolvedImageUrl,
                                      height: 180,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) {
                                        print(
                                          'Grid image.network failed for $resolvedImageUrl: $error',
                                        );
                                        return Container(
                                          height: 180,
                                          width: double.infinity,
                                          color: Colors.blue.shade50,
                                          alignment: Alignment.center,
                                          child: Icon(
                                            Icons.shopping_bag_outlined,
                                            color: Colors.blue.shade400,
                                            size: 30,
                                          ),
                                        );
                                      },
                                    )
                                  : Container(
                                      height: 180,
                                      width: double.infinity,
                                      color: Colors.blue.shade50,
                                      alignment: Alignment.center,
                                      child: Icon(
                                        Icons.shopping_bag_outlined,
                                        color: Colors.blue.shade400,
                                        size: 30,
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              item.name,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.price,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              outOfStock
                                  ? 'Out of Stock'
                                  : 'Stock: ${item.stock}',
                              style: TextStyle(
                                color: outOfStock
                                    ? Colors.red.shade700
                                    : Colors.grey,
                                fontSize: 12,
                                fontWeight: outOfStock
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                            const Spacer(),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: outOfStock
                                    ? null
                                    : () => _addProductWithAddons(item),
                                icon: const Icon(
                                  Icons.add_shopping_cart,
                                  size: 16,
                                ),
                                label: Text(
                                  outOfStock ? 'Out of Stock' : 'Add to Cart',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue.shade700,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 10),
            const Text(
              'Gift Add-ons',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Gift Wrapping'),
              value: _giftWrapping,
              activeThumbColor: Colors.blue.shade700,
              onChanged: (value) => setState(() => _giftWrapping = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Greeting Card'),
              value: _greetingCard,
              activeThumbColor: Colors.blue.shade700,
              onChanged: (value) => setState(() => _greetingCard = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Handwritten Message'),
              value: _handwrittenMessage,
              activeThumbColor: Colors.blue.shade700,
              onChanged: (value) => setState(() => _handwrittenMessage = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Secret Surprise Delivery'),
              value: _secretSurpriseDelivery,
              activeThumbColor: Colors.blue.shade700,
              onChanged: (value) =>
                  setState(() => _secretSurpriseDelivery = value),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Custom Photo Frame',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _openUploadDialog,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Upload Photo'),
                    ),
                  ),
                  if (_uploadedPhotoUrl.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Attached photo URL: $_uploadedPhotoUrl',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Text(
                    'Frame Size Selection',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: ['Small', 'Medium', 'Large']
                        .map(
                          (size) => ChoiceChip(
                            label: Text(size),
                            selected: _selectedFrameSize == size,
                            selectedColor: Colors.blue.shade100,
                            onSelected: (_) {
                              setState(() {
                                _selectedFrameSize = size;
                              });
                            },
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _customMessageController,
                    decoration: InputDecoration(
                      labelText: 'Custom Message',
                      hintText: 'Write your message',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _addCustomFrameToCart,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Add To Cart'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class CartPage extends StatelessWidget {
  final ValueNotifier<List<CartItem>> cartNotifier;

  const CartPage({super.key, required this.cartNotifier});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Cart'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: ValueListenableBuilder<List<CartItem>>(
        valueListenable: cartNotifier,
        builder: (context, items, _) {
          if (items.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.shopping_cart_outlined,
                    size: 72,
                    color: Colors.blue,
                  ),
                  SizedBox(height: 14),
                  Text(
                    'Your cart is empty',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Add a few essentials to get started.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          final subtotal = items.fold<int>(0, (totalPrice, item) {
            return totalPrice +
                (parsePrice(item.product.price) * item.quantity);
          });

          return Column(
            children: [
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final entry = items[index];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: entry.product.accent.withValues(
                              alpha: 0.15,
                            ),
                            child: Text(
                              entry.product.emoji,
                              style: const TextStyle(fontSize: 22),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.product.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${entry.product.price} • ${entry.product.unit}',
                                  style: const TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              IconButton(
                                onPressed: () {
                                  final updated = List<CartItem>.from(items);
                                  if (updated[index].quantity > 1) {
                                    updated[index].quantity -= 1;
                                  } else {
                                    updated.removeAt(index);
                                  }
                                  cartNotifier.value = updated;
                                },
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                              Text(
                                '${entry.quantity}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  final updated = List<CartItem>.from(items);
                                  updated[index].quantity += 1;
                                  cartNotifier.value = updated;
                                },
                                icon: const Icon(Icons.add_circle_outline),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFEAF2FF))),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Subtotal', style: TextStyle(fontSize: 16)),
                        Text(
                          '₹$subtotal',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CheckoutPage(
                                cartNotifier: cartNotifier,
                                subtotal: subtotal,
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Checkout'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class CheckoutPage extends StatefulWidget {
  final ValueNotifier<List<CartItem>> cartNotifier;
  final int subtotal;

  const CheckoutPage({
    super.key,
    required this.cartNotifier,
    required this.subtotal,
  });

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  static const String _paymentMethodCod = 'Cash on Delivery';
  static const String _paymentMethodOnline = 'ONLINE';
  static const String _savedPaymentMethodOnline = 'Online Payment';
  static const String _savedPaymentStatusPending = 'Pending';
  static const String _savedPaymentStatusPaid = 'Paid';
  static const String _razorpayTestKey = String.fromEnvironment(
    'RAZORPAY_TEST_KEY',
    defaultValue: 'rzp_test_TGFIu9vw9kGBIx',
  );

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final AuthService _authService = AuthService();
  String _paymentMethod = _paymentMethodCod;
  bool _isPlacingOrder = false;
  String? _sessionPhone;
  late final Razorpay _razorpay;
  int? _pendingOnlineTotal;
  LatLng? _selectedDeliveryLocation;
  String? _selectedDeliveryAddress;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
    _prefillCheckoutFromSession();
  }

  Future<void> _prefillCheckoutFromSession() async {
    final profile = await _authService.loadCurrentUserProfile();
    if (!mounted || profile == null) {
      return;
    }

    final sessionName = (profile['name'] as String?)?.trim() ?? '';
    final sessionPhone = (profile['phoneNumber'] as String?)?.trim() ?? '';
    final sessionAddress = (profile['address'] as String?)?.trim() ?? '';

    setState(() {
      _sessionPhone = sessionPhone.isEmpty ? null : sessionPhone;
      if (_nameController.text.trim().isEmpty && sessionName.isNotEmpty) {
        _nameController.text = sessionName;
      }
      if (_phoneController.text.trim().isEmpty && sessionPhone.isNotEmpty) {
        _phoneController.text = sessionPhone;
      }
      if (_addressController.text.trim().isEmpty && sessionAddress.isNotEmpty) {
        _addressController.text = sessionAddress;
      }
    });
  }

  int _deliveryCharge() {
    if (widget.subtotal < 200) return 30;
    if (widget.subtotal < 500) return 20;
    return 0;
  }

  Future<void> _reduceStockAfterOrder(List<CartItem> items) async {
    final productQuantities = <String, int>{};
    for (final item in items) {
      final productId = item.product.productId;
      if (productId == null || productId.isEmpty) {
        continue;
      }
      productQuantities[productId] =
          (productQuantities[productId] ?? 0) + item.quantity;
    }

    if (productQuantities.isEmpty) {
      return;
    }

    final productsRef = FirebaseFirestore.instance.collection('products');
    final batch = FirebaseFirestore.instance.batch();

    for (final entry in productQuantities.entries) {
      final docRef = productsRef.doc(entry.key);
      final snapshot = await docRef.get();
      if (!snapshot.exists) {
        continue;
      }

      final currentStock = (snapshot.data()?['stock'] as num?)?.toInt() ?? 0;
      final updatedStock = (currentStock - entry.value).clamp(0, 9999999);
      batch.update(docRef, {'stock': updatedStock});
    }

    await batch.commit();
  }

  Future<void> _selectDeliveryLocation() async {
    final pickedLocation = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) =>
            LocationPickerScreen(initialPosition: _selectedDeliveryLocation),
      ),
    );

    if (!mounted || pickedLocation == null) {
      return;
    }

    final resolvedAddress = await _resolveAddressFromCoordinates(
      pickedLocation,
    );

    setState(() {
      _selectedDeliveryLocation = pickedLocation;
      _selectedDeliveryAddress = resolvedAddress;
      if (resolvedAddress != null && resolvedAddress.isNotEmpty) {
        _addressController.text = resolvedAddress;
      }
    });
  }

  Future<String?> _resolveAddressFromCoordinates(LatLng location) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );

      if (placemarks.isEmpty) {
        return null;
      }

      final place = placemarks.first;
      final parts =
          <String?>[
                place.name,
                place.street,
                place.subLocality,
                place.locality,
                place.administrativeArea,
                place.postalCode,
                place.country,
              ]
              .where((part) => part != null && part.trim().isNotEmpty)
              .map((part) => part!.trim())
              .toList();

      if (parts.isEmpty) {
        return null;
      }

      return parts.join(', ');
    } catch (_) {
      return null;
    }
  }

  Future<Order> _buildOrderForCheckout(
    int total, {
    required String paymentMethod,
    required String paymentStatus,
    String? paymentId,
  }) async {
    final items = List<CartItem>.from(widget.cartNotifier.value);

    final ownerPhone =
        (await _authService.getCurrentUserPhone()) ??
        _sessionPhone ??
        _phoneController.text.trim();
    final ownerName =
        (await _authService.getCurrentUserName()) ??
        _nameController.text.trim();

    if (ownerPhone.isEmpty) {
      throw FirebaseException(
        plugin: 'quickdrop',
        message: 'Session phone is missing. Please log in again.',
      );
    }

    final order = Order(
      id: 'QD${DateTime.now().millisecondsSinceEpoch}',
      items: items,
      totalAmount: total,
      status: OrderStatus.pending,
      address: _addressController.text.trim(),
    );

    final deliveryCharge = _deliveryCharge();
    final checkoutName = _nameController.text.trim();
    final checkoutPhone = _phoneController.text.trim();
    final checkoutAddress = _addressController.text.trim();

    final orderData = <String, dynamic>{
      'orderId': order.id,
      'ownerPhone': ownerPhone,
      'ownerName': ownerName,
      'name': checkoutName,
      'phone': checkoutPhone,
      'address': checkoutAddress,
      'customerName': checkoutName,
      'phoneNumber': checkoutPhone,
      'deliveryAddress': _selectedDeliveryAddress ?? checkoutAddress,
      'paymentMethod': paymentMethod,
      'paymentStatus': paymentStatus,
      'latitude': _selectedDeliveryLocation?.latitude,
      'longitude': _selectedDeliveryLocation?.longitude,
      'subtotal': widget.subtotal,
      'deliveryCharge': deliveryCharge,
      'totalAmount': total,
      'status': order.status.label,
      'statusUpdatedAt': Timestamp.now(),
      'statusHistory': [
        {'status': order.status.label, 'updatedAt': Timestamp.now()},
      ],
      'createdAt': Timestamp.now(),
    };

    if (paymentId != null && paymentId.isNotEmpty) {
      orderData['paymentId'] = paymentId;
    }

    await FirebaseFirestore.instance.collection('orders').add(orderData);

    await _reduceStockAfterOrder(items);
    widget.cartNotifier.value = [];
    return order;
  }

  Map<String, Object> _buildRazorpayOptions(int totalAmount) {
    final amountInPaise = totalAmount * 100;
    final checkoutName = _nameController.text.trim();
    final checkoutPhone = _phoneController.text.trim();

    return {
      'key': _razorpayTestKey,
      'amount': amountInPaise,
      'name': 'QuickDrop Go',
      'description': 'Order payment',
      'prefill': {'contact': checkoutPhone, 'name': checkoutName},
      'theme': {'color': '#0B63F6'},
    };
  }

  Future<void> _startOnlinePayment(int total) async {
    if (kIsWeb) {
      throw FirebaseException(
        plugin: 'quickdrop_payment',
        message:
            'Online payment is currently supported on Android and iOS only.',
      );
    }

    if (_razorpayTestKey == 'rzp_test_ReplaceWithYourKey') {
      throw FirebaseException(
        plugin: 'quickdrop_payment',
        message: 'Razorpay test key is not configured.',
      );
    }

    _pendingOnlineTotal = total;
    _razorpay.open(_buildRazorpayOptions(total));
  }

  void _setPlacingOrder(bool value) {
    if (!mounted) {
      return;
    }
    setState(() {
      _isPlacingOrder = value;
    });
  }

  Future<void> _onPaymentSuccess(PaymentSuccessResponse response) async {
    final total = _pendingOnlineTotal;
    if (total == null) {
      _setPlacingOrder(false);
      return;
    }

    try {
      final order = await _buildOrderForCheckout(
        total,
        paymentMethod: _savedPaymentMethodOnline,
        paymentStatus: _savedPaymentStatusPaid,
        paymentId: response.paymentId,
      );

      if (!mounted) {
        return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => OrderSuccessPage(order: order)),
      );
    } on FirebaseException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? 'Failed to place paid order')),
      );
      _setPlacingOrder(false);
    }
  }

  void _onPaymentError(PaymentFailureResponse response) {
    _pendingOnlineTotal = null;

    final rawMessage = response.message?.trim() ?? '';
    final isCancelled = rawMessage.toLowerCase().contains('cancel');
    final message = isCancelled
        ? 'Payment cancelled. Order was not created.'
        : 'Payment failed. Please try again.';

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
    _setPlacingOrder(false);
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    _pendingOnlineTotal = null;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'External wallet is not enabled for this payment flow.',
          ),
        ),
      );
    }
    _setPlacingOrder(false);
  }

  Future<void> _handlePrimaryCheckoutAction(int total) async {
    final items = List<CartItem>.from(widget.cartNotifier.value);
    if (items.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Your cart is empty')));
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    if (_paymentMethod == _paymentMethodOnline) {
      _setPlacingOrder(true);
      try {
        await _startOnlinePayment(total);
      } on FirebaseException catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.message ?? 'Unable to start payment')),
          );
        }
        _setPlacingOrder(false);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unable to start payment.')),
          );
        }
        _setPlacingOrder(false);
      }
      return;
    }

    _setPlacingOrder(true);

    try {
      final order = await _buildOrderForCheckout(
        total,
        paymentMethod: _paymentMethodCod,
        paymentStatus: _savedPaymentStatusPending,
      );

      if (!mounted) {
        return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => OrderSuccessPage(order: order)),
      );
    } on FirebaseException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? 'Failed to place order')),
      );
      _setPlacingOrder(false);
    }
  }

  @override
  void dispose() {
    _razorpay.clear();
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deliveryCharge = _deliveryCharge();
    final total = widget.subtotal + deliveryCharge;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Customer Name',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                decoration: _inputDecoration(
                  'Enter your full name',
                  Icons.person_outline,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter your name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              const Text(
                'Phone Number',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: _inputDecoration(
                  'Enter your phone number',
                  Icons.phone_outlined,
                ),
                validator: (value) {
                  final phone = value?.trim() ?? '';
                  if (!RegExp(r'^\d{10}$').hasMatch(phone)) {
                    return 'Enter a valid phone number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              const Text(
                'Delivery Address',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _addressController,
                minLines: 2,
                maxLines: 3,
                decoration: _inputDecoration(
                  'Enter complete delivery address',
                  Icons.location_on_outlined,
                ),
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter your delivery address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isPlacingOrder
                      ? null
                      : () async {
                          await _selectDeliveryLocation();
                        },
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Select Delivery Location'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _selectedDeliveryAddress == null ||
                        _selectedDeliveryAddress!.isEmpty
                    ? 'No location selected.'
                    : _selectedDeliveryAddress!,
                style: TextStyle(color: Colors.blue.shade700, fontSize: 12),
              ),
              if (_selectedDeliveryLocation != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Lat: ${_selectedDeliveryLocation!.latitude.toStringAsFixed(6)}, Lng: ${_selectedDeliveryLocation!.longitude.toStringAsFixed(6)}',
                  style: TextStyle(color: Colors.blue.shade700, fontSize: 12),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Payment Method',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _paymentMethod,
                    isExpanded: true,
                    icon: Icon(
                      Icons.keyboard_arrow_down,
                      color: Colors.blue.shade700,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: _paymentMethodOnline,
                        child: Text('Online Payment'),
                      ),
                      DropdownMenuItem(
                        value: _paymentMethodCod,
                        child: Text('Cash on Delivery (COD)'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _paymentMethod = value;
                        });
                      }
                    },
                  ),
                ),
              ),
              if (_paymentMethod == _paymentMethodOnline) ...[
                const SizedBox(height: 8),
                Text(
                  'Proceed to Pay will be connected to Razorpay in the next phase.',
                  style: TextStyle(color: Colors.blue.shade700, fontSize: 12),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Total Amount',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _summaryRow('Subtotal', '₹${widget.subtotal}'),
                    _summaryRow('Delivery Charge', '₹$deliveryCharge'),
                    const Divider(),
                    _summaryRow('Grand Total', '₹$total', isBold: true),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isPlacingOrder
                      ? null
                      : () async {
                          await _handlePrimaryCheckoutAction(total);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isPlacingOrder
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _paymentMethod == _paymentMethodOnline
                              ? 'Proceed to Pay'
                              : 'Place Order',
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hintText, IconData icon) {
    return InputDecoration(
      hintText: hintText,
      prefixIcon: Icon(icon, color: Colors.blue.shade700),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.blue.shade100),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.blue.shade100),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.blue.shade700, width: 1.4),
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class OrderSuccessPage extends StatelessWidget {
  final Order order;

  const OrderSuccessPage({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.shade100,
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    color: Colors.blue,
                    size: 56,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Order placed successfully',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your order ${order.id} is currently ${order.status.label.toLowerCase()}.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const OrdersPage()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                  ),
                  child: const Text('View My Orders'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.cartNotifier});

  final ValueNotifier<List<CartItem>>? cartNotifier;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String _name = 'Ayan Deb';
  String _phone = '+91 7005 123456';
  String _address = 'Kunjaban, Agartala';
  bool _isSaving = false;

  DocumentReference<Map<String, dynamic>> get _profileRef => FirebaseFirestore
      .instance
      .collection('user_profiles')
      .doc('quickdrop_default_user');

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final snapshot = await _profileRef.get();
      final data = snapshot.data();
      if (data == null) {
        return;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _name = (data['name']?.toString().trim().isNotEmpty ?? false)
            ? data['name'].toString().trim()
            : _name;
        _phone = (data['phone']?.toString().trim().isNotEmpty ?? false)
            ? data['phone'].toString().trim()
            : _phone;
        _address = (data['address']?.toString().trim().isNotEmpty ?? false)
            ? data['address'].toString().trim()
            : _address;
      });
    } on FirebaseException {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to load profile right now.')),
      );
    }
  }

  Future<void> _saveProfile({
    required String name,
    required String phone,
    required String address,
  }) async {
    setState(() => _isSaving = true);
    try {
      await _profileRef.set({
        'name': name,
        'phone': phone,
        'address': address,
        'updatedAt': Timestamp.now(),
      }, SetOptions(merge: true));

      if (!mounted) {
        return;
      }

      setState(() {
        _name = name;
        _phone = phone;
        _address = address;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile updated')));
    } on FirebaseException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? 'Failed to update profile')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _showEditProfileDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: _name);
    final phoneController = TextEditingController(text: _phone);
    final addressController = TextEditingController(text: _address);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Edit Profile'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Enter your name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone Number',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Enter your phone number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: addressController,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Delivery Address',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Enter your delivery address';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) {
                  return;
                }

                Navigator.pop(dialogContext);
                await _saveProfile(
                  name: nameController.text.trim(),
                  phone: phoneController.text.trim(),
                  address: addressController.text.trim(),
                );
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    nameController.dispose();
    phoneController.dispose();
    addressController.dispose();
  }

  void _openPage(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _logout() async {
    try {
      await AuthService().signOut();

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => QuickDropApp(
            firebaseInitialization: Future<FirebaseApp>.value(Firebase.app()),
          ),
        ),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileCartNotifier =
        widget.cartNotifier ?? ValueNotifier<List<CartItem>>([]);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.shade100,
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 42,
                    backgroundColor: Colors.blue.shade50,
                    child: Icon(
                      Icons.person,
                      size: 40,
                      color: Colors.blue.shade700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _name,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(_phone, style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text(_address, style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _showEditProfileDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                      ),
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.edit_outlined),
                      label: const Text('Edit Profile'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _profileActionTile(
              context: context,
              icon: Icons.receipt_long_outlined,
              title: 'My Orders',
              onTap: () => _openPage(context, const OrdersPage()),
            ),
            _profileActionTile(
              context: context,
              icon: Icons.location_on_outlined,
              title: 'Saved Addresses',
              onTap: _showEditProfileDialog,
            ),
            _profileActionTile(
              context: context,
              icon: Icons.info_outline,
              title: 'About Us',
              onTap: () => _openPage(context, const AboutUsPage()),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _logout,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue.shade700,
                  side: BorderSide(color: Colors.blue.shade200),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.logout),
                label: const Text('Logout'),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: 4,
        selectedItemColor: Colors.blue.shade700,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.grid_view_outlined),
            label: 'Categories',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Orders',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.shopping_cart_outlined),
            label: 'Cart',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
        onTap: (index) {
          switch (index) {
            case 0:
              _openPage(context, HomePage(cartNotifier: profileCartNotifier));
              break;
            case 1:
              _openPage(
                context,
                GroceryPage(cartNotifier: profileCartNotifier),
              );
              break;
            case 2:
              _openPage(context, const OrdersPage());
              break;
            case 3:
              _openPage(context, CartPage(cartNotifier: profileCartNotifier));
              break;
            case 4:
              break;
            default:
              break;
          }
        },
      ),
    );
  }

  Widget _profileActionTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: onTap,
        tileColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Icon(icon, color: Colors.blue.shade700),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      ),
    );
  }
}

class AboutUsPage extends StatelessWidget {
  const AboutUsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About Us'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.shade100,
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'QuickDrop Go',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Version 1.0',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              const _AboutInfoRow(
                icon: Icons.location_city_outlined,
                text: 'Fast delivery in Agartala',
              ),
              const _AboutInfoRow(
                icon: Icons.timer_outlined,
                text: 'Any item delivery in 30 minutes',
              ),
              const _AboutInfoRow(
                icon: Icons.phone_outlined,
                text: 'Contact Number: +91 7005 123456',
              ),
              const _AboutInfoRow(
                icon: Icons.email_outlined,
                text: 'Email: support@quickdrop.in',
              ),
              const _AboutInfoRow(
                icon: Icons.groups_outlined,
                text: 'Developed by QuickDrop Go Team',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AboutInfoRow extends StatelessWidget {
  const _AboutInfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.blue, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF1F2A44),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class OrdersPage extends StatelessWidget {
  const OrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Orders'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<String?>(
        future: authService.getCurrentUserPhone(),
        builder: (context, sessionSnapshot) {
          if (sessionSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final sessionPhone = sessionSnapshot.data?.trim() ?? '';
          if (sessionPhone.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Session not found. Please log in again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            );
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('orders')
                .where('ownerPhone', isEqualTo: sessionPhone)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Unable to load orders.\n${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                );
              }

              final orders = [...(snapshot.data?.docs ?? [])]
                ..sort((a, b) {
                  final aCreatedAt = a.data()['createdAt'];
                  final bCreatedAt = b.data()['createdAt'];

                  if (aCreatedAt is Timestamp && bCreatedAt is Timestamp) {
                    return bCreatedAt.compareTo(aCreatedAt);
                  }
                  return 0;
                });
              if (orders.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        size: 72,
                        color: Colors.blue,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'No orders yet',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Your recent orders will appear here.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: orders.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final orderDoc = orders[index];
                  final data = orders[index].data();
                  final orderId = data['orderId'] as String? ?? '';
                  final address = data['address'] as String? ?? '';
                  final totalAmount = data['totalAmount'];
                  final orderStatus = _orderStatusFromValue(data['status']);

                  return InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => OrderDetailsPage(orderDoc: orderDoc),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  orderId,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: _orderStatusColor(
                                    orderStatus,
                                  ).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _orderStatusIcon(orderStatus),
                                      size: 15,
                                      color: _orderStatusColor(orderStatus),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      orderStatus == OrderStatus.cancelled
                                          ? 'Order Cancelled'
                                          : orderStatus.label,
                                      style: TextStyle(
                                        color: _orderStatusColor(orderStatus),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Address',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            address,
                            style: const TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Total Amount',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '₹$totalAmount',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class OrderDetailsPage extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>>? orderDoc;
  final String? orderId;

  const OrderDetailsPage({super.key, this.orderDoc, this.orderId})
    : assert(orderDoc != null || orderId != null);

  String _formatOrderDate(dynamic createdAt) {
    if (createdAt is Timestamp) {
      final date = createdAt.toDate();
      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      final year = date.year.toString();

      var hour = date.hour;
      final minute = date.minute.toString().padLeft(2, '0');
      final meridiem = hour >= 12 ? 'PM' : 'AM';
      if (hour == 0) {
        hour = 12;
      } else if (hour > 12) {
        hour -= 12;
      }

      return '$day/$month/$year $hour:$minute $meridiem';
    }
    return 'N/A';
  }

  Widget _detailTile({required String label, required String value}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5F0FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F2A44),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusSummaryCard(OrderStatus status) {
    final displayStatus = status == OrderStatus.cancelled
        ? 'Order Cancelled'
        : status.label;
    final statusColor = _orderStatusColor(status);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(_orderStatusIcon(status), color: statusColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayStatus,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  status == OrderStatus.cancelled
                      ? 'The order has been stopped.'
                      : 'Live order progress updates are shown below.',
                  style: TextStyle(color: statusColor.withValues(alpha: 0.84)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressTracker(OrderStatus status) {
    if (status == OrderStatus.cancelled) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.red.shade100),
        ),
        child: Row(
          children: [
            Icon(Icons.cancel_outlined, color: Colors.red.shade700),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Order Cancelled',
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final currentIndex = _orderProgressStages.indexOf(status);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5F0FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order Progress',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          for (int index = 0; index < _orderProgressStages.length; index++)
            Padding(
              padding: EdgeInsets.only(
                bottom: index == _orderProgressStages.length - 1 ? 0 : 12,
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: index <= currentIndex
                          ? _orderStatusColor(
                              _orderProgressStages[index],
                            ).withValues(alpha: 0.12)
                          : Colors.grey.shade100,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: index <= currentIndex
                            ? _orderStatusColor(_orderProgressStages[index])
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Icon(
                      _orderStatusIcon(_orderProgressStages[index]),
                      size: 20,
                      color: index <= currentIndex
                          ? _orderStatusColor(_orderProgressStages[index])
                          : Colors.grey.shade400,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _orderProgressStages[index].label,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: index <= currentIndex
                                ? const Color(0xFF1F2A44)
                                : Colors.grey.shade500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          index < currentIndex
                              ? 'Completed'
                              : index == currentIndex
                              ? 'Current status'
                              : 'Waiting',
                          style: TextStyle(
                            fontSize: 12,
                            color: index <= currentIndex
                                ? _orderStatusColor(_orderProgressStages[index])
                                : Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOrderScaffold(
    BuildContext context,
    Map<String, dynamic> data,
    String fallbackOrderId,
  ) {
    final orderIdValue = data['orderId']?.toString() ?? fallbackOrderId;
    final customerName = data['name']?.toString() ?? 'N/A';
    final phoneNumber = data['phone']?.toString() ?? 'N/A';
    final deliveryAddress = data['address']?.toString() ?? 'N/A';
    final paymentMethod = data['paymentMethod']?.toString() ?? 'N/A';
    final orderStatus = _orderStatusFromValue(data['status']);
    final totalAmount = data['totalAmount']?.toString() ?? '0';
    final orderDate = _formatOrderDate(data['createdAt']);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Details'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: Container(
        color: const Color(0xFFF7FAFF),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0B6DFF), Color(0xFF4DA3FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Order ID',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      orderIdValue,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _statusSummaryCard(orderStatus),
              const SizedBox(height: 16),
              _buildProgressTracker(orderStatus),
              const SizedBox(height: 16),
              _detailTile(label: 'Customer Name', value: customerName),
              _detailTile(label: 'Phone Number', value: phoneNumber),
              _detailTile(label: 'Delivery Address', value: deliveryAddress),
              _detailTile(label: 'Payment Method', value: paymentMethod),
              _detailTile(
                label: 'Order Status',
                value: orderStatus == OrderStatus.cancelled
                    ? 'Order Cancelled'
                    : orderStatus.label,
              ),
              _detailTile(label: 'Total Amount', value: '₹$totalAmount'),
              _detailTile(label: 'Order Date', value: orderDate),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (orderDoc != null) {
      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: orderDoc!.reference.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              appBar: AppBar(
                title: const Text('Order Details'),
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
              ),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Unable to load order details.\n${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting &&
              snapshot.data == null) {
            return Scaffold(
              appBar: AppBar(
                title: const Text('Order Details'),
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
              ),
              body: const Center(child: CircularProgressIndicator()),
            );
          }

          final data = snapshot.data?.data() ?? orderDoc!.data();
          return _buildOrderScaffold(context, data, orderDoc!.id);
        },
      );
    }

    return FutureBuilder<String?>(
      future: AuthService().getCurrentUserPhone(),
      builder: (context, phoneSnapshot) {
        if (phoneSnapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Order Details'),
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final sessionPhone = phoneSnapshot.data?.trim() ?? '';
        if (sessionPhone.isEmpty) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Order Details'),
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
            ),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Session not found. Please log in again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          );
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('orders')
              .where('ownerPhone', isEqualTo: sessionPhone)
              .where('orderId', isEqualTo: orderId)
              .limit(1)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Scaffold(
                appBar: AppBar(
                  title: const Text('Order Details'),
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                ),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Unable to load order details.\n${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return Scaffold(
                appBar: AppBar(
                  title: const Text('Order Details'),
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                ),
                body: const Center(child: CircularProgressIndicator()),
              );
            }

            final doc = snapshot.data?.docs.isNotEmpty == true
                ? snapshot.data!.docs.first
                : null;
            if (doc == null) {
              return Scaffold(
                appBar: AppBar(
                  title: const Text('Order Details'),
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                ),
                body: const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Order not found.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
              );
            }

            return _buildOrderScaffold(context, doc.data(), doc.id);
          },
        );
      },
    );
  }
}

class ProductManagementPage extends StatefulWidget {
  const ProductManagementPage({super.key});

  @override
  State<ProductManagementPage> createState() => _ProductManagementPageState();
}

class _ProductManagementPageState extends State<ProductManagementPage> {
  final CollectionReference<Map<String, dynamic>> _productsRef =
      FirebaseFirestore.instance.collection('products');

  Future<void> _showProductDialog({
    String? documentId,
    Map<String, dynamic>? initialData,
  }) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(
      text: initialData?['name']?.toString() ?? '',
    );
    final priceController = TextEditingController(
      text: initialData?['price']?.toString() ?? '',
    );
    final categoryController = TextEditingController(
      text: initialData?['category']?.toString() ?? '',
    );
    final imageController = TextEditingController(
      text: initialData?['image']?.toString() ?? '',
    );
    final descriptionController = TextEditingController(
      text: initialData?['description']?.toString() ?? '',
    );
    final stockController = TextEditingController(
      text: initialData?['stock']?.toString() ?? '',
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(documentId == null ? 'Add Product' : 'Edit Product'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _productField(
                    controller: nameController,
                    label: 'Name',
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  _productField(
                    controller: priceController,
                    label: 'Price',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) {
                      final price = double.tryParse(value?.trim() ?? '');
                      if (price == null || price < 0) {
                        return 'Enter valid price';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  _productField(
                    controller: categoryController,
                    label: 'Category',
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter category';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  _productField(
                    controller: imageController,
                    label: 'Image URL',
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter image URL';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  _productField(
                    controller: descriptionController,
                    label: 'Description',
                    maxLines: 3,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter description';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  _productField(
                    controller: stockController,
                    label: 'Stock',
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      final stock = int.tryParse(value?.trim() ?? '');
                      if (stock == null || stock < 0) {
                        return 'Enter valid stock';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) {
                  return;
                }

                final productData = <String, dynamic>{
                  'name': nameController.text.trim(),
                  'price': double.parse(priceController.text.trim()),
                  'category': categoryController.text.trim(),
                  'image': imageController.text.trim(),
                  'description': descriptionController.text.trim(),
                  'stock': int.parse(stockController.text.trim()),
                };

                if (documentId == null) {
                  productData['createdAt'] = Timestamp.now();
                  await _productsRef.add(productData);
                } else {
                  await _productsRef.doc(documentId).update(productData);
                }

                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
              ),
              child: Text(documentId == null ? 'Add' : 'Update'),
            ),
          ],
        );
      },
    );

    nameController.dispose();
    priceController.dispose();
    categoryController.dispose();
    imageController.dispose();
    descriptionController.dispose();
    stockController.dispose();
  }

  Future<void> _deleteProduct(String id) async {
    await _productsRef.doc(id).delete();
  }

  Widget _productField({
    required TextEditingController controller,
    required String label,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFF7FAFF),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Management'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showProductDialog(),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Product'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _productsRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Unable to load products.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            );
          }

          final products = [...(snapshot.data?.docs ?? [])]
            ..sort((a, b) {
              final aCreatedAt = a.data()['createdAt'];
              final bCreatedAt = b.data()['createdAt'];
              if (aCreatedAt is Timestamp && bCreatedAt is Timestamp) {
                return bCreatedAt.compareTo(aCreatedAt);
              }
              return 0;
            });

          if (products.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 72,
                    color: Colors.blue,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'No products found',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Tap Add Product to create your catalog.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: products.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = products[index];
              final data = doc.data();
              final name = data['name']?.toString() ?? '';
              final price = data['price']?.toString() ?? '0';
              final category = data['category']?.toString() ?? '';
              final image = data['image']?.toString() ?? '';
              final description = data['description']?.toString() ?? '';
              final stock = data['stock']?.toString() ?? '0';

              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.shade100,
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: image.isEmpty
                              ? Container(
                                  width: 68,
                                  height: 68,
                                  color: Colors.blue.shade50,
                                  child: const Icon(
                                    Icons.image_outlined,
                                    color: Colors.blue,
                                  ),
                                )
                              : Image.network(
                                  image,
                                  width: 68,
                                  height: 68,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Container(
                                    width: 68,
                                    height: 68,
                                    color: Colors.blue.shade50,
                                    child: const Icon(
                                      Icons.broken_image_outlined,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '₹$price  •  $category',
                                style: const TextStyle(color: Colors.grey),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Stock: $stock',
                                style: TextStyle(
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuButton<String>(
                          color: Colors.white,
                          onSelected: (value) async {
                            if (value == 'edit') {
                              await _showProductDialog(
                                documentId: doc.id,
                                initialData: data,
                              );
                            } else if (value == 'delete') {
                              await _deleteProduct(doc.id);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem<String>(
                              value: 'edit',
                              child: Text('Edit'),
                            ),
                            PopupMenuItem<String>(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Description',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
