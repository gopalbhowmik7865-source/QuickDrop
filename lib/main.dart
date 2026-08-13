import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
import 'category_theme.dart';
import 'splash_screen.dart';
import 'models/delivery_settings.dart';
import 'services/delivery_settings_service.dart';
import 'firestore_query_helpers.dart';

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
  final String brand;
  final String weight;
  final String measureUnit;
  final double? oldPrice;
  final int discountPercent;
  final String shortDescription;

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
    this.brand = '',
    this.weight = '',
    this.measureUnit = '',
    this.oldPrice,
    this.discountPercent = 0,
    this.shortDescription = '',
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
  final CategoryTheme theme;
  final String firestoreCategory;
  final List<String> subcategories;

  const MainCategory({
    required this.title,
    required this.emoji,
    required this.theme,
    required this.firestoreCategory,
    required this.subcategories,
  });
}

const List<MainCategory> homeMainCategories = [
  MainCategory(
    title: 'Grocery',
    emoji: '🛒',
    theme: groceryCategoryTheme,
    firestoreCategory: 'Grocery',
    subcategories: ['Atta, Rice & Dal', 'Oil, Ghee & Masala', 'Dairy & Eggs'],
  ),
  MainCategory(
    title: 'Vegetables',
    emoji: '🥬',
    theme: vegetablesCategoryTheme,
    firestoreCategory: 'Vegetables',
    subcategories: vegetableSubcategories,
  ),
  MainCategory(
    title: 'Fruits',
    emoji: '🍎',
    theme: fruitsCategoryTheme,
    firestoreCategory: 'Fruits',
    subcategories: fruitSubcategories,
  ),
  MainCategory(
    title: 'Food',
    emoji: '🍔',
    theme: foodCategoryTheme,
    firestoreCategory: 'Food',
    subcategories: ['Restaurant Food', 'Fast Food', 'Beverages', 'Sweets'],
  ),
  MainCategory(
    title: 'Gifts',
    emoji: '💐',
    theme: giftsCategoryTheme,
    firestoreCategory: 'Gifts',
    subcategories: ['Flowers', 'Chocolates', 'Soft Toys', 'Gift Combos'],
  ),
  MainCategory(
    title: 'Gifts & Surprises',
    emoji: '🎁',
    theme: giftsSurprisesCategoryTheme,
    firestoreCategory: 'Gifts',
    subcategories: ['Surprise your loved ones'],
  ),
  MainCategory(
    title: 'Cosmetics',
    emoji: '💄',
    theme: cosmeticsCategoryTheme,
    firestoreCategory: 'Cosmetics',
    subcategories: ['Bath & Body', 'Hair Care', 'Beauty Products'],
  ),
  MainCategory(
    title: 'Electronics',
    emoji: '📱',
    theme: electronicsCategoryTheme,
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
    theme: homeServiceCategoryTheme,
    firestoreCategory: 'Home Service',
    subcategories: [],
  ),
  MainCategory(
    title: 'Parcel Delivery',
    emoji: '📦',
    theme: parcelDeliveryCategoryTheme,
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
      Rect.fromCenter(
        center: Offset(w * 0.40, h * 0.30),
        width: w * 0.16,
        height: h * 0.18,
      ),
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
      Rect.fromCenter(
        center: Offset(w * 0.24, h * 0.40),
        width: w * 0.11,
        height: h * 0.12,
      ),
      paint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.56, h * 0.40),
        width: w * 0.11,
        height: h * 0.12,
      ),
      paint,
    );
    canvas.drawLine(
      Offset(w * 0.24, h * 0.34),
      Offset(w * 0.24, h * 0.28),
      paint,
    );
    canvas.drawLine(
      Offset(w * 0.56, h * 0.34),
      Offset(w * 0.56, h * 0.28),
      paint,
    );

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

    canvas.drawLine(
      Offset(w * 0.07, h * 0.73),
      Offset(w * 0.84, h * 0.73),
      paint,
    );
    canvas.drawLine(
      Offset(w * 0.16, h * 0.69),
      Offset(w * 0.76, h * 0.69),
      paint,
    );
    canvas.drawLine(
      Offset(w * 0.24, h * 0.65),
      Offset(w * 0.68, h * 0.65),
      paint,
    );

    for (final dx in <double>[0.21, 0.30, 0.40, 0.50, 0.60]) {
      final x = w * dx;
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(x, h * 0.61),
          width: w * 0.045,
          height: h * 0.08,
        ),
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
      return const Color(0xFFFFC107);
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
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
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

  runApp(QuickDropApp(firebaseInitialization: Future.value(Firebase.app())));
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

  Future<Widget> _buildInitialPage() async {
    await _buildStartupFuture();

    final bool forceHomeForDevelopment = true;
    // TODO: Temporary dev-only bypass. Restore FirebaseAuth-based startup
    // routing after the login issue is fixed.
    if (forceHomeForDevelopment) {
      return HomePage(cartNotifier: cartNotifier);
    }

    final auth = FirebaseAuth.instance;
    User? user = auth.currentUser;

    // On some cold starts, Firebase restores persisted auth state shortly
    // after initialization. Wait briefly before final routing decision.
    if (user == null) {
      try {
        user = await auth.authStateChanges().first.timeout(
          const Duration(seconds: 2),
        );
      } catch (_) {
        // Keep user as null and fall back to LoginPage.
      }
    }

    if (user != null) {
      return HomePage(cartNotifier: cartNotifier);
    }
    return LoginPage(cartNotifier: cartNotifier);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: appScaffoldMessengerKey,
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'QuickDrop Go',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFFC107)),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFFFFFFF),
      ),
      home: SplashScreen(
        nextPageBuilder: _buildInitialPage,
        errorBuilder: (context, error, retry) {
          return StartupErrorScreen(error: error, onRetry: retry);
        },
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
            colors: [Color(0xFFF8F9FA), Colors.white],
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
                  color: Color(0xFFFFC107),
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

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin<HomePage> {
  static const bool _isFlutterTest = bool.fromEnvironment('FLUTTER_TEST');
  static const PageStorageKey<String> _homeScrollKey = PageStorageKey<String>(
    'home_page_scroll',
  );
  final AuthService _drawerAuthService = AuthService();
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _homeScrollController = ScrollController();
  final PageController _bannerController = PageController(viewportFraction: 1);
  final ValueNotifier<int> _bannerIndexNotifier = ValueNotifier<int>(0);
  Timer? _bannerTimer;
  Timer? _searchDebounce;
  StreamSubscription<DeliverySettings>? _homeDeliverySettingsSubscription;
  DeliverySettings _homeDeliverySettings = const DeliverySettings();
  bool _homeDeliverySettingsLoaded = false;

  bool _enableProductStream = false;
  bool _showAllCategories = false;
  int _bannerCount = 3;
  String searchQuery = '';
  bool _isSearchingProducts = false;
  String? _searchProductsError;
  List<_SearchResultItem> _searchResults = const <_SearchResultItem>[];
  late final List<String> _productSearchCollections;
  late final Future<Map<String, dynamic>?> _drawerProfileFuture;

  @override
  void initState() {
    super.initState();
    _drawerProfileFuture = _drawerAuthService.loadCurrentUserProfile();
    _productSearchCollections = _buildProductSearchCollections();
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
    if (Firebase.apps.isNotEmpty) {
      _homeDeliverySettingsSubscription = DeliverySettingsService()
          .watch()
          .listen((settings) {
            if (mounted) {
              setState(() {
                _homeDeliverySettings = settings;
                _homeDeliverySettingsLoaded = true;
              });
            }
          });
    }
  }

  List<String> _buildProductSearchCollections() {
    final collections = <String>{'products'};

    for (final category in homeMainCategories) {
      final raw = category.firestoreCategory.trim();
      if (raw.isEmpty) {
        continue;
      }

      final snake = raw
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'_+'), '_')
          .replaceAll(RegExp(r'^_|_$'), '');

      collections.add(raw);
      collections.add(raw.toLowerCase());
      if (snake.isNotEmpty) {
        collections.add(snake);
        collections.add('${snake}_products');
      }
    }

    final sorted = collections.toList()..sort();
    developer.log(
      'Search collections configured: ${sorted.join(', ')}',
      name: 'QuickDropSearch',
    );
    return sorted;
  }

  Future<void> _searchProductsAcrossCollections(String input) async {
    final query = input.trim().toLowerCase();
    if (query.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSearchingProducts = false;
        _searchProductsError = null;
        _searchResults = const <_SearchResultItem>[];
      });
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _isSearchingProducts = true;
      _searchProductsError = null;
    });

    final results = <_SearchResultItem>[];
    final seen = <String>{};

    try {
      for (final collectionName in _productSearchCollections) {
        try {
          final snapshot = await FirebaseFirestore.instance
              .collection(collectionName)
              .limit(200)
              .get()
              .timeout(const Duration(seconds: 10));
          var matchCount = 0;

          developer.log(
            'Search query "$query" -> $collectionName: fetched ${snapshot.docs.length} docs.',
            name: 'QuickDropSearch',
          );

          for (final doc in snapshot.docs) {
            final data = doc.data();
            final name = (data['name'] ?? '').toString().trim();
            if (name.isEmpty || !name.toLowerCase().contains(query)) {
              continue;
            }

            final dedupeKey = '$collectionName/${doc.id}';
            if (!seen.add(dedupeKey)) {
              continue;
            }

            final patched = <String, dynamic>{...data};
            if ((patched['category'] ?? '').toString().trim().isEmpty) {
              patched['category'] = collectionName;
            }

            results.add(
              _SearchResultItem(
                collection: collectionName,
                id: doc.id,
                product: _productFromDoc(patched, productId: doc.id),
                raw: patched,
              ),
            );
            matchCount += 1;
          }

          developer.log(
            'Search query "$query" -> $collectionName: matched $matchCount docs.',
            name: 'QuickDropSearch',
          );
        } on FirebaseException catch (error, stackTrace) {
          developer.log(
            'Search query "$query" -> $collectionName failed: ${error.code} ${error.message}',
            name: 'QuickDropSearch',
            error: error,
            stackTrace: stackTrace,
          );
        } on TimeoutException catch (error, stackTrace) {
          developer.log(
            'Search query "$query" -> $collectionName timed out.',
            name: 'QuickDropSearch',
            error: error,
            stackTrace: stackTrace,
          );
        } catch (error, stackTrace) {
          developer.log(
            'Search query "$query" -> $collectionName unexpected error.',
            name: 'QuickDropSearch',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }

      results.sort(
        (a, b) => a.product.name.toLowerCase().compareTo(
          b.product.name.toLowerCase(),
        ),
      );

      developer.log(
        'Search query "$query" -> total matches: ${results.length}',
        name: 'QuickDropSearch',
      );

      if (!mounted || searchQuery.trim().toLowerCase() != query) {
        return;
      }

      setState(() {
        _searchResults = results;
        _isSearchingProducts = false;
      });
    } catch (error, stackTrace) {
      developer.log(
        'Search query "$query" failed globally.',
        name: 'QuickDropSearch',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted || searchQuery.trim().toLowerCase() != query) {
        return;
      }
      setState(() {
        _isSearchingProducts = false;
        _searchProductsError = 'Unable to search products right now.';
        _searchResults = const <_SearchResultItem>[];
      });
    }
  }

  void _onSearchTextChanged(String value) {
    setState(() {
      searchQuery = value;
    });

    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 260), () {
      _searchProductsAcrossCollections(value);
    });
  }

  void _openSearchResultDetails(_SearchResultItem result) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductDetailsPage(
          product: result.product,
          sourceCollection: result.collection,
          cartNotifier: widget.cartNotifier,
        ),
      ),
    );
  }

  void _openProductDetails(
    GroceryItem product, {
    String sourceCollection = 'products',
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductDetailsPage(
          product: product,
          sourceCollection: sourceCollection,
          cartNotifier: widget.cartNotifier,
        ),
      ),
    );
  }

  void _startBannerAutoSlide() {
    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_bannerController.hasClients) {
        return;
      }
      final nextPage = (_bannerIndexNotifier.value + 1) % _bannerCount;
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
          accent: category.theme.primary,
          subcategories: category.subcategories,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _homeDeliverySettingsSubscription?.cancel();
    _bannerTimer?.cancel();
    _searchDebounce?.cancel();
    _bannerIndexNotifier.dispose();
    _bannerController.dispose();
    _homeScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

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

  Color _categoryIconCircleBackground(String title) {
    switch (title) {
      case 'Grocery':
        return const Color(0xFFFFF3B0);
      case 'Vegetables':
        return const Color(0xFFD9F7BE);
      case 'Fruits':
        return const Color(0xFFFFE5D0);
      case 'Food':
        return const Color(0xFFFFE4E6);
      case 'Gifts':
        return const Color(0xFFF3E8FF);
      case 'Gifts & Surprises':
        return const Color(0xFFE0F2FE);
      case 'Cosmetics':
        return const Color(0xFFFCE7F3);
      case 'Electronics':
        return const Color(0xFFE0E7FF);
      case 'Home Service':
        return const Color(0xFFFEF3C7);
      case 'Courier / Delivery':
      case 'Parcel Delivery':
        return const Color(0xFFDBEAFE);
      default:
        return const Color(0xFFE5E7EB);
    }
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
    final sold =
        (_toDouble(data['sold']) ??
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

    final hasOfferTag =
        [
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
      accent = const Color(0xFFFFC107);
    } else if (normalized.contains('gift')) {
      accent = Colors.pink.shade700;
    } else if (normalized.contains('electronic')) {
      accent = Colors.indigo.shade700;
    } else if (normalized.contains('beauty') ||
        normalized.contains('cosmetic')) {
      accent = Colors.purple.shade700;
    } else {
      accent = const Color(0xFFFFC107);
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

  Future<void> _showDrawerLogoutConfirmation() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Logout', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );

    if (shouldLogout != true) {
      return;
    }

    await _drawerAuthService.signOut();

    if (!mounted) {
      return;
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) =>
            LoginPage(cartNotifier: ValueNotifier<List<CartItem>>([])),
      ),
      (route) => false,
    );
  }

  Widget _buildSearchResultsSection() {
    final trimmed = searchQuery.trim();
    if (trimmed.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF8F9FA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Search results for "$trimmed"',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (_isSearchingProducts)
            const LinearProgressIndicator()
          else if (_searchProductsError != null)
            Text(
              _searchProductsError!,
              style: TextStyle(
                color: Colors.red.shade700,
                fontWeight: FontWeight.w600,
              ),
            )
          else if (_searchResults.isEmpty)
            const Text(
              'No products found',
              style: TextStyle(color: Colors.black54),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _searchResults.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final result = _searchResults[index];
                final item = result.product;

                return InkWell(
                  onTap: () => _openSearchResultDetails(result),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFF8F9FA)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
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
                            const Spacer(),
                            const Icon(Icons.chevron_right_rounded),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: item.imageUrl.isNotEmpty
                                  ? Image.network(
                                      item.imageUrl,
                                      width: 52,
                                      height: 52,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) {
                                        return Container(
                                          width: 52,
                                          height: 52,
                                          color: const Color(0xFFF8F9FA),
                                          alignment: Alignment.center,
                                          child: Icon(
                                            Icons.image_not_supported_outlined,
                                            color: const Color(0xFFFFECB3),
                                          ),
                                        );
                                      },
                                    )
                                  : Container(
                                      width: 52,
                                      height: 52,
                                      color: const Color(0xFFF8F9FA),
                                      alignment: Alignment.center,
                                      child: Icon(
                                        Icons.shopping_bag_outlined,
                                        color: const Color(0xFFFFECB3),
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    item.price,
                                    style: const TextStyle(
                                      color: Color(0xFFFFC107),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    item.stock <= 0
                                        ? 'Out of stock'
                                        : 'In stock: ${item.stock}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: item.stock <= 0
                                          ? Colors.red.shade700
                                          : Colors.green.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 46,
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: item.stock <= 0
                                ? null
                                : () {
                                    _addToCart(item);
                                  },
                            style: ElevatedButton.styleFrom(
                              elevation: 0,
                              backgroundColor: const Color(0xFF2E7D32),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.add_shopping_cart, size: 16),
                            label: Text(
                              item.stock <= 0 ? 'Out of Stock' : 'Add to Cart',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
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
          color: category.theme.background,
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
                color: category.theme.primary.withValues(alpha: 0.18),
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
                color: Color(0xFF212121),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _localHomeGiftPromoBanner(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bannerHeight = (constraints.maxWidth * 0.24)
            .clamp(180.0, 220.0)
            .toDouble();

        Widget placeholder({required bool loading}) {
          return Container(
            height: bannerHeight,
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFF8F9FA)),
            ),
            alignment: Alignment.center,
            child: loading
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.image_not_supported_outlined,
                        color: const Color(0xFFFFECB3),
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
                    if (index != _bannerIndexNotifier.value) {
                      _bannerIndexNotifier.value = index;
                    }
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
                            frameBuilder:
                                (
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
                            errorBuilder: (_, _, _) =>
                                placeholder(loading: false),
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
                                  color: const Color(0xFFFFC107),
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
                                  color: Color(0xFF212121),
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
                            const Color(0xFFFFC107),
                            const Color(0xFFFFC107),
                            const Color(0xFFFFECB3),
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
                            const Color(0xFFFFC107),
                            const Color(0xFFFFC107),
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
            ValueListenableBuilder<int>(
              valueListenable: _bannerIndexNotifier,
              builder: (context, activeIndex, _) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    3,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      height: 8,
                      width: activeIndex == index ? 24 : 8,
                      decoration: BoxDecoration(
                        color: activeIndex == index
                            ? const Color(0xFFFFC107)
                            : const Color(0xFFFFECB3),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _homeGiftPromoBanner(BuildContext context) {
    if (Firebase.apps.isEmpty) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('banners')
          .where('isActive', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('Banner Firestore query error: ${snapshot.error}');
        }

        final bannerDocs = [...?snapshot.data?.docs]
          ..sort((left, right) {
            final leftOrder = left.data()['displayOrder'] as num? ?? 0;
            final rightOrder = right.data()['displayOrder'] as num? ?? 0;
            return leftOrder.compareTo(rightOrder);
          });

        debugPrint('Banner documents returned: ${bannerDocs.length}');
        for (final doc in bannerDocs) {
          final data = doc.data();
          debugPrint(
            'Banner ${doc.id}: imageUrl=${data['imageUrl']}, '
            'isActive=${data['isActive']}, '
            'displayOrder=${data['displayOrder']}',
          );
        }

        final imageUrls = bannerDocs
            .map((doc) => doc.data()['imageUrl']?.toString().trim() ?? '')
            .where((url) => url.isNotEmpty)
            .toList();

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return const SizedBox.shrink();
        }

        if (imageUrls.isEmpty) {
          _bannerCount = 3;
          return _localHomeGiftPromoBanner(context);
        }

        _bannerCount = imageUrls.length;

        return LayoutBuilder(
          builder: (context, constraints) {
            final bannerHeight = (constraints.maxWidth * 0.24)
                .clamp(180.0, 220.0)
                .toDouble();

            Widget placeholder() {
              return Container(
                color: const Color(0xFFF8F9FA),
                alignment: Alignment.center,
                child: const CircularProgressIndicator(),
              );
            }

            return Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: SizedBox(
                    height: bannerHeight,
                    child: PageView.builder(
                      controller: _bannerController,
                      itemCount: imageUrls.length,
                      onPageChanged: (index) {
                        if (index != _bannerIndexNotifier.value) {
                          _bannerIndexNotifier.value = index;
                        }
                      },
                      itemBuilder: (context, index) {
                        return CachedNetworkImage(
                          imageUrl: imageUrls[index],
                          fit: BoxFit.cover,
                          placeholder: (_, _) => placeholder(),
                          errorWidget: (_, _, _) => Image.asset(
                            'assets/banners/gift_banner.jpg',
                            fit: BoxFit.cover,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                ValueListenableBuilder<int>(
                  valueListenable: _bannerIndexNotifier,
                  builder: (context, activeIndex, _) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        imageUrls.length,
                        (index) => AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          height: 8,
                          width: activeIndex == index ? 24 : 8,
                          decoration: BoxDecoration(
                            color: activeIndex == index
                                ? const Color(0xFFFFC107)
                                : const Color(0xFFFFECB3),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            );
          },
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
                  color: Color(0xFF212121),
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: const Color(0xFF212121),
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
              border: Border.all(color: const Color(0xFFF8F9FA)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFF8F9FA).withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Text(
              'No products available right now.',
              style: TextStyle(
                color: const Color(0xFF212121),
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          SizedBox(
            height: 230,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemBuilder: (context, index) {
                return SizedBox(
                  width: 124,
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
    final categoryTheme = categoryThemeFor(canonicalCategory(item.product.tag));
    final brandText = (item.raw['brand']?.toString() ?? '').trim();
    final weightText = (item.raw['weight']?.toString() ?? '').trim();
    final unitText = (item.raw['unit']?.toString() ?? '').trim();
    final weightUnitText = [
      weightText,
      unitText,
    ].where((part) => part.isNotEmpty).join(' ');
    final shortDescription = (item.raw['shortDescription']?.toString() ?? '')
        .trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openProductDetails(item.product),
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: categoryTheme.primary.withValues(alpha: 0.12),
            ),
            boxShadow: [
              BoxShadow(
                color: categoryTheme.primary.withValues(alpha: 0.12),
                blurRadius: 18,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 74,
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: resolvedImageUrl.isNotEmpty
                          ? Container(
                              width: double.infinity,
                              height: 74,
                              color: categoryTheme.background,
                              alignment: Alignment.center,
                              child: Image.network(
                                resolvedImageUrl,
                                width: 50,
                                height: 50,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) => Icon(
                                  Icons.shopping_bag_outlined,
                                  color: categoryTheme.primary,
                                  size: 32,
                                ),
                              ),
                            )
                          : Container(
                              width: double.infinity,
                              height: 74,
                              color: categoryTheme.background,
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.shopping_bag_outlined,
                                color: categoryTheme.primary,
                                size: 32,
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
                          border: Border.all(
                            color: categoryTheme.primary.withValues(
                              alpha: 0.18,
                            ),
                          ),
                        ),
                        child: Text(
                          item.product.tag,
                          style: TextStyle(
                            color: categoryTheme.primary,
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
              const SizedBox(height: 5),
              if (brandText.isNotEmpty)
                Text(
                  brandText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF212121),
                  ),
                ),
              Text(
                item.product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF212121),
                ),
              ),
              if (weightUnitText.isNotEmpty)
                Text(
                  weightUnitText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF212121),
                  ),
                ),
              const SizedBox(height: 1),
              Row(
                children: [
                  Text(
                    item.product.price,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: categoryTheme.primary,
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
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
              if (shortDescription.isNotEmpty)
                Text(
                  shortDescription,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    color: const Color(0xFF212121),
                  ),
                ),
              const SizedBox(height: 1),
              Text(
                outOfStock ? 'Out of stock' : 'In stock: ${item.product.stock}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: outOfStock
                      ? Colors.red.shade600
                      : Colors.green.shade700,
                ),
              ),
              const SizedBox(height: 2),
              SizedBox(
                height: 46,
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: outOfStock
                      ? null
                      : () {
                          _addToCart(item.product);
                        },
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: categoryTheme.primary,
                    disabledBackgroundColor: Colors.grey.shade400,
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: EdgeInsets.zero,
                  ),
                  icon: const Icon(Icons.add_shopping_cart, size: 15),
                  label: Text(outOfStock ? 'Out of Stock' : 'Add to Cart'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ValueListenableBuilder<List<CartItem>>(
      valueListenable: widget.cartNotifier,
      builder: (context, cartItems, _) {
        final canUseFirestore =
            _enableProductStream && Firebase.apps.isNotEmpty;
        final totalItems = cartItems.fold<int>(
          0,
          (totalCount, item) => totalCount + item.quantity,
        );

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: const Color(0xFFFFFFFF),
          drawer: Drawer(
            backgroundColor: const Color(0xFFFFFDF8),
            child: SafeArea(
              child: Column(
                children: [
                  FutureBuilder<Map<String, dynamic>?>(
                    future: _drawerProfileFuture,
                    builder: (context, snapshot) {
                      final profile = snapshot.data;
                      final name =
                          (profile?['name']?.toString().trim().isNotEmpty ??
                              false)
                          ? profile!['name'].toString().trim()
                          : 'QuickDrop User';
                      final phone =
                          (profile?['phoneNumber']
                                  ?.toString()
                                  .trim()
                                  .isNotEmpty ??
                              false)
                          ? profile!['phoneNumber'].toString().trim()
                          : 'Not available';
                      final avatarLetter = name.isNotEmpty
                          ? name.substring(0, 1).toUpperCase()
                          : 'Q';

                      return Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFEADFCF), Color(0xFFEADFCF)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.45),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  avatarLetter,
                                  style: const TextStyle(
                                    color: Color(0xFF2E2E2E),
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
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
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF2E2E2E),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 17,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    phone,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: const Color(0xFF6D5D4B),
                                      fontWeight: FontWeight.w500,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'QuickDrop Member',
                                    style: TextStyle(
                                      color: const Color(0xFF5B4B3A),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      children: [
                        ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: const BoxDecoration(
                              color: Color(0xFFF3ECE0),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.home_outlined,
                              color: Color(0xFF6D5D4B),
                              size: 20,
                            ),
                          ),
                          title: const Text(
                            'Home',
                            style: TextStyle(color: Color(0xFF2E2E2E)),
                          ),
                          onTap: () => Navigator.pop(context),
                        ),
                        ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: const BoxDecoration(
                              color: Color(0xFFF3ECE0),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.shopping_basket_outlined,
                              color: Color(0xFF6D5D4B),
                              size: 20,
                            ),
                          ),
                          title: const Text(
                            'Grocery',
                            style: TextStyle(color: Color(0xFF2E2E2E)),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => GroceryPage(
                                  cartNotifier: widget.cartNotifier,
                                ),
                              ),
                            );
                          },
                        ),
                        ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: const BoxDecoration(
                              color: Color(0xFFF3ECE0),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.receipt_long_outlined,
                              color: Color(0xFF6D5D4B),
                              size: 20,
                            ),
                          ),
                          title: const Text(
                            'My Orders',
                            style: TextStyle(color: Color(0xFF2E2E2E)),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const OrdersPage(),
                              ),
                            );
                          },
                        ),
                        ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: const BoxDecoration(
                              color: Color(0xFFF3ECE0),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.favorite_border,
                              color: Color(0xFF6D5D4B),
                              size: 20,
                            ),
                          ),
                          title: const Text(
                            'Wishlist',
                            style: TextStyle(color: Color(0xFF2E2E2E)),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AuthProfilePage(
                                  viewMode: AuthProfileViewMode.wishlist,
                                ),
                              ),
                            );
                          },
                        ),
                        ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: const BoxDecoration(
                              color: Color(0xFFF3ECE0),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.local_offer_outlined,
                              color: Color(0xFF6D5D4B),
                              size: 20,
                            ),
                          ),
                          title: const Text(
                            'Offers & Coupons',
                            style: TextStyle(color: Color(0xFF2E2E2E)),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            appScaffoldMessengerKey.currentState?.showSnackBar(
                              const SnackBar(
                                content: Text('Offers coming soon'),
                              ),
                            );
                          },
                        ),
                        ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: const BoxDecoration(
                              color: Color(0xFFF3ECE0),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.settings_outlined,
                              color: Color(0xFF6D5D4B),
                              size: 20,
                            ),
                          ),
                          title: const Text(
                            'Settings',
                            style: TextStyle(color: Color(0xFF2E2E2E)),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AuthProfilePage(
                                  viewMode: AuthProfileViewMode.settings,
                                ),
                              ),
                            );
                          },
                        ),
                        ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: const BoxDecoration(
                              color: Color(0xFFF3ECE0),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.support_agent_outlined,
                              color: Color(0xFF6D5D4B),
                              size: 20,
                            ),
                          ),
                          title: const Text(
                            'Help & Support',
                            style: TextStyle(color: Color(0xFF2E2E2E)),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AuthProfilePage(
                                  viewMode: AuthProfileViewMode.helpSupport,
                                ),
                              ),
                            );
                          },
                        ),
                        ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: const BoxDecoration(
                              color: Color(0xFFF3ECE0),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.logout,
                              color: Color(0xFFE53935),
                              size: 20,
                            ),
                          ),
                          title: const Text(
                            'Logout',
                            style: TextStyle(
                              color: Color(0xFFE53935),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          onTap: () async {
                            Navigator.pop(context);
                            await _showDrawerLogoutConfirmation();
                          },
                        ),
                      ],
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEADFCF),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE8E0D5)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Best Deals',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: Color(0xFF2E2E2E),
                          ),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => GroceryPage(
                                  cartNotifier: widget.cartNotifier,
                                ),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFF3ECE0), Color(0xFFFFFDF8)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.bolt_rounded,
                                  size: 15,
                                  color: Color(0xFF6D5D4B),
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Flash Sale up to 40% off',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF2E2E2E),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const OrdersPage(),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFF3ECE0), Color(0xFFFFFDF8)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.local_shipping_outlined,
                                  size: 15,
                                  color: Color(0xFF6D5D4B),
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Free delivery on select orders',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF2E2E2E),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                    child: Column(
                      children: const [
                        Text(
                          'QuickDrop Go',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF8A7A68),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Version 1.0.0',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFFA19180),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          body: SafeArea(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: canUseFirestore
                  ? FirebaseFirestore.instance
                        .collection('products')
                        .snapshots()
                  : null,
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? [];
                final allProducts = docs.map((doc) {
                  final data = doc.data();
                  final product = _productFromDoc(data, productId: doc.id);
                  final priceValue =
                      _toDouble(data['price']) ??
                      _toDouble(product.price) ??
                      parsePrice(product.price).toDouble();
                  final oldPrice =
                      _toDouble(data['oldPrice']) ??
                      _toDouble(data['old_price']) ??
                      _toDouble(data['mrp']) ??
                      _toDouble(data['originalPrice']) ??
                      _toDouble(data['strikePrice']) ??
                      _toDouble(data['compareAtPrice']);

                  return _HomeProductItem(
                    product: product,
                    oldPrice:
                        oldPrice != null &&
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
                }).toList();

                final popularItems = allProducts.take(8).toList();

                final bestSellerItems = List<_HomeProductItem>.from(allProducts)
                  ..sort(
                    (a, b) => b.bestSellerScore.compareTo(a.bestSellerScore),
                  );

                final offerItems = allProducts
                    .where((item) => _isOfferItem(item.raw, item))
                    .toList();
                final visibleCategories = _showAllCategories
                    ? homeMainCategories
                    : homeMainCategories.take(6).toList();

                final offersSectionItems = offerItems.isNotEmpty
                    ? offerItems.take(8).toList()
                    : allProducts.take(8).toList();

                return SingleChildScrollView(
                  key: _homeScrollKey,
                  controller: _homeScrollController,
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 6),
                      if (_homeDeliverySettingsLoaded) _homeStoreStatusBanner(),
                      Container(
                        width: double.infinity,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xFFFFF6D8), Colors.white],
                            stops: [0.0, 0.6],
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  InkWell(
                                    onTap: () {
                                      _scaffoldKey.currentState?.openDrawer();
                                    },
                                    borderRadius: BorderRadius.circular(999),
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      alignment: Alignment.center,
                                      child: const Icon(
                                        Icons.menu,
                                        size: 24,
                                        color: Color(0xFF212121),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'QuickDrop Go',
                                          style: TextStyle(
                                            color: Color(0xFF212121),
                                            fontSize: 21,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          'Deliver to Agartala, Tripura',
                                          style: TextStyle(
                                            color: Color(0xFF5F6368),
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      IconButton(
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  const NotificationsScreen(),
                                            ),
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.notifications_none_rounded,
                                          color: Color(0xFF2E7D32),
                                        ),
                                      ),
                                      Positioned(
                                        top: 9,
                                        right: 10,
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
                                  IconButton(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const AuthProfilePage(),
                                        ),
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.person_outline_rounded,
                                      color: Color(0xFFFFC107),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0xFFFFF7DC),
                              Color(0xFFFFFCEE),
                              Colors.white,
                            ],
                            stops: [0.0, 0.6, 1.0],
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Hello, Shopper 👋',
                                style: TextStyle(
                                  color: Color(0xFF212121),
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'What would you like to get today?',
                                style: TextStyle(
                                  color: const Color(
                                    0xFF212121,
                                  ).withValues(alpha: 0.78),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),
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
                                      border: Border.all(
                                        color: const Color(0xFFE5E7EB),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.06,
                                          ),
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
                                          color: Color(0xFF2E7D32),
                                        ),
                                        SizedBox(width: 5),
                                        Text(
                                          'Trusted Service',
                                          style: TextStyle(
                                            color: Color(0xFF2E7D32),
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: 60,
                                ),
                                child: Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(30),
                                    border: Border.all(
                                      color: const Color(0xFFE5E7EB),
                                      width: 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.06,
                                        ),
                                        blurRadius: 18,
                                        spreadRadius: 0,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: TextField(
                                    controller: _searchController,
                                    onChanged: _onSearchTextChanged,
                                    decoration: const InputDecoration(
                                      hintText:
                                          'Search groceries, food, gifts...',
                                      prefixIcon: Icon(
                                        Icons.search_rounded,
                                        color: Color(0xFF2E7D32),
                                        size: 28,
                                      ),
                                      suffixIcon: Padding(
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
                                              color: Color(0xFF2E7D32),
                                            ),
                                          ),
                                        ),
                                      ),
                                      suffixIconConstraints: BoxConstraints(
                                        minWidth: 64,
                                      ),
                                      filled: true,
                                      fillColor: Colors.white,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 14,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.all(
                                          Radius.circular(30),
                                        ),
                                        borderSide: BorderSide.none,
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.all(
                                          Radius.circular(30),
                                        ),
                                        borderSide: BorderSide.none,
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.all(
                                          Radius.circular(30),
                                        ),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildSearchResultsSection(),
                      if (searchQuery.trim().isNotEmpty)
                        const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _homeGiftPromoBanner(context),
                      ),
                      const SizedBox(height: 22),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Categories',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1F2937),
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _showAllCategories = !_showAllCategories;
                                });
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 2,
                                ),
                                child: Text(
                                  _showAllCategories
                                      ? 'See Less ↑'
                                      : 'See All →',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1F2937),
                                  ),
                                ),
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
                            vertical: 8,
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
                              final width = constraints.maxWidth;
                              final crossAxisCount = width < 380 ? 3 : 4;

                              return GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: visibleCategories.length,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: crossAxisCount,
                                      mainAxisSpacing: 10,
                                      crossAxisSpacing: 12,
                                      childAspectRatio: 0.66,
                                    ),
                                itemBuilder: (context, index) {
                                  final category = visibleCategories[index];
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
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: category.theme.background,
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.max,
                                          mainAxisAlignment:
                                              MainAxisAlignment.start,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            const SizedBox(height: 4),
                                            Container(
                                              width: 72,
                                              height: 72,
                                              decoration: BoxDecoration(
                                                color:
                                                    _categoryIconCircleBackground(
                                                      category.title,
                                                    ),
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
                                                    _ =>
                                                      'assets/banners/grocery.png',
                                                  },
                                                  width: 60,
                                                  height: 60,
                                                  fit: BoxFit.contain,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Expanded(
                                              child: Center(
                                                child: Text(
                                                  category.title,
                                                  maxLines: 2,
                                                  softWrap: true,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFF1F2937),
                                                    height: 1.2,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
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
                                subtitle:
                                    'Trending choices from live inventory',
                                items: const [],
                              ),
                              const SizedBox(height: 24),
                              _buildProductSection(
                                title: 'Best Sellers',
                                subtitle:
                                    'Top performing products customers love',
                                items: const [],
                              ),
                            ],
                          ),
                        )
                      else if (snapshot.connectionState ==
                          ConnectionState.waiting)
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
                                subtitle:
                                    'Trending choices from live inventory',
                                items: popularItems,
                              ),
                              const SizedBox(height: 24),
                              _buildProductSection(
                                title: 'Best Sellers',
                                subtitle:
                                    'Top performing products customers love',
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
                  color: const Color(0xFFF8F9FA),
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

  Widget _homeStoreStatusBanner() {
    final storeOpen = _homeDeliverySettings.isStoreOpenAt(DateTime.now());
    final available = _homeDeliverySettings.deliveryEnabled && storeOpen;
    final message = !_homeDeliverySettings.deliveryEnabled
        ? 'Delivery service is currently unavailable'
        : storeOpen
        ? 'Store is Open • Delivery in 20–30 mins'
        : 'Store is currently closed • Next delivery starts at ${_homeDeliverySettings.formattedOpeningTime}';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: available ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: available ? Colors.green.shade200 : Colors.orange.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            available ? Icons.check_circle_outline : Icons.schedule_outlined,
            size: 20,
            color: available ? Colors.green.shade700 : Colors.orange.shade800,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
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
                  color: selected
                      ? const Color(0xFFF8F9FA)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      icon,
                      color: selected
                          ? const Color(0xFFFFC107)
                          : const Color(0xFF424242),
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
                  color: selected
                      ? const Color(0xFFFFC107)
                      : const Color(0xFF424242),
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

class _SearchResultItem {
  final String collection;
  final String id;
  final GroceryItem product;
  final Map<String, dynamic> raw;

  const _SearchResultItem({
    required this.collection,
    required this.id,
    required this.product,
    required this.raw,
  });
}

class ProductDetailsPage extends StatefulWidget {
  const ProductDetailsPage({
    super.key,
    required this.product,
    required this.sourceCollection,
    required this.cartNotifier,
  });

  final GroceryItem product;
  final String sourceCollection;
  final ValueNotifier<List<CartItem>> cartNotifier;

  @override
  State<ProductDetailsPage> createState() => _ProductDetailsPageState();
}

class _ProductDetailsPageState extends State<ProductDetailsPage> {
  int _quantity = 1;

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

  GroceryItem _productFromDoc(Map<String, dynamic> data, {String? productId}) {
    final name = data['name']?.toString() ?? 'Product';
    final category = data['category']?.toString() ?? 'General';
    final stock = (data['stock'] as num?)?.toInt() ?? 999;
    final imageUrl = _extractProductImageUrl(data);
    final priceValue = double.tryParse(data['price']?.toString() ?? '');
    final oldPriceValue = double.tryParse(data['oldPrice']?.toString() ?? '');
    final validOldPrice =
        oldPriceValue != null &&
            priceValue != null &&
            oldPriceValue > priceValue
        ? oldPriceValue
        : null;
    final discountFromField = double.tryParse(
      data['discount']?.toString() ?? '',
    );
    final discountPercent = discountFromField != null && discountFromField > 0
        ? discountFromField.round()
        : (validOldPrice != null && priceValue != null && priceValue > 0
              ? (((validOldPrice - priceValue) / validOldPrice) * 100).round()
              : 0);

    return GroceryItem(
      productId: productId,
      name: name,
      price: _priceText(data['price']),
      unit: '1 item',
      emoji: '🛍️',
      tag: category,
      accent: categoryThemeFor(canonicalCategory(category)).primary,
      stock: stock,
      imageUrl: imageUrl,
      brand: data['brand']?.toString() ?? '',
      weight: data['weight']?.toString() ?? '',
      measureUnit: data['unit']?.toString() ?? '',
      oldPrice: validOldPrice,
      discountPercent: discountPercent,
      shortDescription: data['shortDescription']?.toString() ?? '',
    );
  }

  int _unitPrice() => parsePrice(widget.product.price);

  int _effectiveMaxQuantity() {
    if (widget.product.stock <= 0) {
      return 1;
    }
    return widget.product.stock;
  }

  void _changeQuantity(int delta) {
    setState(() {
      final next = (_quantity + delta).clamp(1, _effectiveMaxQuantity());
      _quantity = next;
    });
  }

  void _addToCartSelectedQuantity() {
    if (widget.product.stock <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This product is out of stock')),
      );
      return;
    }

    final currentCart = List<CartItem>.from(widget.cartNotifier.value);
    final existingIndex = currentCart.indexWhere(
      (entry) =>
          (entry.product.productId != null &&
              widget.product.productId != null &&
              entry.product.productId == widget.product.productId) ||
          entry.product.name == widget.product.name,
    );

    if (existingIndex >= 0) {
      final maxQuantity = widget.product.stock <= 0
          ? currentCart[existingIndex].quantity
          : widget.product.stock;
      currentCart[existingIndex].quantity =
          (currentCart[existingIndex].quantity + _quantity).clamp(
            1,
            maxQuantity,
          );
    } else {
      currentCart.add(CartItem(product: widget.product, quantity: _quantity));
    }

    widget.cartNotifier.value = currentCart;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${widget.product.name} added to cart')),
    );
  }

  void _buyNow() {
    _addToCartSelectedQuantity();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CartPage(cartNotifier: widget.cartNotifier),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final categoryTheme = categoryThemeFor(canonicalCategory(product.tag));
    final outOfStock = product.stock <= 0;
    final lowStock = !outOfStock && product.stock <= 5;
    final stockText = outOfStock
        ? 'Out of stock'
        : lowStock
        ? 'Low stock: ${product.stock} left'
        : 'In stock: ${product.stock}';
    final stockColor = outOfStock
        ? Colors.red.shade700
        : lowStock
        ? Colors.orange.shade700
        : Colors.green.shade700;
    final weightUnitText = [
      product.weight,
      product.measureUnit,
    ].where((part) => part.trim().isNotEmpty).join(' ');
    final total = _unitPrice() * _quantity;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Details'),
        backgroundColor: categoryTheme.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: categoryTheme.primary.withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: product.imageUrl.isNotEmpty
                    ? Image.network(
                        product.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return ColoredBox(
                            color: categoryTheme.background,
                            child: Icon(
                              Icons.shopping_bag_outlined,
                              size: 56,
                              color: categoryTheme.primary,
                            ),
                          );
                        },
                      )
                    : ColoredBox(
                        color: categoryTheme.background,
                        child: Icon(
                          Icons.shopping_bag_outlined,
                          size: 56,
                          color: categoryTheme.primary,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        product.name,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF212121),
                        ),
                      ),
                    ),
                    if (product.discountPercent > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE84141),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${product.discountPercent}% OFF',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: categoryTheme.background,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        product.tag,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: categoryTheme.primary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: stockColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        stockText,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: stockColor,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      product.price,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: categoryTheme.primary,
                      ),
                    ),
                    if (product.oldPrice != null) ...[
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '₹${product.oldPrice!.toStringAsFixed(product.oldPrice! % 1 == 0 ? 0 : 2)}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                            decoration: TextDecoration.lineThrough,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                if (product.brand.trim().isNotEmpty)
                  Text(
                    'Brand: ${product.brand}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF4B5563),
                    ),
                  ),
                if (weightUnitText.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Weight: $weightUnitText',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF4B5563),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  product.shortDescription.trim().isEmpty
                      ? 'No description available.'
                      : product.shortDescription,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Quantity',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed: _quantity > 1
                          ? () => _changeQuantity(-1)
                          : null,
                      icon: const Icon(Icons.remove),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '$_quantity',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filledTonal(
                      onPressed:
                          outOfStock || _quantity >= _effectiveMaxQuantity()
                          ? null
                          : () => _changeQuantity(1),
                      icon: const Icon(Icons.add),
                    ),
                    const Spacer(),
                    Text(
                      'Total: ₹$total',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: categoryTheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: outOfStock
                            ? null
                            : _addToCartSelectedQuantity,
                        style: FilledButton.styleFrom(
                          backgroundColor: outOfStock
                              ? Colors.grey.shade400
                              : categoryTheme.primary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.add_shopping_cart_rounded),
                        label: const Text('Add to Cart'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: outOfStock ? null : _buyNow,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: outOfStock
                              ? Colors.grey.shade500
                              : categoryTheme.primary,
                          side: BorderSide(
                            color: outOfStock
                                ? Colors.grey.shade300
                                : categoryTheme.primary,
                          ),
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.flash_on_rounded),
                        label: const Text('Buy Now'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Related Products',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF212121),
            ),
          ),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('products')
                .where('category', isEqualTo: product.tag)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final docs =
                  snapshot.data?.docs
                      .where(
                        (doc) =>
                            (doc.id != product.productId) &&
                            ((doc.data()['name']?.toString() ?? '') !=
                                product.name),
                      )
                      .toList() ??
                  const [];

              if (docs.isEmpty) {
                return const Text(
                  'No related products right now.',
                  style: TextStyle(color: Colors.black54),
                );
              }

              return SizedBox(
                height: 156,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: docs.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final related = _productFromDoc(
                      docs[index].data(),
                      productId: docs[index].id,
                    );
                    final relatedTheme = categoryThemeFor(
                      canonicalCategory(related.tag),
                    );

                    return SizedBox(
                      width: 140,
                      child: Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ProductDetailsPage(
                                  product: related,
                                  sourceCollection: widget.sourceCollection,
                                  cartNotifier: widget.cartNotifier,
                                ),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: relatedTheme.primary.withValues(
                                  alpha: 0.12,
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: related.imageUrl.isNotEmpty
                                        ? Image.network(
                                            related.imageUrl,
                                            width: double.infinity,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, _, _) =>
                                                ColoredBox(
                                                  color:
                                                      relatedTheme.background,
                                                  child: Icon(
                                                    Icons.shopping_bag_outlined,
                                                    color: relatedTheme.primary,
                                                  ),
                                                ),
                                          )
                                        : ColoredBox(
                                            color: relatedTheme.background,
                                            child: Icon(
                                              Icons.shopping_bag_outlined,
                                              color: relatedTheme.primary,
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  related.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  related.price,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: relatedTheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
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

class _CategoryProductCard extends StatelessWidget {
  const _CategoryProductCard({
    required this.item,
    required this.onAddToCart,
    required this.onOpenDetails,
  });

  final GroceryItem item;
  final VoidCallback onAddToCart;
  final VoidCallback onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final outOfStock = item.stock <= 0;
    final resolvedImageUrl = item.imageUrl;
    final weightUnitText = [
      item.weight,
      item.measureUnit,
    ].where((part) => part.trim().isNotEmpty).join(' ');
    final categoryTheme = categoryThemeFor(canonicalCategory(item.tag));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpenDetails,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: categoryTheme.primary.withValues(alpha: 0.13),
                blurRadius: 18,
                offset: const Offset(0, 7),
              ),
            ],
            border: Border.all(
              color: categoryTheme.primary.withValues(alpha: 0.12),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: categoryTheme.background,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        item.tag,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: categoryTheme.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.shopping_bag_outlined,
                    color: categoryTheme.primary,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              AspectRatio(
                aspectRatio: 1.30,
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: resolvedImageUrl.isNotEmpty
                          ? Image.network(
                              resolvedImageUrl,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: categoryTheme.background,
                                  alignment: Alignment.center,
                                  child: Icon(
                                    Icons.shopping_bag_outlined,
                                    color: categoryTheme.primary,
                                    size: 34,
                                  ),
                                );
                              },
                            )
                          : Container(
                              color: categoryTheme.background,
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.shopping_bag_outlined,
                                color: categoryTheme.primary,
                                size: 34,
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
              const SizedBox(height: 10),
              if (item.brand.trim().isNotEmpty)
                Text(
                  item.brand,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF212121),
                  ),
                ),
              Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF212121),
                ),
              ),
              if (weightUnitText.isNotEmpty)
                Text(
                  weightUnitText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF212121),
                  ),
                ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    item.price,
                    style: TextStyle(
                      color: categoryTheme.primary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
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
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
              if (item.shortDescription.trim().isNotEmpty)
                Text(
                  item.shortDescription,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF212121),
                  ),
                ),
              const SizedBox(height: 2),
              Text(
                outOfStock ? 'Out of Stock' : 'Stock: ${item.stock}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: outOfStock
                      ? Colors.red.shade700
                      : Colors.green.shade700,
                  fontSize: 11,
                  fontWeight: outOfStock ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 46,
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: outOfStock ? null : onAddToCart,
                  icon: const Icon(Icons.add_shopping_cart, size: 16),
                  label: Text(outOfStock ? 'Out of Stock' : 'Add to Cart'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: categoryTheme.primary,
                    disabledBackgroundColor: Colors.grey.shade400,
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

  Color _categoryPageThemeColor() {
    final keys = <String>{
      widget.title.trim().toLowerCase(),
      widget.firestoreCategory.trim().toLowerCase(),
    };

    if (keys.contains('grocery')) {
      return const Color(0xFFFFF3B0);
    }
    if (keys.contains('vegetables') || keys.contains('vegetable')) {
      return const Color(0xFFD9F7BE);
    }
    if (keys.contains('fruits') || keys.contains('fruit')) {
      return const Color(0xFFFFE5D0);
    }
    if (keys.contains('food')) {
      return const Color(0xFFFFE4E6);
    }
    if (keys.contains('gifts') || keys.contains('gift')) {
      return const Color(0xFFF3E8FF);
    }
    if (keys.contains('gifts & surprises') ||
        keys.contains('gift & surprises')) {
      return const Color(0xFFE0F2FE);
    }
    if (keys.contains('cosmetics')) {
      return const Color(0xFFFCE7F3);
    }
    if (keys.contains('electronics')) {
      return const Color(0xFFE0E7FF);
    }
    if (keys.contains('home service')) {
      return const Color(0xFFFEF3C7);
    }
    if (keys.contains('courier') ||
        keys.contains('parcel delivery') ||
        keys.contains('local parcel') ||
        keys.contains('delivery')) {
      return const Color(0xFFDBEAFE);
    }

    return const Color(0xFFF3F4F6);
  }

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
    return categoryThemeFor(canonicalCategory(category)).primary;
  }

  GroceryItem _productFromDoc(Map<String, dynamic> data, {String? productId}) {
    final name = data['name']?.toString() ?? 'Product';
    final category = data['category']?.toString() ?? 'General';
    final stock = (data['stock'] as num?)?.toInt() ?? 999;
    final imageUrl = _extractProductImageUrl(data);
    final priceValue = double.tryParse(data['price']?.toString() ?? '');
    final oldPriceValue = double.tryParse(data['oldPrice']?.toString() ?? '');
    final validOldPrice =
        oldPriceValue != null &&
            priceValue != null &&
            oldPriceValue > priceValue
        ? oldPriceValue
        : null;
    final discountFromField = double.tryParse(
      data['discount']?.toString() ?? '',
    );
    final discountPercent = discountFromField != null && discountFromField > 0
        ? discountFromField.round()
        : (validOldPrice != null && priceValue != null && priceValue > 0
              ? (((validOldPrice - priceValue) / validOldPrice) * 100).round()
              : 0);

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
      brand: data['brand']?.toString() ?? '',
      weight: data['weight']?.toString() ?? '',
      measureUnit: data['unit']?.toString() ?? '',
      oldPrice: validOldPrice,
      discountPercent: discountPercent,
      shortDescription: data['shortDescription']?.toString() ?? '',
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
      cartLog(
        'Category cart size after add: ${widget.cartNotifier.value.length}',
      );

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

  @override
  Widget build(BuildContext context) {
    final categoryTheme = categoryThemeFor(widget.title);
    final categoryPageColor = _categoryPageThemeColor();
    final childCategories = buildChildCategoryOptions(_selectedSubcategory);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final crossAxisCount = screenWidth > 700 ? 3 : 2;
    final categoryCardAspectRatio = crossAxisCount == 3 ? 0.58 : 0.50;
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
          final fallbackDocs = shouldUseFallbackProducts(
            docs.map((doc) => doc.data()),
            firestoreCategory: widget.firestoreCategory,
          )
              ? docs.toList()
              : null;
          final resolvedDocs = filteredDocs.isEmpty && fallbackDocs != null
              ? fallbackDocs
              : filteredDocs;

          final tabContent = Container(
            width: double.infinity,
            color: categoryTheme.background,
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
                                  ? categoryPageColor
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: categoryPageColor.withValues(
                                  alpha: 0.25,
                                ),
                              ),
                            ),
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              style: TextStyle(
                                color: _selectedSubcategory == null
                                    ? const Color(0xFF1F2937)
                                    : const Color(0xFF374151),
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
                                    ? categoryPageColor
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: categoryPageColor.withValues(
                                    alpha: 0.25,
                                  ),
                                ),
                              ),
                              child: AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                style: TextStyle(
                                  color: _selectedSubcategory == name
                                      ? const Color(0xFF1F2937)
                                      : const Color(0xFF374151),
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
                            color: categoryTheme.primary,
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
                                      ? categoryPageColor
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: categoryPageColor.withValues(
                                      alpha: 0.25,
                                    ),
                                  ),
                                ),
                                child: AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOutCubic,
                                  style: TextStyle(
                                    color: _selectedChildCategory == null
                                        ? const Color(0xFF1F2937)
                                        : const Color(0xFF374151),
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
                                        ? categoryPageColor
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: categoryPageColor.withValues(
                                        alpha: 0.25,
                                      ),
                                    ),
                                  ),
                                  child: AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 220),
                                    curve: Curves.easeOutCubic,
                                    style: TextStyle(
                                      color: _selectedChildCategory == name
                                          ? const Color(0xFF1F2937)
                                          : const Color(0xFF374151),
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
                backgroundColor: categoryPageColor,
                foregroundColor: const Color(0xFF1F2937),
                automaticallyImplyLeading: true,
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _PinnedCategoryHeaderDelegate(
                  child: tabContent,
                  minHeight:
                      availableSubcategories.isEmpty && childCategories.isEmpty
                      ? 0
                      : headerHeight,
                  maxHeight:
                      availableSubcategories.isEmpty && childCategories.isEmpty
                      ? 0
                      : headerHeight,
                ),
              ),
              if (resolvedDocs.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 24,
                    ),
                    child: Text(
                      'No products available in ${widget.title}${_selectedSubcategory == null ? '' : ' / $_selectedSubcategory'}${_selectedChildCategory == null ? '' : ' / $_selectedChildCategory'} right now.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: 3.2,
                      crossAxisSpacing: 12,
                      childAspectRatio: categoryCardAspectRatio,
                    ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final doc = resolvedDocs[index];
                      final item = _productFromDoc(
                        doc.data(),
                        productId: doc.id,
                      );
                      return _CategoryProductCard(
                        item: item,
                        onAddToCart: () => _addToCart(item),
                        onOpenDetails: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProductDetailsPage(
                                product: item,
                                sourceCollection: 'products',
                                cartNotifier: widget.cartNotifier,
                              ),
                            ),
                          );
                        },
                      );
                    }, childCount: resolvedDocs.length),
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
      accent: groceryCategoryTheme.primary,
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
      accent: foodCategoryTheme.primary,
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
      accent: giftsCategoryTheme.primary,
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
      accent: cosmeticsCategoryTheme.primary,
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
      accent: electronicsCategoryTheme.primary,
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
          accent: const Color(0xFFFFC107),
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
          accent: const Color(0xFFFFC107),
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
          accent: const Color(0xFFFFC107),
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
          accent: const Color(0xFFFFC107),
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
      ScaffoldMessenger.of(context).showSnackBar(
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
    const categoryTheme = giftsSurprisesCategoryTheme;
    const categoryPageColor = Color(0xFFE0F2FE);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gifts & Surprises'),
        backgroundColor: categoryPageColor,
        foregroundColor: Color(0xFF1F2937),
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
                color: categoryTheme.background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: categoryTheme.primary.withValues(alpha: 0.25),
                ),
              ),
              child: const Text(
                'Surprise your loved ones',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF212121),
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
                      selectedColor: categoryPageColor,
                      onSelected: (_) {
                        setState(() {
                          _selectedSection = section;
                        });
                      },
                      labelStyle: TextStyle(
                        color: categoryTheme.primary,
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
                          : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ProductDetailsPage(
                                    product: item,
                                    sourceCollection: 'products',
                                    cartNotifier: widget.cartNotifier,
                                  ),
                                ),
                              );
                            },
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
                                  color: categoryTheme.primary,
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
                                          color: categoryTheme.background,
                                          alignment: Alignment.center,
                                          child: Icon(
                                            Icons.shopping_bag_outlined,
                                            color: categoryTheme.primary,
                                            size: 30,
                                          ),
                                        );
                                      },
                                    )
                                  : Container(
                                      height: 180,
                                      width: double.infinity,
                                      color: categoryTheme.background,
                                      alignment: Alignment.center,
                                      child: Icon(
                                        Icons.shopping_bag_outlined,
                                        color: categoryTheme.primary,
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
                                  backgroundColor: categoryTheme.primary,
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
              activeThumbColor: categoryTheme.primary,
              onChanged: (value) => setState(() => _giftWrapping = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Greeting Card'),
              value: _greetingCard,
              activeThumbColor: categoryTheme.primary,
              onChanged: (value) => setState(() => _greetingCard = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Handwritten Message'),
              value: _handwrittenMessage,
              activeThumbColor: categoryTheme.primary,
              onChanged: (value) => setState(() => _handwrittenMessage = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Secret Surprise Delivery'),
              value: _secretSurpriseDelivery,
              activeThumbColor: categoryTheme.primary,
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
                border: Border.all(
                  color: categoryTheme.primary.withValues(alpha: 0.25),
                ),
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
                            selectedColor: categoryPageColor,
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
                        backgroundColor: categoryTheme.primary,
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
        backgroundColor: const Color(0xFFFFC107),
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
                    color: const Color(0xFFFFC107),
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

          void addRecommendedToCart(GroceryItem product) {
            final updated = List<CartItem>.from(items);
            final existingIndex = updated.indexWhere(
              (entry) => entry.product.productId == product.productId,
            );

            if (existingIndex >= 0) {
              updated[existingIndex].quantity += 1;
            } else {
              updated.add(CartItem(product: product, quantity: 1));
            }

            cartNotifier.value = updated;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${product.name} added to cart')),
            );
          }

          return Column(
            children: [
              Expanded(
                child: Column(
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
                                  backgroundColor: entry.product.accent
                                      .withValues(alpha: 0.15),
                                  child: Text(
                                    entry.product.emoji,
                                    style: const TextStyle(fontSize: 22),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                        style: const TextStyle(
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      onPressed: () {
                                        final updated = List<CartItem>.from(
                                          items,
                                        );
                                        if (updated[index].quantity > 1) {
                                          updated[index].quantity -= 1;
                                        } else {
                                          updated.removeAt(index);
                                        }
                                        cartNotifier.value = updated;
                                      },
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                      ),
                                    ),
                                    Text(
                                      '${entry.quantity}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () {
                                        final updated = List<CartItem>.from(
                                          items,
                                        );
                                        updated[index].quantity += 1;
                                        cartNotifier.value = updated;
                                      },
                                      icon: const Icon(
                                        Icons.add_circle_outline,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    _RelatedProductsSection(
                      cartItems: items,
                      onAdd: addRecommendedToCart,
                    ),
                  ],
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
                          backgroundColor: const Color(0xFFFFC107),
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

class _RelatedProductsSection extends StatelessWidget {
  const _RelatedProductsSection({required this.cartItems, required this.onAdd});

  final List<CartItem> cartItems;
  final ValueChanged<GroceryItem> onAdd;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('products').snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];
        final recommendations = _buildRecommendations(docs, cartItems);

        if (recommendations.isEmpty) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '🛍️ Frequently Bought Together',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 198,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: recommendations.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final item = recommendations[index];
                    return _RelatedProductCard(
                      item: item,
                      onAdd: () => onAdd(item),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<GroceryItem> _buildRecommendations(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    List<CartItem> currentCart,
  ) {
    final cartIds = currentCart
        .map((entry) => entry.product.productId)
        .whereType<String>()
        .where((id) => id.trim().isNotEmpty)
        .toSet();
    final cartNames = currentCart
        .map((entry) => _normalize(entry.product.name))
        .where((name) => name.isNotEmpty)
        .toSet();
    final cartCategories = currentCart
        .map((entry) => _normalize(entry.product.tag))
        .where((category) => category.isNotEmpty)
        .toSet();

    final buckets = <_ScoredProduct>[];

    for (final doc in docs) {
      final data = doc.data();
      final productId = doc.id;
      final name = (data['name'] ?? '').toString().trim();
      if (name.isEmpty) {
        continue;
      }
      if (cartIds.contains(productId) || cartNames.contains(_normalize(name))) {
        continue;
      }

      final stock = _toInt(data['stock'], fallback: 999);
      if (stock <= 0) {
        continue;
      }

      final category = _normalize(
        (data['category'] ?? data['mainCategory'] ?? data['tag'] ?? '')
            .toString(),
      );
      final sameCategory =
          category.isNotEmpty && cartCategories.contains(category);

      final popularity =
          _toInt(data['popularity']) +
          _toInt(data['orderCount']) +
          _toInt(data['soldCount']) +
          _toInt(data['views']);

      buckets.add(
        _ScoredProduct(
          item: GroceryItem(
            productId: productId,
            name: name,
            price: _priceLabel(data['price']),
            unit: (data['measureUnit'] ?? data['unit'] ?? '1 pc').toString(),
            emoji: (data['emoji'] ?? '🛍️').toString(),
            tag: (data['category'] ?? '').toString(),
            accent: const Color(0xFFFFC107),
            stock: stock,
            imageUrl: extractProductImageUrl(data),
            brand: (data['brand'] ?? '').toString(),
            weight: (data['weight'] ?? '').toString(),
            measureUnit: (data['measureUnit'] ?? '').toString(),
          ),
          sameCategory: sameCategory,
          popularity: popularity,
        ),
      );
    }

    buckets.sort((a, b) {
      if (a.sameCategory != b.sameCategory) {
        return a.sameCategory ? -1 : 1;
      }
      return b.popularity.compareTo(a.popularity);
    });

    return buckets.map((entry) => entry.item).take(10).toList();
  }

  int _toInt(Object? value, {int fallback = 0}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  String _normalize(String value) {
    return value.trim().toLowerCase();
  }

  String _priceLabel(Object? rawPrice) {
    final raw = rawPrice?.toString().trim() ?? '';
    if (raw.isEmpty) {
      return '₹0';
    }
    if (raw.contains('₹')) {
      return raw;
    }
    return '₹$raw';
  }
}

class _RelatedProductCard extends StatelessWidget {
  const _RelatedProductCard({required this.item, required this.onAdd});

  final GroceryItem item;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 152,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: item.imageUrl.isNotEmpty
                  ? Image.network(
                      item.imageUrl,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _fallbackImage(item),
                    )
                  : _fallbackImage(item),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.price,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 30,
            child: ElevatedButton(
              onPressed: onAdd,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                '+ Add',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallbackImage(GroceryItem product) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF8E1),
      alignment: Alignment.center,
      child: Text(product.emoji, style: const TextStyle(fontSize: 30)),
    );
  }
}

class _ScoredProduct {
  const _ScoredProduct({
    required this.item,
    required this.sameCategory,
    required this.popularity,
  });

  final GroceryItem item;
  final bool sameCategory;
  final int popularity;
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
  DeliverySettingsService? _deliverySettingsService;
  StreamSubscription<DeliverySettings>? _deliverySettingsSubscription;
  DeliverySettings _deliverySettings = const DeliverySettings();
  bool _settingsLoaded = false;
  String _paymentMethod = _paymentMethodCod;
  bool _isPlacingOrder = false;
  String? _sessionPhone;
  late final Razorpay _razorpay;
  int? _pendingOnlineTotal;
  DeliverySettings? _pendingOnlineSettings;
  LatLng? _selectedDeliveryLocation;
  String? _selectedDeliveryAddress;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
    if (Firebase.apps.isNotEmpty) {
      _deliverySettingsService = DeliverySettingsService();
      _deliverySettingsSubscription = _deliverySettingsService!.watch().listen(
        (settings) {
          if (mounted) {
            setState(() {
              _deliverySettings = settings;
              _settingsLoaded = true;
            });
          }
        },
        onError: (_) {
          if (mounted) setState(() => _settingsLoaded = true);
        },
      );
    }
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
    return _deliverySettings.chargeFor(widget.subtotal.toDouble()).round();
  }

  Future<DeliverySettings?> _validatedDeliverySettings() async {
    final service = _deliverySettingsService;
    if (service == null) {
      _showCheckoutMessage(
        'Delivery settings are unavailable. Please try again.',
      );
      return null;
    }

    try {
      final settings = await service.getLatest();
      if (!settings.deliveryEnabled) {
        _showCheckoutMessage('Delivery service is currently unavailable.');
        return null;
      }
      if (!settings.isStoreOpenAt(DateTime.now())) {
        _showCheckoutMessage(
          'Store is currently closed. Next delivery starts at ${settings.formattedOpeningTime}.',
        );
        return null;
      }
      if (!settings.hasHubLocation) {
        _showCheckoutMessage(
          'Delivery location is not configured yet. Please try again later.',
        );
        return null;
      }

      final location = _selectedDeliveryLocation;
      if (location == null) {
        _showCheckoutMessage(
          'Select your delivery location on the map to continue.',
        );
        return null;
      }
      if (!settings.containsLocation(location.latitude, location.longitude)) {
        _showCheckoutMessage(
          'Sorry, we currently deliver within ${_formatNumber(settings.deliveryRadiusKm)} km of our store.',
        );
        return null;
      }
      return settings;
    } on FirebaseException catch (error) {
      _showCheckoutMessage(
        error.message ?? 'Could not verify delivery availability.',
      );
      return null;
    } on TimeoutException {
      _showCheckoutMessage(
        'Delivery verification timed out. Please try again.',
      );
      return null;
    }
  }

  void _showCheckoutMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatNumber(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(1);
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
    required DeliverySettings deliverySettings,
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

    final deliveryCharge = deliverySettings
        .chargeFor(widget.subtotal.toDouble())
        .round();
    final checkoutName = _nameController.text.trim();
    final checkoutPhone = _phoneController.text.trim();
    final checkoutAddress = _addressController.text.trim();

    double amountValue(dynamic value) {
      if (value is num) {
        return value.toDouble();
      }
      return double.tryParse(
            value?.toString().replaceAll(RegExp(r'[^0-9.-]'), '') ?? '',
          ) ??
          0;
    }

    final productsRef = FirebaseFirestore.instance.collection('products');
    final orderItems = await Future.wait(
      items.map((item) async {
        final product = item.product;
        Map<String, dynamic> productData = const {};
        final productId = product.productId?.trim() ?? '';

        if (productId.isNotEmpty) {
          final productSnapshot = await productsRef.doc(productId).get();
          productData = productSnapshot.data() ?? const {};
        }

        final price = amountValue(product.price);
        final oldPrice = amountValue(
          productData['oldPrice'] ?? product.oldPrice,
        );
        final discountPercent = amountValue(
          productData['discount'] ?? product.discountPercent,
        );

        return <String, dynamic>{
          'productId': productId,
          'name': product.name,
          'image': product.imageUrl.isNotEmpty
              ? product.imageUrl
              : productData['imageUrl']?.toString() ?? '',
          'brand': productData['brand']?.toString() ?? product.brand,
          'weight': productData['weight']?.toString() ?? product.weight,
          'unit': productData['unit']?.toString() ?? product.measureUnit,
          'shortDescription':
              productData['shortDescription']?.toString() ??
              product.shortDescription,
          'price': price,
          'oldPrice': oldPrice,
          'discountPercent': discountPercent,
          'quantity': item.quantity,
          'itemTotal': price * item.quantity,
        };
      }),
    );

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
      'items': orderItems,
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

  Future<void> _startOnlinePayment(
    int total,
    DeliverySettings deliverySettings,
  ) async {
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
    _pendingOnlineSettings = deliverySettings;
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
    final deliverySettings = _pendingOnlineSettings;
    if (total == null || deliverySettings == null) {
      _setPlacingOrder(false);
      return;
    }

    try {
      final order = await _buildOrderForCheckout(
        total,
        deliverySettings: deliverySettings,
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
    _pendingOnlineSettings = null;

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
    _pendingOnlineSettings = null;
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

  Future<void> _handlePrimaryCheckoutAction() async {
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

    final deliverySettings = await _validatedDeliverySettings();
    if (deliverySettings == null) return;
    final deliveryCharge = deliverySettings
        .chargeFor(widget.subtotal.toDouble())
        .round();
    final total = widget.subtotal + deliveryCharge;

    if (_paymentMethod == _paymentMethodOnline) {
      _setPlacingOrder(true);
      try {
        await _startOnlinePayment(total, deliverySettings);
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
        deliverySettings: deliverySettings,
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
    _deliverySettingsSubscription?.cancel();
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
    final storeOpen = _deliverySettings.isStoreOpenAt(DateTime.now());
    final orderingAvailable =
        _settingsLoaded && _deliverySettings.deliveryEnabled && storeOpen;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout'),
        backgroundColor: const Color(0xFFFFC107),
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: orderingAvailable
                      ? Colors.green.shade50
                      : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: orderingAvailable
                        ? Colors.green.shade200
                        : Colors.orange.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      orderingAvailable
                          ? Icons.check_circle_outline
                          : Icons.schedule_outlined,
                      color: orderingAvailable
                          ? Colors.green.shade700
                          : Colors.orange.shade800,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        !_settingsLoaded
                            ? 'Checking delivery availability...'
                            : !_deliverySettings.deliveryEnabled
                            ? 'Delivery service is currently unavailable.'
                            : storeOpen
                            ? 'Store is Open • Delivery in 20–30 mins'
                            : 'Store is currently closed\nNext delivery starts at ${_deliverySettings.formattedOpeningTime}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
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
                style: TextStyle(color: const Color(0xFFFFC107), fontSize: 12),
              ),
              if (_selectedDeliveryLocation != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Lat: ${_selectedDeliveryLocation!.latitude.toStringAsFixed(6)}, Lng: ${_selectedDeliveryLocation!.longitude.toStringAsFixed(6)}',
                  style: TextStyle(
                    color: const Color(0xFFFFC107),
                    fontSize: 12,
                  ),
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
                  border: Border.all(color: const Color(0xFFF8F9FA)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _paymentMethod,
                    isExpanded: true,
                    icon: Icon(
                      Icons.keyboard_arrow_down,
                      color: const Color(0xFFFFC107),
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
                  style: TextStyle(
                    color: const Color(0xFFFFC107),
                    fontSize: 12,
                  ),
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
                  color: const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFF8F9FA)),
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
                  onPressed: _isPlacingOrder || !orderingAvailable
                      ? null
                      : () async {
                          await _handlePrimaryCheckoutAction();
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFC107),
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
      prefixIcon: Icon(icon, color: const Color(0xFFFFC107)),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: const Color(0xFFF8F9FA)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: const Color(0xFFF8F9FA)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: const Color(0xFFFFC107), width: 1.4),
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
                  color: const Color(0xFFF8F9FA),
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
                    color: const Color(0xFFF8F9FA),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    color: Color(0xFF2E7D32),
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
                    backgroundColor: const Color(0xFF2E7D32),
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
        backgroundColor: const Color(0xFFFFC107),
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
                    color: const Color(0xFFF8F9FA),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 42,
                    backgroundColor: const Color(0xFFF8F9FA),
                    child: Icon(
                      Icons.person,
                      size: 40,
                      color: const Color(0xFFFFC107),
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
                        backgroundColor: const Color(0xFFFFC107),
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
                  foregroundColor: const Color(0xFFFFC107),
                  side: BorderSide(color: const Color(0xFFFFECB3)),
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
        selectedItemColor: const Color(0xFFFFC107),
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
        leading: Icon(icon, color: const Color(0xFFFFC107)),
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
        backgroundColor: const Color(0xFFFFC107),
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
                color: const Color(0xFFF8F9FA),
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
                  color: const Color(0xFFFFC107),
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
          Icon(icon, color: const Color(0xFFFFC107), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF212121),
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
        backgroundColor: const Color(0xFFFFC107),
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
            stream: FirebaseFirestore.instance.collection('orders').snapshots(),
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
                .where((doc) => orderMatchesSessionPhone(doc.data(), sessionPhone))
                .toList()
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
                        color: const Color(0xFFFFC107),
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

  AppBar _orderDetailsAppBar() {
    return AppBar(
      title: const Text(
        'Order Details',
        style: TextStyle(color: Color(0xFF222222), fontWeight: FontWeight.w700),
      ),
      backgroundColor: Colors.white,
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      iconTheme: const IconThemeData(color: Color(0xFFFFC107)),
    );
  }

  ({Color bg, Color fg}) _statusBadgePalette(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return (bg: const Color(0xFFFFF4CC), fg: const Color(0xFFA37400));
      case OrderStatus.accepted:
        return (bg: const Color(0xFFE5F0FF), fg: const Color(0xFF2F67D6));
      case OrderStatus.packed:
        return (bg: const Color(0xFFF2E8FF), fg: const Color(0xFF7E57C2));
      case OrderStatus.outForDelivery:
        return (bg: const Color(0xFFFFE9D6), fg: const Color(0xFFEF6C00));
      case OrderStatus.delivered:
        return (bg: const Color(0xFFE5F6EA), fg: const Color(0xFF2E7D32));
      case OrderStatus.cancelled:
        return (bg: const Color(0xFFFCE8E8), fg: const Color(0xFFC62828));
    }
  }

  Widget _surfaceCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEEEEEE)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String title,
    required List<Widget> content,
  }) {
    return _surfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFFFFC107), size: 22),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF222222),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...content,
        ],
      ),
    );
  }

  Widget _statusSummaryCard(OrderStatus status) {
    final displayStatus = status == OrderStatus.cancelled
        ? 'Order Cancelled'
        : status.label;
    final palette = _statusBadgePalette(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_orderStatusIcon(status), size: 16, color: palette.fg),
          const SizedBox(width: 6),
          Text(
            displayStatus,
            style: TextStyle(
              color: palette.fg,
              fontWeight: FontWeight.w700,
              fontSize: 12,
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

    return _surfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order Progress',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF222222),
            ),
          ),
          const SizedBox(height: 16),
          for (int index = 0; index < _orderProgressStages.length; index++)
            Padding(
              padding: EdgeInsets.only(
                bottom: index == _orderProgressStages.length - 1 ? 0 : 16,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 34,
                    child: Column(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: index <= currentIndex
                                ? const Color(0xFFFFC107)
                                : const Color(0xFFE0E0E0),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _orderStatusIcon(_orderProgressStages[index]),
                            size: 18,
                            color: index <= currentIndex
                                ? Colors.white
                                : const Color(0xFF9E9E9E),
                          ),
                        ),
                        if (index < _orderProgressStages.length - 1)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 420),
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            width: 3,
                            height: 36,
                            decoration: BoxDecoration(
                              color: index < currentIndex
                                  ? const Color(0xFFFFC107)
                                  : const Color(0xFFE0E0E0),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _orderProgressStages[index].label,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: index <= currentIndex
                                  ? const Color(0xFF222222)
                                  : const Color(0xFF9E9E9E),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            index < currentIndex
                                ? 'Completed'
                                : index == currentIndex
                                ? 'Current status'
                                : 'Pending',
                            style: TextStyle(
                              fontSize: 12,
                              color: index <= currentIndex
                                  ? const Color(0xFF757575)
                                  : const Color(0xFFB0B0B0),
                            ),
                          ),
                        ],
                      ),
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
      appBar: _orderDetailsAppBar(),
      backgroundColor: const Color(0xFFFAFAFA),
      body: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, 10 * (1 - value)),
              child: child,
            ),
          );
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _surfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Order ID',
                                style: TextStyle(
                                  color: Color(0xFF757575),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                orderIdValue,
                                style: const TextStyle(
                                  color: Color(0xFF222222),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _statusSummaryCard(orderStatus),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Divider(color: Color(0xFFEEEEEE), height: 1),
                    const SizedBox(height: 14),
                    const Text(
                      'Order Date & Time',
                      style: TextStyle(
                        color: Color(0xFF757575),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      orderDate,
                      style: const TextStyle(
                        color: Color(0xFF222222),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Total Amount',
                              style: TextStyle(
                                color: Color(0xFF757575),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '₹$totalAmount',
                              style: const TextStyle(
                                color: Color(0xFF222222),
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              'Payment Method',
                              style: TextStyle(
                                color: Color(0xFF757575),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              paymentMethod,
                              style: const TextStyle(
                                color: Color(0xFF222222),
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _buildProgressTracker(orderStatus),
              const SizedBox(height: 18),
              _infoCard(
                icon: Icons.person_outline_rounded,
                title: 'Customer Information',
                content: [
                  Text(
                    customerName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF222222),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    phoneNumber,
                    style: const TextStyle(
                      color: Color(0xFF757575),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _infoCard(
                icon: Icons.location_on_outlined,
                title: 'Delivery Address',
                content: [
                  Text(
                    deliveryAddress,
                    style: const TextStyle(
                      color: Color(0xFF222222),
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _infoCard(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Payment',
                content: [
                  Text(
                    paymentMethod,
                    style: const TextStyle(
                      color: Color(0xFF222222),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7E1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFEEEEEE)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Order Total',
                      style: TextStyle(
                        color: Color(0xFF757575),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '₹$totalAmount',
                      style: const TextStyle(
                        fontSize: 32,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF222222),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 94),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: const Color(0xFFEEEEEE))),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.location_searching_rounded, size: 18),
                  label: const Text('Track Order'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF222222),
                    side: const BorderSide(color: Color(0xFFEEEEEE)),
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.support_agent_rounded, size: 18),
                  label: const Text('Contact Support'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF222222),
                    side: const BorderSide(color: Color(0xFFEEEEEE)),
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              if (orderStatus == OrderStatus.delivered ||
                  orderStatus == OrderStatus.cancelled) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Reorder'),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: const Color(0xFFFFC107),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
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
              appBar: _orderDetailsAppBar(),
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
              appBar: _orderDetailsAppBar(),
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
            appBar: _orderDetailsAppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final sessionPhone = phoneSnapshot.data?.trim() ?? '';
        if (sessionPhone.isEmpty) {
          return Scaffold(
            appBar: _orderDetailsAppBar(),
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
          stream: FirebaseFirestore.instance.collection('orders').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Scaffold(
                appBar: _orderDetailsAppBar(),
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
                appBar: _orderDetailsAppBar(),
                body: const Center(child: CircularProgressIndicator()),
              );
            }

            final matchingDocs = (snapshot.data?.docs ?? [])
                .where((doc) {
                  final data = doc.data();
                  return orderMatchesSessionPhone(data, sessionPhone) &&
                      (data['orderId']?.toString() ?? '') == (orderId ?? '');
                })
                .toList();
            final doc = matchingDocs.isNotEmpty ? matchingDocs.first : null;
            if (doc == null) {
              return Scaffold(
                appBar: _orderDetailsAppBar(),
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
                backgroundColor: const Color(0xFFFFC107),
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
        backgroundColor: const Color(0xFFFFC107),
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showProductDialog(),
        backgroundColor: const Color(0xFFFFC107),
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
                    color: const Color(0xFFFFC107),
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
                      color: const Color(0xFFF8F9FA),
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
                                  color: const Color(0xFFF8F9FA),
                                  child: const Icon(
                                    Icons.image_outlined,
                                    color: const Color(0xFFFFC107),
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
                                    color: const Color(0xFFF8F9FA),
                                    child: const Icon(
                                      Icons.broken_image_outlined,
                                      color: const Color(0xFFFFC107),
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
                                  color: const Color(0xFFFFC107),
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
