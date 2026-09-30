import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:developer' as developer;
import 'dart:async';
import 'auth_service.dart';
import 'login_page.dart';
import 'push_notification_service.dart';
import 'profile_page.dart';
import 'firebase_options.dart';
import 'notifications_screen.dart';
import 'screens/location_picker_screen.dart';
import 'screens/order_chat_page.dart';
import 'screens/shop_details_page.dart';
import 'category_routing.dart';
import 'category_theme.dart';
import 'splash_screen.dart';
import 'models/delivery_settings.dart';
import 'models/shop.dart';
import 'services/delivery_settings_service.dart';
import 'services/location_service.dart';
import 'services/shop_service.dart';
import 'firestore_query_helpers.dart';
import 'app_theme.dart';

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
  String? normalize(dynamic value) {
    if (value is Map) {
      for (final key in ['downloadURL', 'downloadUrl', 'url']) {
        final nested = normalize(value[key]);
        if (nested != null) {
          return nested;
        }
      }
      return null;
    }

    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) {
      return null;
    }

    if (text.startsWith('gs://')) {
      final reference = text.substring(5);
      final separator = reference.indexOf('/');
      if (separator <= 0 || separator == reference.length - 1) {
        return null;
      }
      final bucket = reference.substring(0, separator);
      final objectPath = reference.substring(separator + 1);
      return 'https://firebasestorage.googleapis.com/v0/b/$bucket/o/'
          '${Uri.encodeComponent(objectPath)}?alt=media';
    }

    final uri = Uri.tryParse(text);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    return text;
  }

  for (final key in [
    'imageUrl',
    'imageUrls',
    'image',
    'imageURL',
    'image_url',
  ]) {
    final value = data[key];
    if (value is List) {
      for (final item in value) {
        final url = normalize(item);
        if (url != null) {
          return url;
        }
      }
    } else {
      final url = normalize(value);
      if (url != null) {
        return url;
      }
    }
  }

  return '';
}

String extractProductImageUrl(Map<String, dynamic> data) =>
    _extractProductImageUrl(data);

final Set<String> _prefetchedProductImageUrls = <String>{};

void _prefetchProductImages(
  BuildContext context,
  Iterable<String> urls, {
  int limit = 8,
}) {
  final pending = <String>[];
  for (final rawUrl in urls) {
    final url = rawUrl.trim();
    if (url.isEmpty || !_prefetchedProductImageUrls.add(url)) {
      continue;
    }
    pending.add(url);
    if (pending.length == limit) {
      break;
    }
  }

  if (pending.isEmpty) {
    return;
  }

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) {
      return;
    }
    for (final url in pending) {
      precacheImage(
        CachedNetworkImageProvider(url, maxWidth: 720, maxHeight: 720),
        context,
      ).catchError((_) {});
    }
  });
}

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
  final String? shopId;
  final String shopNameSnapshot;
  final String shopAddressSnapshot;

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
    this.shopId,
    this.shopNameSnapshot = '',
    this.shopAddressSnapshot = '',
  });
}

class CartItem {
  final GroceryItem product;
  int quantity;

  CartItem({required this.product, required this.quantity});
}

int cartSubtotal(Iterable<CartItem> items) {
  return items.fold<int>(
    0,
    (totalPrice, item) =>
        totalPrice + (parsePrice(item.product.price) * item.quantity),
  );
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
  goingToStore,
  reachedStore,
  orderCollected,
  outForDelivery,
  delivered,
  rejected,
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
      case OrderStatus.goingToStore:
        return 'Rider Going to Store';
      case OrderStatus.reachedStore:
        return 'Rider Reached Store';
      case OrderStatus.orderCollected:
        return 'Order Collected';
      case OrderStatus.outForDelivery:
        return 'Out for Delivery';
      case OrderStatus.delivered:
        return 'Delivered';
      case OrderStatus.rejected:
        return 'Rejected';
      case OrderStatus.cancelled:
        return 'Cancelled';
    }
  }
}

const List<OrderStatus> _orderProgressStages = <OrderStatus>[
  OrderStatus.pending,
  OrderStatus.accepted,
  OrderStatus.goingToStore,
  OrderStatus.reachedStore,
  OrderStatus.orderCollected,
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
    case 'going to store':
    case 'going_to_store':
      return OrderStatus.goingToStore;
    case 'reached store':
    case 'reached_store':
      return OrderStatus.reachedStore;
    case 'order collected':
    case 'order_collected':
      return OrderStatus.orderCollected;
    case 'out for delivery':
    case 'outfordelivery':
    case 'out_for_delivery':
      return OrderStatus.outForDelivery;
    case 'delivered':
      return OrderStatus.delivered;
    case 'rejected':
      return OrderStatus.rejected;
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
      return QuickDropColors.offer;
    case OrderStatus.accepted:
      return QuickDropColors.primary;
    case OrderStatus.packed:
      return QuickDropColors.primaryDark;
    case OrderStatus.goingToStore:
    case OrderStatus.reachedStore:
    case OrderStatus.orderCollected:
      return QuickDropColors.primaryDark;
    case OrderStatus.outForDelivery:
      return QuickDropColors.primary;
    case OrderStatus.delivered:
      return QuickDropColors.primary;
    case OrderStatus.rejected:
      return const Color(0xFFB8544F);
    case OrderStatus.cancelled:
      return const Color(0xFFB8544F);
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
    case OrderStatus.goingToStore:
      return Icons.storefront_outlined;
    case OrderStatus.reachedStore:
      return Icons.location_on_outlined;
    case OrderStatus.orderCollected:
      return Icons.shopping_bag_outlined;
    case OrderStatus.outForDelivery:
      return Icons.local_shipping_outlined;
    case OrderStatus.delivered:
      return Icons.done_all_outlined;
    case OrderStatus.rejected:
      return Icons.cancel_outlined;
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
    await FirebaseAppCheck.instance.activate(
      providerAndroid: const AndroidDebugProvider(),
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

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: QuickDropColors.background,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );

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
      theme: quickDropTheme(),
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
            colors: [QuickDropColors.mint, QuickDropColors.background],
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
                  color: QuickDropColors.primary,
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
    with AutomaticKeepAliveClientMixin<HomePage>, WidgetsBindingObserver {
  static const bool _isFlutterTest = bool.fromEnvironment('FLUTTER_TEST');
  static const PageStorageKey<String> _homeScrollKey = PageStorageKey<String>(
    'home_page_scroll',
  );
  final AuthService _drawerAuthService = AuthService();
  final LocationService _locationService = const LocationService();
  final ShopService _shopService = ShopService();
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _homeScrollController = ScrollController();
  final PageController _bannerController = PageController(viewportFraction: 1);
  final PageController _popularBestSellerBannerController = PageController(
    viewportFraction: 1,
  );
  final ValueNotifier<int> _popularBestSellerBannerIndex = ValueNotifier<int>(
    0,
  );
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
  String _homeLocationAddress = 'Deliver to Agartala, Tripura';
  LatLng? _homeLocationPosition;
  bool _homeLocationLoadInProgress = false;
  bool _homeLocationResolved = false;
  bool _locationSettingsOpened = false;
  bool _isSearchingProducts = false;
  String? _searchProductsError;
  List<_SearchResultItem> _searchResults = const <_SearchResultItem>[];
  late final List<String> _productSearchCollections;
  late final Future<Map<String, dynamic>?> _drawerProfileFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _drawerProfileFuture = _drawerAuthService.loadCurrentUserProfile();
    _productSearchCollections = _buildProductSearchCollections();
    if (!_isFlutterTest) {
      unawaited(_loadHomeLocation());
    }
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

  Future<void> _loadHomeLocation() async {
    if (_homeLocationLoadInProgress || _homeLocationResolved) {
      return;
    }

    _homeLocationLoadInProgress = true;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!_locationSettingsOpened) {
          _locationSettingsOpened = true;
          await Geolocator.openLocationSettings();
        }
        return;
      }

      _locationSettingsOpened = false;
      final position = await _locationService.getCurrentPosition();
      _homeLocationPosition = LatLng(position.latitude, position.longitude);
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isEmpty || !mounted) {
        return;
      }

      final place = placemarks.first;
      final addressParts = _currentLocationAddressParts(place);
      if (addressParts.isEmpty) {
        return;
      }

      setState(() {
        _homeLocationAddress = 'Deliver to ${addressParts.join(', ')}';
        _homeLocationResolved = true;
      });
    } catch (error, stackTrace) {
      developer.log(
        'Home location detection failed: $error',
        name: 'QuickDropLocation',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _homeLocationLoadInProgress = false;
    }
  }

  Future<void> _openHomeLocationSearch() async {
    final pickedLocation = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) =>
            LocationPickerScreen(initialPosition: _homeLocationPosition),
      ),
    );

    if (!mounted || pickedLocation == null) {
      return;
    }

    try {
      final placemarks = await placemarkFromCoordinates(
        pickedLocation.latitude,
        pickedLocation.longitude,
      );
      if (!mounted || placemarks.isEmpty) {
        return;
      }

      final place = placemarks.first;
      final addressParts = _currentLocationAddressParts(place);
      if (addressParts.isEmpty) {
        return;
      }

      setState(() {
        _homeLocationPosition = pickedLocation;
        _homeLocationAddress = 'Deliver to ${addressParts.join(', ')}';
        _homeLocationResolved = true;
      });
    } catch (error, stackTrace) {
      developer.log(
        'Selected Home location address lookup failed: $error',
        name: 'QuickDropLocation',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  List<String> _currentLocationAddressParts(Placemark place) {
    final specificName = place.name?.trim() ?? '';
    final isPlusCodeLike = RegExp(
      r'^[A-Z0-9]{2,}(?:[-+][A-Z0-9]+){1,}$',
      caseSensitive: false,
    ).hasMatch(specificName);
    final parts = <String>[
      if (specificName.isNotEmpty && !isPlusCodeLike) specificName,
      place.subLocality?.trim() ?? '',
      place.locality?.trim() ?? '',
      place.administrativeArea?.trim() ?? '',
    ].where((part) => part.isNotEmpty).toList();

    final uniqueParts = <String>[];
    for (final part in parts) {
      if (!uniqueParts.any(
        (existing) => existing.toLowerCase() == part.toLowerCase(),
      )) {
        uniqueParts.add(part);
      }
    }
    return uniqueParts;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !_isFlutterTest &&
        !_homeLocationResolved) {
      unawaited(_loadHomeLocation());
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

  List<MainCategory> _availableCategories(Iterable<_HomeProductItem> products) {
    final categories = <MainCategory>[...homeMainCategories];
    final knownCategories = categories
        .map((category) => normalizeOption(category.firestoreCategory))
        .toSet();

    for (final item in products) {
      final categoryName = item.raw['category']?.toString().trim() ?? '';
      if (categoryName.isEmpty) {
        continue;
      }

      final canonical = canonicalCategory(categoryName);
      final normalized = normalizeOption(canonical);
      if (normalized.isEmpty || !knownCategories.add(normalized)) {
        continue;
      }

      categories.add(
        MainCategory(
          title: canonical,
          emoji: '🛍️',
          theme: categoryThemeFor(canonical),
          firestoreCategory: canonical,
          subcategories: buildSubcategoriesForCategory(
            products.map((product) => product.raw),
            firestoreCategory: canonical,
          ),
        ),
      );
    }

    return categories;
  }

  String _homeCategoryAsset(String title) {
    switch (title) {
      case 'Grocery':
        return 'assets/banners/grocery.png';
      case 'Food':
        return 'assets/banners/food.png';
      case 'Gifts':
        return 'assets/banners/gifts.png';
      case 'Gifts & Surprises':
        return 'assets/banners/gifts_surprises.png';
      case 'Cosmetics':
        return 'assets/banners/cosmetics.png';
      case 'Electronics':
        return 'assets/banners/electronics.png';
      case 'Home Service':
        return 'assets/banners/home_service.png';
      case 'Parcel Delivery':
        return 'assets/banners/parcel_delivery.png';
      default:
        return 'assets/banners/grocery.png';
    }
  }

  Widget _buildHomeRoundCategories(List<MainCategory> categories) {
    final visibleCategories = _showAllCategories
        ? categories
        : categories.take(6).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Categories',
                  style: TextStyle(
                    fontSize: 20,
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
                    _showAllCategories ? 'See less' : 'See all',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: QuickDropColors.primaryDark,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 104,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: visibleCategories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final category = visibleCategories[index];
              return InkWell(
                onTap: () => _openCategoryPage(category),
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  width: 70,
                  child: Column(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: category.theme.background,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: category.theme.primary.withValues(
                              alpha: 0.18,
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(7),
                          child: Image.asset(
                            _homeCategoryAsset(category.title),
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        category.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1F2937),
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNearbyShopsSection() {
    return StreamBuilder<List<Shop>>(
      stream: _shopService.watchActiveShops(),
      builder: (context, snapshot) {
        final shops = [...?snapshot.data];
        final customerLocation = _homeLocationPosition;
        shops.sort((left, right) {
          final leftDistance = customerLocation == null
              ? null
              : left.distanceFrom(
                  customerLocation.latitude,
                  customerLocation.longitude,
                );
          final rightDistance = customerLocation == null
              ? null
              : right.distanceFrom(
                  customerLocation.latitude,
                  customerLocation.longitude,
                );
          if (leftDistance == null && rightDistance == null) {
            return left.name.toLowerCase().compareTo(right.name.toLowerCase());
          }
          if (leftDistance == null) return 1;
          if (rightDistance == null) return -1;
          return leftDistance.compareTo(rightDistance);
        });

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Nearby Shops',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 104,
                child: shops.isEmpty
                    ? const Center(
                        child: Text(
                          'No active shops available right now.',
                          style: TextStyle(
                            color: Colors.black54,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: shops.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          final shop = shops[index];
                          final distance = customerLocation == null
                              ? null
                              : shop.distanceFrom(
                                  customerLocation.latitude,
                                  customerLocation.longitude,
                                );
                          return SizedBox(
                            width: 238,
                            child: InkWell(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ShopDetailsPage(
                                    shop: shop,
                                    cartNotifier: widget.cartNotifier,
                                  ),
                                ),
                              ),
                              borderRadius: BorderRadius.circular(16),
                              child: Ink(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: QuickDropColors.border,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 52,
                                      height: 52,
                                      child: shop.imageUrl.isEmpty
                                          ? const Icon(
                                              Icons.storefront_outlined,
                                              size: 34,
                                              color: QuickDropColors.primary,
                                            )
                                          : CachedNetworkImage(
                                              imageUrl: shop.imageUrl,
                                              fit: BoxFit.cover,
                                              memCacheWidth: 108,
                                              memCacheHeight: 108,
                                              errorWidget: (_, _, _) =>
                                                  const Icon(
                                                    Icons.storefront_outlined,
                                                    size: 34,
                                                    color:
                                                        QuickDropColors.primary,
                                                  ),
                                            ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            shop.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Text(
                                            shop.displayAddress,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.black54,
                                            ),
                                          ),
                                          Text(
                                            distance == null
                                                ? 'Distance unavailable'
                                                : '${distance.toStringAsFixed(1)} km away',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: QuickDropColors.primary,
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
    WidgetsBinding.instance.removeObserver(this);
    _homeDeliverySettingsSubscription?.cancel();
    _bannerTimer?.cancel();
    _searchDebounce?.cancel();
    _bannerIndexNotifier.dispose();
    _bannerController.dispose();
    _popularBestSellerBannerController.dispose();
    _popularBestSellerBannerIndex.dispose();
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
        return QuickDropColors.primaryLight;
      case 'Cosmetics':
        return const Color(0xFFFCE7F3);
      case 'Electronics':
        return const Color(0xFFE0E7FF);
      case 'Home Service':
        return const Color(0xFFFEF3C7);
      case 'Courier / Delivery':
      case 'Parcel Delivery':
        return QuickDropColors.mint;
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
                                  ? CachedNetworkImage(
                                      imageUrl: item.imageUrl,
                                      width: 52,
                                      height: 52,
                                      fit: BoxFit.cover,
                                      memCacheWidth: 104,
                                      memCacheHeight: 104,
                                      placeholder: (_, _) => const Center(
                                        child: SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                      errorWidget: (context, error, stackTrace) {
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
        final bannerHeight = (constraints.maxWidth * 0.44)
            .clamp(144.0, 168.0)
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
              borderRadius: BorderRadius.circular(16),
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
                            QuickDropColors.primary,
                            QuickDropColors.primaryDark,
                            QuickDropColors.primaryLight,
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
                            QuickDropColors.offer,
                            QuickDropColors.offer,
                            QuickDropColors.lightGreen,
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
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      height: 6,
                      width: activeIndex == index ? 18 : 6,
                      decoration: BoxDecoration(
                        color: activeIndex == index
                            ? QuickDropColors.primary
                            : QuickDropColors.primaryLight,
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
            final bannerHeight = (constraints.maxWidth * 0.44)
                .clamp(144.0, 168.0)
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
                  borderRadius: BorderRadius.circular(16),
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
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          height: 6,
                          width: activeIndex == index ? 18 : 6,
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
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF212121),
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: QuickDropColors.secondaryText,
                  fontWeight: FontWeight.w500,
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
        const SizedBox(height: 10),
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
            height: 244,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemBuilder: (context, index) {
                return SizedBox(
                  width: 148,
                  child: _buildPremiumProductCard(items[index]),
                );
              },
              separatorBuilder: (_, _) => const SizedBox(width: 10),
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openProductDetails(item.product),
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: QuickDropColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 92,
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: resolvedImageUrl.isNotEmpty
                          ? Container(
                              width: double.infinity,
                              height: 92,
                              color: categoryTheme.background,
                              alignment: Alignment.center,
                              child: CachedNetworkImage(
                                imageUrl: resolvedImageUrl,
                                width: 72,
                                height: 72,
                                fit: BoxFit.contain,
                                memCacheWidth: 100,
                                memCacheHeight: 100,
                                placeholder: (_, _) => const SizedBox(
                                  width: 50,
                                  height: 50,
                                  child: Center(
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                ),
                                errorWidget: (_, _, _) => Icon(
                                  Icons.shopping_bag_outlined,
                                  color: categoryTheme.primary,
                                  size: 32,
                                ),
                              ),
                            )
                          : Container(
                              width: double.infinity,
                              height: 92,
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
                            fontSize: 8,
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
                            color: QuickDropColors.commerceGreen,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${item.discountPercent}% OFF',
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
              const SizedBox(height: 7),
              if (brandText.isNotEmpty)
                Text(
                  brandText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF212121),
                  ),
                ),
              Text(
                item.product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
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
                    fontSize: 10,
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
                      color: QuickDropColors.darkText,
                    ),
                  ),
                  if (item.oldPrice != null) ...[
                    const SizedBox(width: 5),
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
              const SizedBox(height: 3),
              Text(
                outOfStock ? 'Out of stock' : 'In stock: ${item.product.stock}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: outOfStock
                      ? Colors.red.shade600
                      : QuickDropColors.secondaryText,
                ),
              ),
              const SizedBox(height: 5),
              SizedBox(
                height: 34,
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: outOfStock
                      ? null
                      : () {
                          _addToCart(item.product);
                        },
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade100,
                    foregroundColor: QuickDropColors.commerceGreen,
                    disabledForegroundColor: Colors.red.shade500,
                    side: BorderSide(
                      color: outOfStock
                          ? Colors.red.shade200
                          : QuickDropColors.commerceGreen,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                    padding: EdgeInsets.zero,
                  ),
                  icon: Icon(
                    outOfStock ? Icons.block_outlined : Icons.add,
                    size: 16,
                  ),
                  label: Text(outOfStock ? 'Out of stock' : 'ADD'),
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
          backgroundColor: QuickDropColors.background,
          drawer: Drawer(
            backgroundColor: Colors.white,
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
                            colors: [
                              QuickDropColors.primaryLight,
                              Color(0xFFFFF8E1),
                            ],
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
                                    color: QuickDropColors.darkText,
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
                                      color: QuickDropColors.darkText,
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
                                      color: QuickDropColors.secondaryText,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'QuickDrop Member',
                                    style: TextStyle(
                                      color: QuickDropColors.secondaryText,
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
                        .limit(50)
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

                _prefetchProductImages(
                  context,
                  allProducts.take(12).map((item) => item.product.imageUrl),
                  limit: 12,
                );

                final popularItems = allProducts.take(8).toList();

                final bestSellerItems = List<_HomeProductItem>.from(allProducts)
                  ..sort(
                    (a, b) => b.bestSellerScore.compareTo(a.bestSellerScore),
                  );

                final availableCategories = _availableCategories(allProducts);

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
                        color: QuickDropColors.background,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
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
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: QuickDropColors.primaryLight,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      alignment: Alignment.center,
                                      child: const Icon(
                                        Icons.menu,
                                        size: 22,
                                        color: Color(0xFF212121),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'QuickDrop Go',
                                          style: const TextStyle(
                                            color: QuickDropColors.darkText,
                                            fontSize: 19,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 1),
                                        InkWell(
                                          onTap: _openHomeLocationSearch,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.location_on_outlined,
                                                color:
                                                    QuickDropColors.primaryDark,
                                                size: 15,
                                              ),
                                              const SizedBox(width: 2),
                                              Expanded(
                                                child: Text(
                                                  _homeLocationAddress,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: QuickDropColors
                                                        .secondaryText,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                              const Icon(
                                                Icons
                                                    .keyboard_arrow_down_rounded,
                                                color: QuickDropColors
                                                    .secondaryText,
                                                size: 17,
                                              ),
                                            ],
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
                                          color: QuickDropColors.darkText,
                                          size: 22,
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
                                      color: QuickDropColors.darkText,
                                      size: 22,
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
                          color: QuickDropColors.primaryLight,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Hello, Shopper 👋',
                                style: TextStyle(
                                  color: QuickDropColors.text,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'What would you like to get today?',
                                style: TextStyle(
                                  color: QuickDropColors.text.withValues(
                                    alpha: 0.78,
                                  ),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: 50,
                                ),
                                child: Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: QuickDropColors.border,
                                      width: 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.06,
                                        ),
                                        blurRadius: 8,
                                        spreadRadius: 0,
                                        offset: const Offset(0, 3),
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
                                        color: QuickDropColors.darkText,
                                        size: 22,
                                      ),
                                      suffixIcon: Padding(
                                        padding: EdgeInsets.only(right: 12),
                                        child: SizedBox(
                                          width: 36,
                                          height: 36,
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              color: QuickDropColors.primary,
                                              borderRadius: BorderRadius.all(
                                                Radius.circular(10),
                                              ),
                                            ),
                                            child: Icon(
                                              Icons.mic_rounded,
                                              size: 22,
                                              color: QuickDropColors.darkText,
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
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.all(
                                          Radius.circular(14),
                                        ),
                                        borderSide: BorderSide.none,
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.all(
                                          Radius.circular(14),
                                        ),
                                        borderSide: BorderSide.none,
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.all(
                                          Radius.circular(14),
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
                      const SizedBox(height: 6),
                      _buildSearchResultsSection(),
                      if (searchQuery.trim().isNotEmpty)
                        const SizedBox(height: 12),
                      _buildHomeRoundCategories(availableCategories),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _homeGiftPromoBanner(context),
                      ),
                      const SizedBox(height: 18),
                      _buildNearbyShopsSection(),
                      const SizedBox(height: 12),
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
                              _popularBestSellerBannerSection(),
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
                              _popularBestSellerBannerSection(),
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
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ViewCartBar(
                cartNotifier: widget.cartNotifier,
                useBottomSafeArea: false,
              ),
              Container(
                margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: QuickDropColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
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
            ],
          ),
        );
      },
    );
  }

  Widget _popularBestSellerBannerSection() {
    if (Firebase.apps.isEmpty) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('banners').snapshots(),
      builder: (context, snapshot) {
        final banners =
            (snapshot.data?.docs ?? const []).where((document) {
              final data = document.data();
              return data['isActive'] == true &&
                  (data['imageUrl']?.toString().trim().isNotEmpty ?? false);
            }).toList()..sort((left, right) {
              final leftData = left.data();
              final rightData = right.data();
              final leftOrder =
                  (leftData['order'] ?? leftData['displayOrder']) as num? ?? 0;
              final rightOrder =
                  (rightData['order'] ?? rightData['displayOrder']) as num? ??
                  0;
              return leftOrder.compareTo(rightOrder);
            });

        if (snapshot.connectionState == ConnectionState.waiting ||
            snapshot.hasError ||
            banners.isEmpty) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 24),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final height = (constraints.maxWidth * 0.44)
                  .clamp(144.0, 168.0)
                  .toDouble();
              return Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      height: height,
                      child: PageView.builder(
                        controller: _popularBestSellerBannerController,
                        itemCount: banners.length,
                        onPageChanged: (index) {
                          _popularBestSellerBannerIndex.value = index;
                        },
                        itemBuilder: (context, index) {
                          final imageUrl =
                              banners[index]
                                  .data()['imageUrl']
                                  ?.toString()
                                  .trim() ??
                              '';
                          return CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, _) => const ColoredBox(
                              color: QuickDropColors.mint,
                              child: Center(child: CircularProgressIndicator()),
                            ),
                            errorWidget: (_, _, _) => const ColoredBox(
                              color: QuickDropColors.mint,
                              child: Icon(Icons.image_not_supported_outlined),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  if (banners.length > 1) ...[
                    const SizedBox(height: 10),
                    ValueListenableBuilder<int>(
                      valueListenable: _popularBestSellerBannerIndex,
                      builder: (context, activeIndex, _) {
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            banners.length,
                            (index) => AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              width: activeIndex == index ? 18 : 6,
                              height: 6,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                color: activeIndex == index
                                    ? QuickDropColors.primary
                                    : QuickDropColors.primaryLight,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _homeStoreStatusBanner() {
    final storeOpen = _homeDeliverySettings.isStoreOpenAt(DateTime.now());
    if (storeOpen) {
      return const SizedBox.shrink();
    }

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
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? QuickDropColors.primaryLight
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      icon,
                      color: selected
                          ? QuickDropColors.primaryDark
                          : QuickDropColors.secondaryText,
                      size: 22,
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
                      ? QuickDropColors.darkText
                      : QuickDropColors.secondaryText,
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
        backgroundColor: QuickDropColors.background,
        foregroundColor: Colors.black,
      ),
      bottomNavigationBar: _ViewCartBar(cartNotifier: widget.cartNotifier),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: QuickDropColors.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: AspectRatio(
                aspectRatio: 16 / 11,
                child: product.imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: product.imageUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: 720,
                        memCacheHeight: 450,
                        placeholder: (_, _) => const Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (context, error, stackTrace) {
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
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
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
                          color: QuickDropColors.commerceGreen,
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
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
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
                              : QuickDropColors.primary,
                          foregroundColor: QuickDropColors.darkText,
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
          const SizedBox(height: 14),
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
                                        ? CachedNetworkImage(
                                            imageUrl: related.imageUrl,
                                            width: double.infinity,
                                            fit: BoxFit.cover,
                                            memCacheWidth: 280,
                                            memCacheHeight: 280,
                                            placeholder: (_, _) => const Center(
                                              child: SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              ),
                                            ),
                                            errorWidget: (_, _, _) =>
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpenDetails,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: QuickDropColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1.3,
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: resolvedImageUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: resolvedImageUrl,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              memCacheWidth: 360,
                              memCacheHeight: 280,
                              placeholder: (_, _) => const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                              errorWidget: (context, error, stackTrace) {
                                return Container(
                                  color: const Color(0xFFFAF7F2),
                                  alignment: Alignment.center,
                                  child: Icon(
                                    Icons.shopping_bag_outlined,
                                    color: Colors.grey.shade400,
                                    size: 32,
                                  ),
                                );
                              },
                            )
                          : Container(
                              color: const Color(0xFFFAF7F2),
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.shopping_bag_outlined,
                                color: Colors.grey.shade400,
                                size: 32,
                              ),
                            ),
                    ),
                    if (item.discountPercent > 0)
                      Positioned(
                        left: 5,
                        top: 5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: QuickDropColors.commerceGreen,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${item.discountPercent}%',
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
              const SizedBox(height: 4),
              if (item.brand.trim().isNotEmpty)
                Text(
                  item.brand,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF999999),
                  ),
                ),
              SizedBox(
                height: 32,
                child: Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF212121),
                  ),
                ),
              ),
              if (weightUnitText.isNotEmpty)
                Text(
                  weightUnitText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF666666),
                  ),
                ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    item.price,
                    style: const TextStyle(
                      color: Color(0xFF212121),
                      fontSize: 14,
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
                        fontWeight: FontWeight.w500,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 3),
              Text(
                outOfStock ? 'Out of stock' : 'In stock',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: outOfStock
                      ? Colors.red.shade600
                      : QuickDropColors.secondaryText,
                  fontSize: 9,
                  fontWeight: outOfStock ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 32,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: outOfStock ? null : onAddToCart,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    foregroundColor: QuickDropColors.commerceGreen,
                    disabledForegroundColor: Colors.red.shade500,
                    side: BorderSide(
                      color: outOfStock
                          ? Colors.red.shade200
                          : QuickDropColors.commerceGreen,
                    ),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  child: Text(
                    outOfStock ? 'Out of stock' : 'ADD',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
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
  String? _selectedSidebarSubcategory;
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
    _selectedSidebarSubcategory = widget.selectedSubcategory;
    _scrollController = ScrollController();
  }

  @override
  void didUpdateWidget(covariant CategoryProductsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedSubcategory != widget.selectedSubcategory) {
      _selectedSubcategory = widget.selectedSubcategory;
      _selectedSidebarSubcategory = widget.selectedSubcategory;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
      return;
    }

    if (subcategory == _selectedSubcategory) {
      setState(() {
        _selectedSubcategory = null;
        _selectedChildCategory = null;
      });
      return;
    }

    setState(() {
      _selectedSubcategory = subcategory;
      _selectedChildCategory = null;
    });
  }

  void _openChildCategory(String? childCategory) {
    if (childCategory == null || childCategory.isEmpty) {
      if (_selectedChildCategory == null) {
        return;
      }
      setState(() {
        _selectedChildCategory = null;
      });
      return;
    }

    if (childCategory == _selectedChildCategory) {
      setState(() {
        _selectedChildCategory = null;
      });
      return;
    }

    setState(() {
      _selectedChildCategory = childCategory;
    });
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

  List<String> _dynamicSubcategoryNames(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final names = <String>[];
    final seen = <String>{};
    for (final doc in docs) {
      final data = doc.data();
      if (!categoryValueMatches(
        data['category']?.toString(),
        widget.firestoreCategory,
      )) {
        continue;
      }
      final subcategory = data['subcategory']?.toString().trim() ?? '';
      final key = normalizeOption(subcategory);
      if (key.isNotEmpty && seen.add(key)) {
        names.add(subcategory);
      }
    }
    return names;
  }

  String _subcategoryImageUrl(
    String subcategory,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    for (final doc in docs) {
      final data = doc.data();
      if (categoryValueMatches(
            data['category']?.toString(),
            widget.firestoreCategory,
          ) &&
          normalizeOption(data['subcategory']?.toString()) ==
              normalizeOption(subcategory)) {
        final imageUrl = extractProductImageUrl(data);
        if (imageUrl.isNotEmpty) {
          return imageUrl;
        }
      }
    }
    return '';
  }

  Widget _buildGrocerySidebarLayout(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final subcategories = _dynamicSubcategoryNames(docs);
    final selectedSubcategory =
        subcategories.any(
          (subcategory) =>
              normalizeOption(subcategory) ==
              normalizeOption(_selectedSidebarSubcategory),
        )
        ? _selectedSidebarSubcategory
        : null;
    final sidebarItems = ['All', ...subcategories];
    final filteredDocs = docs
        .where(
          (doc) => matchesCategoryAndSubcategory(
            doc.data(),
            firestoreCategory: widget.firestoreCategory,
            selectedSubcategory: selectedSubcategory,
          ),
        )
        .toList();

    _prefetchProductImages(
      context,
      filteredDocs.take(8).map((doc) => extractProductImageUrl(doc.data())),
    );

    final screenWidth = MediaQuery.sizeOf(context).width;
    final sidebarWidth = screenWidth < 360 ? 96.0 : 116.0;
    final categoryTheme = categoryThemeFor(widget.firestoreCategory);
    final productCellWidth = (screenWidth - sidebarWidth - 32) / 2;
    final productCardAspectRatio = (productCellWidth / (productCellWidth + 125))
        .clamp(0.42, 0.54)
        .toDouble();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: QuickDropColors.background,
        foregroundColor: QuickDropColors.darkText,
        elevation: 0,
      ),
      bottomNavigationBar: _ViewCartBar(cartNotifier: widget.cartNotifier),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: sidebarWidth,
            child: ColoredBox(
              color: Colors.white,
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(vertical: 12),
                itemCount: sidebarItems.length,
                itemBuilder: (context, index) {
                  final subcategory = sidebarItems[index];
                  final isAll = index == 0;
                  final isSelected = isAll
                      ? selectedSubcategory == null
                      : normalizeOption(subcategory) ==
                            normalizeOption(selectedSubcategory);
                  final imageUrl = isAll
                      ? ''
                      : _subcategoryImageUrl(subcategory, docs);
                  final theme = categoryTheme;
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: InkWell(
                      onTap: isSelected
                          ? null
                          : () {
                              setState(() {
                                _selectedSidebarSubcategory = isAll
                                    ? null
                                    : subcategory;
                                _selectedSubcategory = isAll
                                    ? null
                                    : subcategory;
                                _selectedChildCategory = null;
                              });
                            },
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFFFF9E6)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: isSelected
                              ? Border.all(
                                  color: const Color(0xFFFFD54F),
                                  width: 1.0,
                                )
                              : null,
                        ),
                        child: Column(
                          children: [
                            SizedBox(
                              width: 48,
                              height: 48,
                              child: imageUrl.isEmpty
                                  ? Icon(
                                      Icons.shopping_bag_outlined,
                                      color: theme.primary,
                                      size: 30,
                                    )
                                  : ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: CachedNetworkImage(
                                        imageUrl: imageUrl,
                                        fit: BoxFit.cover,
                                        memCacheWidth: 96,
                                        memCacheHeight: 96,
                                        placeholder: (_, _) => Icon(
                                          Icons.shopping_bag_outlined,
                                          color: theme.primary,
                                        ),
                                        errorWidget: (_, _, _) => Icon(
                                          Icons.shopping_bag_outlined,
                                          color: theme.primary,
                                          size: 30,
                                        ),
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              subcategory,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.black
                                    : const Color(0xFF212121),
                                fontSize: 11,
                                fontWeight: isSelected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Expanded(
            child: filteredDocs.isEmpty
                ? Center(
                    child: Text(
                      'No products available in ${widget.title} right now.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  )
                : CustomScrollView(
                    key: ValueKey(selectedSubcategory ?? 'all'),
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 12, 104),
                        sliver: SliverGrid(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 8,
                                childAspectRatio: productCardAspectRatio,
                              ),
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            final doc = filteredDocs[index];
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
                          }, childCount: filteredDocs.length),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categoryTheme = categoryThemeFor(widget.title);
    final categoryPageColor = _categoryPageThemeColor();
    final childCategories = buildChildCategoryOptions(_selectedSubcategory);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final crossAxisCount = screenWidth > 700 ? 3 : 2;
    final categoryCardAspectRatio = crossAxisCount == 3 ? 0.75 : 0.70;
    final headerHeight = childCategories.isNotEmpty ? 122.0 : 60.0;

    return Scaffold(
      bottomNavigationBar: _ViewCartBar(cartNotifier: widget.cartNotifier),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('products')
            .where('category', isEqualTo: widget.firestoreCategory)
            .snapshots(),
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
          if (widget.firestoreCategory.trim().isNotEmpty) {
            return _buildGrocerySidebarLayout(context, docs);
          }

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
          final resolvedDocs = filteredDocs;

          _prefetchProductImages(
            context,
            resolvedDocs
                .take(8)
                .map((doc) => extractProductImageUrl(doc.data())),
          );

          final tabContent = Container(
            width: double.infinity,
            color: categoryTheme.background,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (availableSubcategories.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: SizedBox(
                      height: 34,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
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
                        SizedBox(
                          height: 34,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
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
                                      duration: const Duration(
                                        milliseconds: 220,
                                      ),
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
                                      duration: const Duration(
                                        milliseconds: 220,
                                      ),
                                      curve: Curves.easeOutCubic,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _selectedChildCategory == name
                                            ? categoryPageColor
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        border: Border.all(
                                          color: categoryPageColor.withValues(
                                            alpha: 0.25,
                                          ),
                                        ),
                                      ),
                                      child: AnimatedDefaultTextStyle(
                                        duration: const Duration(
                                          milliseconds: 220,
                                        ),
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
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                title: Text(widget.title),
                backgroundColor: QuickDropColors.background,
                foregroundColor: Colors.black,
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
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: 2,
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gifts & Surprises'),
        backgroundColor: QuickDropColors.background,
        foregroundColor: Colors.black,
      ),
      bottomNavigationBar: _ViewCartBar(cartNotifier: widget.cartNotifier),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
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
                      selectedColor: Colors.black,
                      onSelected: (_) {
                        setState(() {
                          _selectedSection = section;
                        });
                      },
                      labelStyle: TextStyle(
                        color: _selectedSection == section
                            ? Colors.white
                            : Colors.black,
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
                  .where('category', isEqualTo: 'Gifts & Surprises')
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

                _prefetchProductImages(
                  context,
                  items.take(8).map((item) => item.imageUrl),
                );

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
                                  ? CachedNetworkImage(
                                      imageUrl: resolvedImageUrl,
                                      height: 180,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      memCacheWidth: 360,
                                      memCacheHeight: 360,
                                      placeholder: (_, _) => const Center(
                                        child: SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                      errorWidget: (context, error, stackTrace) {
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
                                  backgroundColor: Colors.black,
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
              activeThumbColor: Colors.black,
              onChanged: (value) => setState(() => _giftWrapping = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Greeting Card'),
              value: _greetingCard,
              activeThumbColor: Colors.black,
              onChanged: (value) => setState(() => _greetingCard = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Handwritten Message'),
              value: _handwrittenMessage,
              activeThumbColor: Colors.black,
              onChanged: (value) => setState(() => _handwrittenMessage = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Secret Surprise Delivery'),
              value: _secretSurpriseDelivery,
              activeThumbColor: Colors.black,
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
                            selectedColor: Colors.black,
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
                        backgroundColor: Colors.black,
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
        backgroundColor: QuickDropColors.background,
        foregroundColor: Colors.black,
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

          final subtotal = cartSubtotal(items);

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
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  children: [
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
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
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: SizedBox(
                                  width: 56,
                                  height: 56,
                                  child: entry.product.imageUrl.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: entry.product.imageUrl,
                                          fit: BoxFit.cover,
                                          memCacheWidth: 112,
                                          memCacheHeight: 112,
                                          errorWidget: (_, _, _) => ColoredBox(
                                            color: entry.product.accent
                                                .withValues(alpha: 0.15),
                                            child: Center(
                                              child: Text(
                                                entry.product.emoji,
                                                style: const TextStyle(
                                                  fontSize: 22,
                                                ),
                                              ),
                                            ),
                                          ),
                                        )
                                      : ColoredBox(
                                          color: entry.product.accent
                                              .withValues(alpha: 0.15),
                                          child: Center(
                                            child: Text(
                                              entry.product.emoji,
                                              style: const TextStyle(
                                                fontSize: 22,
                                              ),
                                            ),
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
                                      entry.product.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${entry.product.price} • ${entry.product.unit}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: QuickDropColors.secondaryText,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
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
                                    color: QuickDropColors.commerceGreen,
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
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () {
                                      final updated = List<CartItem>.from(
                                        items,
                                      );
                                      updated[index].quantity += 1;
                                      cartNotifier.value = updated;
                                    },
                                    color: QuickDropColors.commerceGreen,
                                    icon: const Icon(Icons.add_circle_outline),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
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
                  border: Border(
                    top: BorderSide(color: QuickDropColors.border),
                  ),
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
                          backgroundColor: QuickDropColors.primary,
                          foregroundColor: QuickDropColors.darkText,
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

class _ViewCartBar extends StatelessWidget {
  const _ViewCartBar({
    required this.cartNotifier,
    this.useBottomSafeArea = true,
  });

  final ValueNotifier<List<CartItem>> cartNotifier;
  final bool useBottomSafeArea;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<CartItem>>(
      valueListenable: cartNotifier,
      builder: (context, items, _) {
        if (items.isEmpty) return const SizedBox.shrink();

        final itemCount = items.fold<int>(
          0,
          (total, item) => total + item.quantity,
        );
        final subtotal = cartSubtotal(items);

        return SafeArea(
          top: false,
          bottom: useBottomSafeArea,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Material(
              color: QuickDropColors.primary,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CartPage(cartNotifier: cartNotifier),
                  ),
                ),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.shopping_cart_outlined,
                        color: QuickDropColors.darkText,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '$itemCount ${itemCount == 1 ? 'item' : 'items'} • ₹$subtotal',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: QuickDropColors.darkText,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const Text(
                        'View Cart',
                        style: TextStyle(
                          color: QuickDropColors.darkText,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: QuickDropColors.darkText,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
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
      stream: FirebaseFirestore.instance
          .collection('products')
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];
        final recommendations = _buildRecommendations(docs, cartItems);

        _prefetchProductImages(
          context,
          recommendations.take(6).map((item) => item.imageUrl),
          limit: 6,
        );

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
                  ? CachedNetworkImage(
                      imageUrl: item.imageUrl,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      memCacheWidth: 304,
                      memCacheHeight: 304,
                      placeholder: (_, _) => const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (_, _, _) => _fallbackImage(item),
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
  final LocationService _locationService = const LocationService();
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
    unawaited(_initializeCurrentDeliveryLocation());
  }

  Future<void> _initializeCurrentDeliveryLocation() async {
    await _prefillCheckoutFromSession();
    try {
      final position = await _locationService.getCurrentPosition();
      final currentLocation = LatLng(position.latitude, position.longitude);
      final currentAddress = await _resolveAddressFromCoordinates(
        currentLocation,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _selectedDeliveryLocation = currentLocation;
        _selectedDeliveryAddress = currentAddress ?? 'Current Location';
        _addressController.text = _selectedDeliveryAddress!;
      });
    } catch (error, stackTrace) {
      developer.log(
        'Checkout current location initialization failed: $error',
        name: 'QuickDropLocation',
        error: error,
        stackTrace: stackTrace,
      );
    }
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
      _selectedDeliveryAddress = resolvedAddress ?? 'Current Location';
      _addressController.text = _selectedDeliveryAddress!;
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
      final specificName = place.name?.trim() ?? '';
      final isPlusCodeLike = RegExp(
        r'^[A-Z0-9]{2,}(?:[-+][A-Z0-9]+){1,}$',
        caseSensitive: false,
      ).hasMatch(specificName);
      final parts = <String>[
        if (specificName.isNotEmpty && !isPlusCodeLike) specificName,
        place.subLocality?.trim() ?? '',
        place.locality?.trim() ?? '',
        place.administrativeArea?.trim() ?? '',
      ].where((part) => part.isNotEmpty).toList();

      final uniqueParts = <String>[];
      for (final part in parts) {
        if (!uniqueParts.any(
          (existing) => existing.toLowerCase() == part.toLowerCase(),
        )) {
          uniqueParts.add(part);
        }
      }

      if (uniqueParts.isEmpty) {
        return null;
      }

      return uniqueParts.join(', ');
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
    final shopIds = items
        .map((item) => item.product.shopId?.trim())
        .where((shopId) => shopId != null && shopId.isNotEmpty)
        .toSet();
    final hasGlobalProducts = items.any((item) => item.product.shopId == null);
    if (shopIds.length > 1 || (shopIds.isNotEmpty && hasGlobalProducts)) {
      throw FirebaseException(
        plugin: 'quickdrop',
        message:
            'Products from different shopping sources cannot be ordered together. Clear the cart or finish the current shop order first.',
      );
    }
    final selectedShopId = shopIds.singleOrNull;
    final CartItem? selectedShopItem = selectedShopId == null
        ? null
        : items.firstWhere((item) => item.product.shopId == selectedShopId);

    final authUser = FirebaseAuth.instance.currentUser;
    final ownerUid = authUser?.uid ?? '';
    if (ownerUid.isEmpty) {
      throw FirebaseException(
        plugin: 'quickdrop',
        message: 'Sign in again before placing an order.',
      );
    }

    final ownerPhone = normalizePhoneValue(
      authUser?.phoneNumber ?? await _authService.getCurrentUserPhone(),
    );
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
      if (value is num) return value.toDouble();
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
      'ownerUid': ownerUid,
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

    if (selectedShopId != null) {
      orderData['storeId'] = selectedShopId;
      orderData['shopNameSnapshot'] =
          selectedShopItem!.product.shopNameSnapshot;
      orderData['shopAddressSnapshot'] =
          selectedShopItem.product.shopAddressSnapshot;

      try {
        final shopSnapshot = await FirebaseFirestore.instance
            .collection('shops')
            .doc(selectedShopId)
            .get();
        final shop = shopSnapshot.data();
        final pickupLatitude = (shop?['latitude'] as num?)?.toDouble();
        final pickupLongitude = (shop?['longitude'] as num?)?.toDouble();
        if (pickupLatitude != null && pickupLongitude != null) {
          orderData['pickupName'] =
              shop?['name']?.toString().trim().isNotEmpty == true
              ? shop!['name'].toString().trim()
              : selectedShopItem.product.shopNameSnapshot;
          orderData['pickupAddress'] =
              shop?['address']?.toString().trim().isNotEmpty == true
              ? shop!['address'].toString().trim()
              : selectedShopItem.product.shopAddressSnapshot;
          orderData['pickupLatitude'] = pickupLatitude;
          orderData['pickupLongitude'] = pickupLongitude;
        }
      } catch (_) {}
    }

    if (paymentId != null && paymentId.isNotEmpty) {
      orderData['paymentId'] = paymentId;
    }

    await FirebaseFirestore.instance.collection('orders').add(orderData);
    try {
      await _reduceStockAfterOrder(items);
    } catch (error, stackTrace) {
      developer.log(
        'Order was created, but the post-order stock update failed.',
        name: 'QuickDropCheckout',
        error: error,
        stackTrace: stackTrace,
      );
    }
    widget.cartNotifier.value = [];
    return order;
  }

  Map<String, Object> _buildRazorpayOptions(int totalAmount) {
    return {
      'key': _razorpayTestKey,
      'amount': totalAmount * 100,
      'name': 'QuickDrop Go',
      'description': 'Order payment',
      'prefill': {
        'contact': _phoneController.text.trim(),
        'name': _nameController.text.trim(),
      },
      'theme': {'color': '#16856F'},
    };
  }

  Future<void> _startOnlinePayment(
    int total,
    DeliverySettings deliverySettings,
  ) async {
    if (kIsWeb) {
      throw FirebaseException(
        plugin: 'quickdrop',
        message: 'Online payment is available on Android and iOS only.',
      );
    }
    if (_razorpayTestKey == 'rzp_test_ReplaceWithYourKey') {
      throw FirebaseException(
        plugin: 'quickdrop',
        message: 'Online payment is not configured yet.',
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
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => OrderSuccessPage(order: order)),
      );
    } on FirebaseException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.message ??
                'Payment succeeded, but the order could not be saved.',
          ),
        ),
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
    if (_isPlacingOrder) return;
    _setPlacingOrder(true);

    final items = List<CartItem>.from(widget.cartNotifier.value);
    if (items.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Your cart is empty')));
      _setPlacingOrder(false);
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      _setPlacingOrder(false);
      return;
    }

    final deliverySettings = await _validatedDeliverySettings();
    if (deliverySettings == null) {
      _setPlacingOrder(false);
      return;
    }
    final deliveryCharge = deliverySettings
        .chargeFor(widget.subtotal.toDouble())
        .round();
    final total = widget.subtotal + deliveryCharge;

    if (_paymentMethod == _paymentMethodOnline) {
      try {
        await _startOnlinePayment(total, deliverySettings);
      } on FirebaseException catch (error) {
        _showCheckoutMessage(error.message ?? 'Unable to start payment.');
        _setPlacingOrder(false);
      } catch (_) {
        _showCheckoutMessage('Unable to start payment.');
        _setPlacingOrder(false);
      }
      return;
    }

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
        backgroundColor: QuickDropColors.background,
        foregroundColor: Colors.black,
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
                'Customer information',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: QuickDropColors.darkText,
                ),
              ),
              const SizedBox(height: 10),
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
                'Delivery details',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: QuickDropColors.darkText,
                ),
              ),
              const SizedBox(height: 10),
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
              const SizedBox(height: 16),
              const Text(
                'Payment',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: QuickDropColors.darkText,
                ),
              ),
              const SizedBox(height: 10),
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
                    icon: Icon(Icons.keyboard_arrow_down, color: Colors.black),
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
                'Bill summary',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: QuickDropColors.darkText,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Total Amount',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: QuickDropColors.background,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: QuickDropColors.border),
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
                    backgroundColor: QuickDropColors.primary,
                    foregroundColor: QuickDropColors.darkText,
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
      prefixIcon: Icon(icon, color: QuickDropColors.darkText),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: QuickDropColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: QuickDropColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: QuickDropColors.primaryDark,
          width: 1.4,
        ),
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
      backgroundColor: QuickDropColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: QuickDropColors.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: QuickDropColors.primaryLight,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle,
                      color: QuickDropColors.commerceGreen,
                      size: 56,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Order placed successfully',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: QuickDropColors.background,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: QuickDropColors.border),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Order ID: ${order.id}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: QuickDropColors.darkText,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          order.status.label,
                          style: const TextStyle(
                            color: QuickDropColors.secondaryText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
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
                      backgroundColor: QuickDropColors.primary,
                      foregroundColor: QuickDropColors.darkText,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Text('View My Orders'),
                  ),
                ],
              ),
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
        backgroundColor: QuickDropColors.background,
        foregroundColor: Colors.black,
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
                        backgroundColor: Colors.black,
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
                  foregroundColor: Colors.black,
                  side: const BorderSide(color: Colors.black),
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
        selectedItemColor: Colors.black,
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
        leading: Icon(icon, color: Colors.black),
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
        backgroundColor: QuickDropColors.background,
        foregroundColor: Colors.black,
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Orders'),
        backgroundColor: QuickDropColors.background,
        foregroundColor: Colors.black,
      ),
      body: FutureBuilder<String?>(
        future: Future<String?>.value(FirebaseAuth.instance.currentUser?.uid),
        builder: (context, sessionSnapshot) {
          if (sessionSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final ownerUid = sessionSnapshot.data?.trim() ?? '';
          if (ownerUid.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Sign in again to view your orders.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            );
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('orders')
                .where('ownerUid', isEqualTo: ownerUid)
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
      backgroundColor: QuickDropColors.background,
      elevation: 0,
      iconTheme: const IconThemeData(color: QuickDropColors.darkText),
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
      case OrderStatus.goingToStore:
      case OrderStatus.reachedStore:
      case OrderStatus.orderCollected:
        return (bg: const Color(0xFFE5F0FF), fg: const Color(0xFF2F67D6));
      case OrderStatus.outForDelivery:
        return (bg: const Color(0xFFFFE9D6), fg: const Color(0xFFEF6C00));
      case OrderStatus.delivered:
        return (bg: const Color(0xFFE5F6EA), fg: const Color(0xFF2E7D32));
      case OrderStatus.rejected:
        return (bg: const Color(0xFFFCE8E8), fg: const Color(0xFFC62828));
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: QuickDropColors.border),
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

    if (status == OrderStatus.rejected) {
      return _surfaceCard(
        child: const Row(
          children: [
            Icon(Icons.refresh_rounded, color: Color(0xFFA37400)),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Your delivery partner could not accept the order. QuickDrop will assign another rider.',
                style: TextStyle(
                  color: Color(0xFFA37400),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Packed is retained for legacy/admin-managed orders. The current rider
    // workflow proceeds directly from Accepted to Going to Store.
    final progressStatus = status == OrderStatus.packed
        ? OrderStatus.accepted
        : status;
    final currentIndex = _orderProgressStages.indexOf(progressStatus);

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
                            color: index < currentIndex
                                ? QuickDropColors.commerceGreen
                                : index == currentIndex
                                ? QuickDropColors.primary
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
                            height: 32,
                            decoration: BoxDecoration(
                              color: index < currentIndex
                                  ? QuickDropColors.commerceGreen
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

  String _stringField(Map<String, dynamic> data, String key) =>
      data[key]?.toString().trim() ?? '';

  Future<void> _ensureOwnerUid(
    String orderDocId,
    Map<String, dynamic> data,
  ) async {
    final authUser = FirebaseAuth.instance.currentUser;
    final uid = authUser?.uid;
    if (uid == null || _stringField(data, 'ownerUid').isNotEmpty) {
      return;
    }
    if (!orderMatchesVerifiedOwnerPhone(data, authUser?.phoneNumber)) {
      return;
    }
    try {
      await FirebaseFirestore.instance.collection('orders').doc(orderDocId).set(
        {'ownerUid': uid},
        SetOptions(merge: true),
      );
    } catch (error) {
      developer.log(
        'ownerUid backfill skipped: $error',
        name: 'QuickDropOrder',
      );
    }
  }

  Future<void> _openRiderChat(
    BuildContext context,
    String orderDocId,
    String orderDisplayId,
    Map<String, dynamic> data,
    String? riderName,
  ) async {
    await _ensureOwnerUid(orderDocId, data);
    if (!context.mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderChatPage(
          orderDocId: orderDocId,
          orderDisplayId: orderDisplayId,
          riderName: riderName,
          customerName: _stringField(data, 'name'),
        ),
      ),
    );
  }

  Future<void> _dialNumber(BuildContext context, String phone) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(' ', ''));
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not start the call.')),
      );
    }
  }

  Widget _riderActionButtons(
    BuildContext context,
    String orderDocId,
    String orderDisplayId,
    Map<String, dynamic> data,
    String? riderName,
    String riderPhone,
  ) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _openRiderChat(
              context,
              orderDocId,
              orderDisplayId,
              data,
              riderName,
            ),
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
            label: const Text('Message Rider'),
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.black,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: riderPhone.isEmpty
                ? null
                : () => _dialNumber(context, riderPhone),
            icon: const Icon(Icons.call_outlined, size: 18),
            label: const Text('Call Rider'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF222222),
              side: const BorderSide(color: Color(0xFFEEEEEE)),
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _riderDetails(
    BuildContext context,
    String orderDocId,
    String orderDisplayId,
    Map<String, dynamic> data,
    String riderName,
    String riderPhone,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          riderName.isEmpty ? 'Delivery Partner' : riderName,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF222222),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          riderPhone.isEmpty ? 'Phone not available' : riderPhone,
          style: const TextStyle(
            color: Color(0xFF757575),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        _riderActionButtons(
          context,
          orderDocId,
          orderDisplayId,
          data,
          riderName.isEmpty ? null : riderName,
          riderPhone,
        ),
      ],
    );
  }

  Widget _deliveryPartnerCard(
    BuildContext context,
    Map<String, dynamic> data,
    String orderDocId,
    String orderDisplayId,
  ) {
    final partnerId = _stringField(data, 'assignedPartnerId');

    if (partnerId.isEmpty) {
      return _infoCard(
        icon: Icons.delivery_dining_outlined,
        title: 'Delivery Partner',
        content: const [
          Text(
            'Delivery partner will be assigned soon',
            style: TextStyle(
              color: Color(0xFF757575),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    final cachedName = _stringField(data, 'assignedPartnerName');
    final cachedPhone = _stringField(data, 'assignedPartnerPhone');

    if (cachedName.isNotEmpty || cachedPhone.isNotEmpty) {
      return _infoCard(
        icon: Icons.delivery_dining_outlined,
        title: 'Delivery Partner',
        content: [
          _riderDetails(
            context,
            orderDocId,
            orderDisplayId,
            data,
            cachedName,
            cachedPhone,
          ),
        ],
      );
    }

    return _infoCard(
      icon: Icons.delivery_dining_outlined,
      title: 'Delivery Partner',
      content: [
        FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          key: ValueKey(partnerId),
          future: FirebaseFirestore.instance
              .collection('delivery_partners')
              .doc(partnerId)
              .get(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            }

            final rider = snapshot.data?.data() ?? const <String, dynamic>{};
            return _riderDetails(
              context,
              orderDocId,
              orderDisplayId,
              data,
              rider['name']?.toString().trim() ?? '',
              rider['phone']?.toString().trim() ?? '',
            );
          },
        ),
      ],
    );
  }

  Future<void> _openDeliveryLocation(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final latitude = (data['latitude'] as num?)?.toDouble();
    final longitude = (data['longitude'] as num?)?.toDouble();

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          title: 'Delivery Location',
          initialPosition: latitude != null && longitude != null
              ? LatLng(latitude, longitude)
              : null,
        ),
      ),
    );
  }

  Widget _orderSummaryCard(Map<String, dynamic> data) {
    final items = (data['items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final subtotal = data['subtotal']?.toString() ?? '';
    final deliveryCharge = data['deliveryCharge']?.toString() ?? '';
    final totalAmount = data['totalAmount']?.toString() ?? '0';

    Widget amountRow(String label, String value, {bool emphasize = false}) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: emphasize
                    ? const Color(0xFF222222)
                    : const Color(0xFF757575),
                fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            Text(
              '₹$value',
              style: TextStyle(
                color: const Color(0xFF222222),
                fontWeight: emphasize ? FontWeight.w800 : FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    return _infoCard(
      icon: Icons.receipt_long_outlined,
      title: 'Order Summary',
      content: [
        if (items.isEmpty)
          const Text(
            'Item details are not available for this order.',
            style: TextStyle(
              color: Color(0xFF757575),
              fontWeight: FontWeight.w600,
            ),
          )
        else
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['name']?.toString() ?? 'Item',
                          style: const TextStyle(
                            color: Color(0xFF222222),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Qty ${item['quantity']?.toString() ?? '1'}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF757575),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '₹${item['itemTotal']?.toString() ?? item['price']?.toString() ?? '0'}',
                    style: const TextStyle(
                      color: Color(0xFF222222),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        const Divider(color: Color(0xFFEEEEEE), height: 18),
        if (subtotal.isNotEmpty) amountRow('Subtotal', subtotal),
        if (deliveryCharge.isNotEmpty)
          amountRow('Delivery Charge', deliveryCharge),
        amountRow('Total', totalAmount, emphasize: true),
      ],
    );
  }

  ({String method, String status, bool paid}) _paymentDisplay(
    Map<String, dynamic> data,
  ) {
    final rawMethod = _stringField(data, 'paymentMethod');
    final rawStatus = _stringField(data, 'paymentStatus').toLowerCase();
    final isCod = rawMethod.toLowerCase().contains('cash');
    final paid = rawStatus == 'paid';

    return (
      method: isCod
          ? 'Cash on Delivery'
          : rawMethod.isEmpty
          ? 'Online Payment'
          : rawMethod,
      status: paid ? 'Paid' : 'Payment Pending',
      paid: paid,
    );
  }

  Widget _paymentCard(Map<String, dynamic> data) {
    final payment = _paymentDisplay(data);

    return _infoCard(
      icon: Icons.account_balance_wallet_outlined,
      title: 'Payment',
      content: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              payment.method,
              style: const TextStyle(
                color: Color(0xFF222222),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: payment.paid
                    ? const Color(0xFFE5F6EA)
                    : const Color(0xFFFFF4CC),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                payment.status,
                style: TextStyle(
                  color: payment.paid
                      ? const Color(0xFF2E7D32)
                      : const Color(0xFFA37400),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _showContactSupport(BuildContext context, String orderId) async {
    const supportEmail = 'quickdropsupport@gmail.com';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: QuickDropColors.border,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Row(
                  children: [
                    Icon(
                      Icons.email_outlined,
                      color: QuickDropColors.primaryDark,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Email Support',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: QuickDropColors.darkText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: QuickDropColors.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: QuickDropColors.border),
                  ),
                  child: const Text(
                    supportEmail,
                    style: TextStyle(
                      color: QuickDropColors.darkText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final emailUri = Uri(
                        scheme: 'mailto',
                        path: supportEmail,
                        queryParameters: {
                          'subject': 'QuickDrop Support - Order $orderId',
                        },
                      );

                      try {
                        final opened = await launchUrl(
                          emailUri,
                          mode: LaunchMode.externalApplication,
                        );
                        if (opened) {
                          if (sheetContext.mounted) {
                            Navigator.of(sheetContext).pop();
                          }
                        } else if (sheetContext.mounted) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Unable to open an email app. Please use the email address shown above.',
                              ),
                            ),
                          );
                        }
                      } catch (_) {
                        if (sheetContext.mounted) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Unable to open an email app. Please use the email address shown above.',
                              ),
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('Send Email'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: QuickDropColors.primary,
                      foregroundColor: QuickDropColors.darkText,
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
              _deliveryPartnerCard(
                context,
                data,
                fallbackOrderId,
                orderIdValue,
              ),
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
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _openDeliveryLocation(context, data),
                      icon: const Icon(Icons.map_outlined, size: 18),
                      label: const Text('View Location'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF222222),
                        side: const BorderSide(color: Color(0xFFEEEEEE)),
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _orderSummaryCard(data),
              const SizedBox(height: 18),
              _paymentCard(data),
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
              // Keeps the final progress milestones fully scrollable above the
              // fixed order actions and the device navigation inset.
              const SizedBox(height: 156),
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
                  onPressed: () => _openDeliveryLocation(context, data),
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
                  onPressed: () => _showContactSupport(context, orderIdValue),
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
                      backgroundColor: Colors.black,
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
      future: Future<String?>.value(FirebaseAuth.instance.currentUser?.uid),
      builder: (context, ownerSnapshot) {
        if (ownerSnapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: _orderDetailsAppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final ownerUid = ownerSnapshot.data?.trim() ?? '';
        if (ownerUid.isEmpty) {
          return Scaffold(
            appBar: _orderDetailsAppBar(),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Sign in again to view this order.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          );
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('orders')
              .doc(orderId)
              .snapshots(),
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

            final doc = snapshot.data;
            final data = doc?.data();
            final isUidOwner =
                data != null && _stringField(data, 'ownerUid') == ownerUid;
            // Isolated legacy compatibility: a blank ownerUid can only be
            // recognized when the immutable ownership phone matches the
            // authenticated Firebase phone after canonical normalization.
            final isVerifiedLegacyOwner =
                data != null &&
                _stringField(data, 'ownerUid').isEmpty &&
                orderMatchesVerifiedOwnerPhone(
                  data,
                  FirebaseAuth.instance.currentUser?.phoneNumber,
                );
            if (doc == null ||
                !doc.exists ||
                data == null ||
                (!isUidOwner && !isVerifiedLegacyOwner) ||
                (data['orderId']?.toString() ?? '') != (orderId ?? '')) {
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

            if (isVerifiedLegacyOwner) {
              unawaited(_ensureOwnerUid(doc.id, data));
            }

            return _buildOrderScaffold(context, data, doc.id);
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
                backgroundColor: Colors.black,
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
        backgroundColor: QuickDropColors.background,
        foregroundColor: Colors.black,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showProductDialog(),
        backgroundColor: Colors.black,
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
                              : CachedNetworkImage(
                                  imageUrl: image,
                                  width: 68,
                                  height: 68,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 136,
                                  memCacheHeight: 136,
                                  placeholder: (_, _) => const Center(
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                  errorWidget: (_, _, _) => Container(
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
