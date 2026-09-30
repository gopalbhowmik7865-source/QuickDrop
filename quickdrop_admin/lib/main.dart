import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:csv/csv.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'admin_order_details_page.dart';
import 'banner_management_page.dart';
import 'push_notification_service.dart';
import 'firebase_options.dart';
import 'category_routing.dart';
import 'services/rider_assignment_service.dart';
import 'settings_page.dart';
import 'shop_management_page.dart';
import 'stock_management_page.dart';

final GlobalKey<NavigatorState> adminNavigatorKey = GlobalKey<NavigatorState>();

late QuickDropAdminNotificationService quickDropAdminNotificationService;

Future<void> _openAdminOrderDetails(String orderId) async {
  adminNavigatorKey.currentState?.push(
    MaterialPageRoute(builder: (_) => AdminOrderDetailsPage(orderId: orderId)),
  );
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
        return 'Going to Store';
      case OrderStatus.reachedStore:
        return 'Reached Store';
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
      return Colors.orange;
    case OrderStatus.accepted:
      return Colors.blue;
    case OrderStatus.packed:
      return Colors.deepPurple;
    case OrderStatus.goingToStore:
    case OrderStatus.reachedStore:
    case OrderStatus.orderCollected:
      return Colors.indigo;
    case OrderStatus.outForDelivery:
      return Colors.teal;
    case OrderStatus.delivered:
      return Colors.green;
    case OrderStatus.rejected:
      return Colors.red;
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

bool _canCancelOrder(OrderStatus status) {
  return status != OrderStatus.delivered && status != OrderStatus.cancelled;
}

bool _canTransitionOrderStatus(OrderStatus current, OrderStatus next) {
  // Dispatch can safely cancel an active order, but the delivery partner is
  // the source of truth for every forward delivery milestone.
  return next == OrderStatus.cancelled && _canCancelOrder(current);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(
      quickDropAdminMessagingBackgroundHandler,
    );
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.authStateChanges});

  final Stream<User?>? authStateChanges;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0F766E),
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'QuickDrop Admin',
      debugShowCheckedModeBanner: false,
      navigatorKey: adminNavigatorKey,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF6F7FB),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: colorScheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: colorScheme.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
      home: AuthGate(authStateChanges: authStateChanges),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key, this.authStateChanges});

  final Stream<User?>? authStateChanges;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: authStateChanges ?? FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user != null) {
          return _AdminClaimGate(user: user);
        }

        return const LoginPage();
      },
    );
  }
}

class _AdminClaimGate extends StatefulWidget {
  const _AdminClaimGate({required this.user});

  final User user;

  @override
  State<_AdminClaimGate> createState() => _AdminClaimGateState();
}

class _AdminClaimGateState extends State<_AdminClaimGate> {
  bool _isChecking = true;
  bool _isAdmin = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _verifyAdminClaim();
  }

  Future<void> _verifyAdminClaim() async {
    if (!mounted) return;
    setState(() {
      _isChecking = true;
      _errorMessage = null;
    });

    try {
      final token = await widget.user.getIdTokenResult(true);
      if (!mounted) return;
      setState(() {
        _isAdmin = token.claims?['admin'] == true;
      });
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _isAdmin = false;
        _errorMessage = error.message ?? 'Unable to verify admin access.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_isAdmin) {
      return const DashboardPage();
    }

    return _AdminAccessDeniedPage(
      email: widget.user.email,
      errorMessage: _errorMessage,
      onRetry: _verifyAdminClaim,
      onLogout: () async {
        await FirebaseAuth.instance.signOut();
      },
    );
  }
}

class _AdminAccessDeniedPage extends StatelessWidget {
  const _AdminAccessDeniedPage({
    required this.email,
    required this.onRetry,
    required this.onLogout,
    this.errorMessage,
  });

  final String? email;
  final String? errorMessage;
  final Future<void> Function() onRetry;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.lock_person_outlined, size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      'Admin access required',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      errorMessage ??
                          'This account is signed in, but does not have administrator permissions.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (email != null && email!.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Signed in as: ${email!.trim()}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh Access'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: onLogout,
                      icon: const Icon(Icons.logout),
                      label: const Text('Sign Out'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      // Force refresh so newly assigned custom claims can be read immediately.
      await credential.user?.getIdTokenResult(true);
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message ?? 'Login failed.')));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x12000000),
                      blurRadius: 24,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: colorScheme.primaryContainer,
                        child: Icon(
                          Icons.local_shipping_rounded,
                          color: colorScheme.onPrimaryContainer,
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'QuickDrop Admin',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Sign in to manage deliveries and operations.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 28),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Enter your email.';
                          }
                          if (!value.contains('@')) {
                            return 'Enter a valid email.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _login(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Enter your password.';
                          }
                          if (value.length < 6) {
                            return 'Password must be at least 6 characters.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _isLoading ? null : _login,
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Login'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final CollectionReference<Map<String, dynamic>> _ordersRef = FirebaseFirestore
      .instance
      .collection('orders');
  final AudioPlayer _notificationPlayer = AudioPlayer();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ordersSubscription;
  bool _hasLoadedInitialOrders = false;
  bool _isDialogVisible = false;
  int _pendingOrderCount = 0;

  @override
  void initState() {
    super.initState();
    quickDropAdminNotificationService = QuickDropAdminNotificationService(
      onOrderTap: _openAdminOrderDetails,
    );
    unawaited(quickDropAdminNotificationService.initialize());
    _ordersSubscription = _ordersRef.snapshots().listen(_handleOrdersSnapshot);
  }

  void _handleOrdersSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    debugPrint(
      'Dashboard orders snapshot: docs=${snapshot.docs.length}, changes=${snapshot.docChanges.length}',
    );

    final pendingCount = snapshot.docs.where((doc) {
      final status = doc.data()['status']?.toString().toLowerCase() ?? '';
      return status == 'pending';
    }).length;

    if (mounted) {
      setState(() {
        _pendingOrderCount = pendingCount;
      });
    }

    if (!_hasLoadedInitialOrders) {
      debugPrint('Initial orders snapshot loaded, skipping notification.');
      _hasLoadedInitialOrders = true;
      return;
    }

    final hasNewOrder = snapshot.docChanges.any(
      (change) => change.type == DocumentChangeType.added,
    );
    debugPrint('New order detected in changes: $hasNewOrder');

    if (hasNewOrder) {
      unawaited(_showNewOrderNotification());
    }
  }

  Future<void> _showNewOrderNotification() async {
    debugPrint('Attempting to show new order notification UI.');

    if (!mounted || !context.mounted) {
      debugPrint('Notification skipped because context is not mounted.');
      return;
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      debugPrint(
        'Notification skipped because ScaffoldMessenger is unavailable.',
      );
      return;
    }

    if (!_isDialogVisible) {
      _isDialogVisible = true;
      debugPrint('Showing new order AlertDialog.');
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: true,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('New Order'),
              content: const Text('🔔 New Order Received'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        ).whenComplete(() {
          _isDialogVisible = false;
          debugPrint('New order AlertDialog closed.');
        }),
      );
    } else {
      debugPrint('Dialog already visible, skipping additional dialog.');
    }

    if (!mounted || !context.mounted) {
      debugPrint('SnackBar skipped because context is not mounted.');
      return;
    }

    debugPrint('Showing new order SnackBar and playing notification sound.');
    messenger.clearSnackBars();
    messenger.showSnackBar(
      const SnackBar(content: Text('🔔 New Order Received')),
    );

    if (!mounted || !context.mounted) {
      debugPrint('Notification sound skipped because context is not mounted.');
      return;
    }

    unawaited(_playNewOrderSound());
  }

  Future<void> _playNewOrderSound() async {
    try {
      await _notificationPlayer.play(AssetSource('sounds/file/quickdrop.mp3'));
      debugPrint('New order notification sound played.');
    } catch (error) {
      debugPrint('Failed to play notification sound: $error');
    }
  }

  @override
  void dispose() {
    _ordersSubscription?.cancel();
    _notificationPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        centerTitle: false,
        actions: [
          TextButton.icon(
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
            icon: const Icon(Icons.logout),
            label: const Text('Logout'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [colorScheme.primary, colorScheme.tertiary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  user?.email ?? 'Admin',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: colorScheme.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Monitor account activity, deliveries, and service operations from one place.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onPrimary.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          GridView.count(
            crossAxisCount: MediaQuery.of(context).size.width > 720 ? 3 : 1,
            shrinkWrap: true,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.7,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _DashboardCard(
                icon: Icons.inventory_2_outlined,
                title: 'Orders',
                subtitle: _pendingOrderCount > 0
                    ? 'View and manage requests • $_pendingOrderCount pending'
                    : 'View and manage requests',
                onTap: () {
                  Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const OrdersPage()));
                },
              ),
              const _DashboardCard(
                icon: Icons.delivery_dining_outlined,
                title: 'Deliveries',
                subtitle: 'Track active deliveries',
              ),
              const _DashboardCard(
                icon: Icons.people_outline,
                title: 'Customers',
                subtitle: 'Review customer activity',
              ),
              _DashboardCard(
                icon: Icons.storefront_outlined,
                title: 'Products',
                subtitle: 'Manage catalog and stock',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ProductManagementPage(),
                    ),
                  );
                },
              ),
              _DashboardCard(
                icon: Icons.inventory_outlined,
                title: '\u{1F4E6} Stock Management',
                subtitle: 'Track and update product stock',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const StockManagementPage(),
                    ),
                  );
                },
              ),
              _DashboardCard(
                icon: Icons.store_mall_directory_outlined,
                title: 'Shop Management',
                subtitle: 'Manage shops and shop inventory',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ShopManagementPage(),
                    ),
                  );
                },
              ),
              _DashboardCard(
                icon: Icons.view_carousel_outlined,
                title: 'Banner Management',
                subtitle: 'Manage banners',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const BannerManagementPage(),
                    ),
                  );
                },
              ),
              _DashboardCard(
                icon: Icons.local_shipping_outlined,
                title: 'Delivery Settings',
                subtitle: 'Hub, radius, charges and store timing',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsPage()),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: colorScheme.outline,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  static const List<OrderStatus?> _statusTabs = <OrderStatus?>[
    null,
    OrderStatus.pending,
    OrderStatus.accepted,
    OrderStatus.packed,
    OrderStatus.goingToStore,
    OrderStatus.reachedStore,
    OrderStatus.orderCollected,
    OrderStatus.outForDelivery,
    OrderStatus.delivered,
    OrderStatus.rejected,
    OrderStatus.cancelled,
  ];

  OrderStatus? _selectedStatus = OrderStatus.pending;
  final RiderAssignmentService _riderAssignmentService =
      RiderAssignmentService();

  /// Reserves the nearest eligible rider. The order deliberately remains
  /// pending until that rider accepts it in the Delivery App.
  Future<void> _assignNearestRider(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    OrderStatus currentStatus,
  ) async {
    if (currentStatus != OrderStatus.pending) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only pending orders can be assigned.')),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);

    try {
      final rider = await _riderAssignmentService.assignNearestRider(
        orderRef: doc.reference,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Order assigned to ${rider.name} '
            '(${rider.distanceKm.toStringAsFixed(1)} km away). '
            'Waiting for rider acceptance.',
          ),
        ),
      );
    } on NoRiderAvailableException {
      final reason = await _lockedRidersSummary();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'No available rider nearby. The order remains pending.$reason',
          ),
          duration: const Duration(seconds: 8),
        ),
      );
    } on RiderAssignmentException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } on FirebaseException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(error.message ?? 'Failed to accept order.')),
      );
    }
  }

  Future<String> _lockedRidersSummary() async {
    try {
      final locked = await _riderAssignmentService.diagnoseLockedRiders();
      if (locked.isEmpty) {
        return '';
      }
      return '\n${locked.map((d) => d.description).join('\n')}';
    } catch (_) {
      return '';
    }
  }

  Future<void> _updateOrderStatus(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    OrderStatus currentStatus,
    OrderStatus nextStatus,
  ) async {
    if (!_canTransitionOrderStatus(currentStatus, nextStatus)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid order status transition.')),
      );
      return;
    }

    try {
      final updateData = <String, dynamic>{
        'status': nextStatus.label,
        'statusUpdatedAt': Timestamp.now(),
        'statusHistory': FieldValue.arrayUnion([
          {'status': nextStatus.label, 'updatedAt': Timestamp.now()},
        ]),
      };

      final paymentMethod = doc.data()['paymentMethod']?.toString().trim();
      if (nextStatus == OrderStatus.delivered &&
          paymentMethod == 'Cash on Delivery') {
        updateData['paymentStatus'] = 'Paid';
      }

      await doc.reference.update(updateData);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order updated to ${nextStatus.label}.')),
      );
    } on FirebaseException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? 'Failed to update order.')),
      );
    }
  }

  Future<void> _cancelOrder(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    OrderStatus currentStatus,
  ) async {
    await _updateOrderStatus(
      context,
      doc,
      currentStatus,
      OrderStatus.cancelled,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Orders')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('orders').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 36,
                      color: colorScheme.error,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Failed to load orders.',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final activeSnapshot = snapshot.data;
          if (snapshot.connectionState == ConnectionState.waiting &&
              activeSnapshot == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = activeSnapshot?.docs ?? [];
          final filteredDocs = docs.where((doc) {
            final data = doc.data();
            final orderStatus = _orderStatusFromValue(data['status']);
            return _selectedStatus == null || orderStatus == _selectedStatus;
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _statusTabs.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final status = _statusTabs[index];
                      final label = status == null ? 'All' : status.label;
                      final isSelected = _selectedStatus == status;

                      return ChoiceChip(
                        label: Text(label),
                        selected: isSelected,
                        onSelected: (_) {
                          setState(() {
                            _selectedStatus = status;
                          });
                        },
                        selectedColor: colorScheme.primaryContainer,
                        labelStyle: TextStyle(
                          color: isSelected
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      );
                    },
                  ),
                ),
              ),
              Expanded(
                child: filteredDocs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.inventory_2_outlined,
                              size: 40,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No orders found.',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'New orders will appear here in real time.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: filteredDocs.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final doc = filteredDocs[index];
                          final data = doc.data();

                          final orderId = _displayValue(data['orderId']);
                          final customerName = _displayValue(
                            data['customerName'] ??
                                data['name'] ??
                                data['ownerName'],
                          );
                          final phone = _displayValue(
                            data['phoneNumber'] ??
                                data['phone'] ??
                                data['ownerPhone'],
                          );
                          final address = _displayValue(
                            data['deliveryAddress'] ?? data['address'],
                          );
                          final orderStatus = _orderStatusFromValue(
                            data['status'],
                          );
                          final statusLabel =
                              orderStatus == OrderStatus.cancelled
                              ? 'Order Cancelled'
                              : orderStatus.label;
                          final statusColor = _orderStatusColor(orderStatus);
                          final statusIcon = _orderStatusIcon(orderStatus);
                          final paymentMethod = _displayValue(
                            data['paymentMethod'],
                          );
                          final paymentStatus = _displayValue(
                            data['paymentStatus'],
                          );
                          final paymentIdValue =
                              data['paymentId']?.toString().trim() ?? '';
                          final paymentId = paymentIdValue.isEmpty
                              ? null
                              : paymentIdValue;
                          final totalAmount = _displayAmount(
                            data['totalAmount'],
                          );
                          final hasReservedRider =
                              (data['assignedPartnerId'] ?? '')
                                  .toString()
                                  .trim()
                                  .isNotEmpty;

                          return Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: colorScheme.outlineVariant,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Order #$orderId',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                      Chip(
                                        avatar: Icon(
                                          statusIcon,
                                          size: 16,
                                          color: statusColor,
                                        ),
                                        label: Text(statusLabel),
                                        backgroundColor: statusColor.withValues(
                                          alpha: 0.12,
                                        ),
                                        side: BorderSide(
                                          color: statusColor.withValues(
                                            alpha: 0.22,
                                          ),
                                        ),
                                        labelStyle: TextStyle(
                                          color: statusColor,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  _OrderDetailRow(
                                    label: 'Customer',
                                    value: customerName,
                                  ),
                                  _OrderDetailRow(label: 'Phone', value: phone),
                                  _OrderDetailRow(
                                    label: 'Address',
                                    value: address,
                                  ),
                                  _OrderDetailRow(
                                    label: 'Payment Method',
                                    value: paymentMethod,
                                  ),
                                  _OrderDetailRow(
                                    label: 'Payment Status',
                                    value: paymentStatus,
                                  ),
                                  if (paymentId != null)
                                    _OrderDetailRow(
                                      label: 'Payment ID',
                                      value: paymentId,
                                    ),
                                  _OrderDetailRow(
                                    label: 'Total',
                                    value: totalAmount,
                                  ),
                                  const SizedBox(height: 6),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      onPressed: () =>
                                          _openAdminOrderDetails(orderId),
                                      icon: const Icon(
                                        Icons.visibility_outlined,
                                      ),
                                      label: const Text('View Details'),
                                    ),
                                  ),
                                  if (_canCancelOrder(orderStatus)) ...[
                                    const SizedBox(height: 6),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton.icon(
                                        onPressed: () => _cancelOrder(
                                          context,
                                          doc,
                                          orderStatus,
                                        ),
                                        icon: const Icon(Icons.cancel_outlined),
                                        label: const Text('Cancel'),
                                      ),
                                    ),
                                  ],
                                  if (orderStatus == OrderStatus.pending &&
                                      !hasReservedRider) ...[
                                    const SizedBox(height: 6),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton.icon(
                                        onPressed: () => _assignNearestRider(
                                          context,
                                          doc,
                                          orderStatus,
                                        ),
                                        icon: const Icon(
                                          Icons.check_circle_outline,
                                        ),
                                        label: const Text('Assign nearest rider'),
                                      ),
                                    ),
                                  ],
                                  if (orderStatus == OrderStatus.pending &&
                                      hasReservedRider) ...[
                                    const SizedBox(height: 6),
                                    const Align(
                                      alignment: Alignment.centerRight,
                                      child: Text(
                                        'Waiting for rider acceptance',
                                        style: TextStyle(
                                          color: Colors.blueGrey,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OrderDetailRow extends StatelessWidget {
  const _OrderDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              '$label:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }
}

String _displayValue(dynamic value) {
  if (value == null) {
    return '-';
  }

  final text = value.toString().trim();
  return text.isEmpty ? '-' : text;
}

String _displayAmount(dynamic value) {
  if (value == null) {
    return '-';
  }

  if (value is num) {
    return value.toStringAsFixed(2);
  }

  return _displayValue(value);
}

class ProductManagementPage extends StatefulWidget {
  const ProductManagementPage({super.key});

  @override
  State<ProductManagementPage> createState() => _ProductManagementPageState();
}

class _ProductManagementPageState extends State<ProductManagementPage> {
  final CollectionReference<Map<String, dynamic>> _productsRef =
      FirebaseFirestore.instance.collection('products');
  static final List<String> _mainCategories = categorySubcategoryMap.keys
      .toSet()
      .toList();
  static const List<String> _productCategoryFilters = [
    'Grocery',
    'Vegetables',
    'Fruits',
    'Food',
    'Gifts',
    'Gifts & Surprises',
    'Cosmetics',
    'Electronics',
  ];
  static const List<String> _unitOptions = ['g', 'kg', 'ml', 'L', 'pcs'];
  static const List<String> _csvColumns = [
    'name',
    'price',
    'category',
    'subcategory',
    'childCategory',
    'imageUrl',
    'stock',
    'brand',
    'weight',
    'unit',
    'oldPrice',
    'discount',
    'shortDescription',
  ];
  // Firestore allows 500 writes per batch; stay below it for safety.
  static const int _importBatchSize = 400;
  static const List<String> _imageExtensions = ['jpg', 'jpeg', 'png', 'webp'];
  static const int _maxProductImages = 4;
  String? _selectedProductCategory;
  String _searchQuery = '';

  // Dropdowns crash on duplicate or missing values, so keep options unique and
  // always include the value currently stored on the product.
  List<String> _dropdownOptions(List<String> options, String? currentValue) {
    final values = <String>{
      ...options.map((option) => option.trim()).where((o) => o.isNotEmpty),
    };
    final current = currentValue?.trim() ?? '';
    if (current.isNotEmpty) {
      values.add(current);
    }
    return values.toList();
  }

  String _contentTypeForExtension(String? extension) {
    switch ((extension ?? '').toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      default:
        return 'image/jpeg';
    }
  }

  Future<String> _uploadProductImageBytes(PlatformFile file) async {
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw Exception('Selected file has no data.');
    }

    final safeName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final path =
        'product_images/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    final ref = FirebaseStorage.instance.ref().child(path);

    await ref.putData(
      Uint8List.fromList(bytes),
      SettableMetadata(contentType: _contentTypeForExtension(file.extension)),
    );

    return ref.getDownloadURL();
  }

  // Older products only have `imageUrl`; treat it as the first gallery image.
  List<String> _existingImageUrls(Map<String, dynamic> data) {
    final urls = <String>[];
    final mainUrl = data['imageUrl']?.toString().trim() ?? '';
    if (mainUrl.isNotEmpty) {
      urls.add(mainUrl);
    }
    final rawUrls = data['imageUrls'];
    if (rawUrls is List) {
      for (final value in rawUrls) {
        final url = value?.toString().trim() ?? '';
        if (url.isNotEmpty && !urls.contains(url)) {
          urls.add(url);
        }
      }
    }
    return urls.take(_maxProductImages).toList();
  }

  Widget _photoThumbnail({
    required String url,
    required bool isMain,
    required VoidCallback? onSetMain,
    required VoidCallback? onRemove,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 96,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMain ? colorScheme.primary : colorScheme.outlineVariant,
          width: isMain ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              url,
              width: 84,
              height: 64,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox(
                width: 84,
                height: 64,
                child: Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
          Text(
            isMain ? 'Main Photo' : 'Photo',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Set as main photo',
                visualDensity: VisualDensity.compact,
                onPressed: onSetMain,
                icon: Icon(isMain ? Icons.star : Icons.star_border),
              ),
              IconButton(
                tooltip: 'Remove photo',
                visualDensity: VisualDensity.compact,
                onPressed: onRemove,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ],
      ),
    );
  }

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
    String initialCategoryValue = canonicalCategory(
      initialData?['category']?.toString() ?? '',
    );
    String? selectedCategory = _mainCategories.contains(initialCategoryValue)
        ? initialCategoryValue
        : (initialCategoryValue.trim().isEmpty ? null : initialCategoryValue);
    String? selectedSubcategory = initialData?['subcategory']
        ?.toString()
        .trim();
    if (selectedSubcategory != null && selectedSubcategory.isEmpty) {
      selectedSubcategory = null;
    }
    String? selectedChildCategory = initialData?['childCategory']
        ?.toString()
        .trim();
    if (selectedChildCategory != null && selectedChildCategory.isEmpty) {
      selectedChildCategory = null;
    }
    final imageUrlController = TextEditingController(
      text: initialData?['imageUrl']?.toString() ?? '',
    );
    final productImageUrls = _existingImageUrls(initialData ?? const {});
    final stockController = TextEditingController(
      text: initialData?['stock']?.toString() ?? '',
    );
    final brandController = TextEditingController(
      text: initialData?['brand']?.toString() ?? '',
    );
    final weightController = TextEditingController(
      text: initialData?['weight']?.toString() ?? '',
    );
    final oldPriceController = TextEditingController(
      text: initialData?['oldPrice']?.toString() ?? '',
    );
    final discountController = TextEditingController(
      text: initialData?['discount']?.toString() ?? '',
    );
    final shortDescriptionController = TextEditingController(
      text: initialData?['shortDescription']?.toString() ?? '',
    );
    const unitOptions = _unitOptions;
    String selectedUnit = unitOptions.contains(initialData?['unit']?.toString())
        ? initialData!['unit'].toString()
        : 'g';
    bool isImageUploading = false;
    String selectedImageLabel = productImageUrls.isEmpty
        ? 'No photos added yet'
        : '${productImageUrls.length} of $_maxProductImages photo(s) added';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
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
                            return 'Please enter product name';
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
                          if (price == null || price <= 0) {
                            return 'Price must be greater than 0';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: selectedCategory,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                        ),
                        items:
                            _dropdownOptions(_mainCategories, selectedCategory)
                                .map(
                                  (category) => DropdownMenuItem<String>(
                                    value: category,
                                    child: Text(category),
                                  ),
                                )
                                .toList(),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedCategory = value;
                            selectedSubcategory = null;
                            selectedChildCategory = null;
                          });
                        },
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please select category';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        // Rebuild the field when the parent changes so the stale
                        // selection is dropped along with its options.
                        key: ValueKey('subcategory-$selectedCategory'),
                        initialValue: selectedSubcategory,
                        decoration: const InputDecoration(
                          labelText: 'Subcategory',
                        ),
                        items:
                            _dropdownOptions(
                                  buildSubcategoryOptions(
                                    selectedCategory ?? '',
                                  ),
                                  selectedSubcategory,
                                )
                                .map(
                                  (subcategory) => DropdownMenuItem<String>(
                                    value: subcategory,
                                    child: Text(subcategory),
                                  ),
                                )
                                .toList(),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedSubcategory = value;
                            selectedChildCategory = null;
                          });
                        },
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please select subcategory';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        key: ValueKey('childCategory-$selectedSubcategory'),
                        initialValue: selectedChildCategory,
                        decoration: const InputDecoration(
                          labelText: 'Child Category',
                        ),
                        items:
                            _dropdownOptions(
                                  buildChildCategoryOptions(
                                    selectedSubcategory,
                                  ),
                                  selectedChildCategory,
                                )
                                .map(
                                  (childCategory) => DropdownMenuItem<String>(
                                    value: childCategory,
                                    child: Text(childCategory),
                                  ),
                                )
                                .toList(),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedChildCategory = value;
                          });
                        },
                        validator: (value) {
                          final hasChildCategories = buildChildCategoryOptions(
                            selectedSubcategory,
                          ).isNotEmpty;
                          if (hasChildCategories &&
                              (value == null || value.trim().isEmpty)) {
                            return 'Please select child category';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Product Photos',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (productImageUrls.isNotEmpty)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (var i = 0; i < productImageUrls.length; i++)
                              _photoThumbnail(
                                url: productImageUrls[i],
                                isMain: i == 0,
                                onSetMain: i == 0 || isImageUploading
                                    ? null
                                    : () {
                                        setDialogState(() {
                                          final url = productImageUrls.removeAt(
                                            i,
                                          );
                                          productImageUrls.insert(0, url);
                                          imageUrlController.text = url;
                                        });
                                      },
                                onRemove: isImageUploading
                                    ? null
                                    : () {
                                        setDialogState(() {
                                          productImageUrls.removeAt(i);
                                          imageUrlController.text =
                                              productImageUrls.isEmpty
                                              ? ''
                                              : productImageUrls.first;
                                          selectedImageLabel =
                                              productImageUrls.isEmpty
                                              ? 'No photos added yet'
                                              : '${productImageUrls.length} of $_maxProductImages photo(s) added';
                                        });
                                      },
                              ),
                          ],
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              selectedImageLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed:
                                isImageUploading ||
                                    productImageUrls.length >= _maxProductImages
                                ? null
                                : () async {
                                    final messenger = ScaffoldMessenger.of(
                                      context,
                                    );
                                    setDialogState(() {
                                      isImageUploading = true;
                                      selectedImageLabel =
                                          'Uploading photos...';
                                    });

                                    var uploaded = 0;
                                    var failed = 0;
                                    try {
                                      final picked = await FilePicker.platform.
                                          pickFiles(
                                            allowMultiple: true,
                                            type: FileType.custom,
                                            allowedExtensions: _imageExtensions,
                                            withData: true,
                                          );
                                      for (final file
                                          in picked?.files ??
                                              const <PlatformFile>[]) {
                                        if (productImageUrls.length >=
                                            _maxProductImages) {
                                          break;
                                        }
                                        try {
                                          final url =
                                              await _uploadProductImageBytes(
                                                file,
                                              );
                                          if (!productImageUrls.contains(url)) {
                                            productImageUrls.add(url);
                                            uploaded++;
                                          }
                                        } catch (_) {
                                          failed++;
                                        }
                                      }
                                    } finally {
                                      if (dialogContext.mounted) {
                                        setDialogState(() {
                                          isImageUploading = false;
                                          imageUrlController.text =
                                              productImageUrls.isEmpty
                                              ? ''
                                              : productImageUrls.first;
                                          selectedImageLabel =
                                              productImageUrls.isEmpty
                                              ? 'No photos added yet'
                                              : '${productImageUrls.length} of $_maxProductImages photo(s) added';
                                        });
                                      }
                                    }

                                    if (dialogContext.mounted &&
                                        (uploaded > 0 || failed > 0)) {
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '$uploaded photo(s) uploaded'
                                            '${failed > 0 ? ', $failed failed' : ''}',
                                          ),
                                        ),
                                      );
                                    }
                                  },
                            icon: isImageUploading
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.add_photo_alternate_outlined,
                                  ),
                            label: const Text('Add Photos'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _productField(
                        controller: imageUrlController,
                        label: 'Image URL',
                      ),
                      const SizedBox(height: 10),
                      _productField(
                        controller: stockController,
                        label: 'Stock Quantity',
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          final stock = int.tryParse(value?.trim() ?? '');
                          if (stock == null || stock < 0) {
                            return 'Enter valid stock';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      _productField(
                        controller: brandController,
                        label: 'Brand',
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _productField(
                              controller: weightController,
                              label: 'Weight',
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedUnit,
                              decoration: const InputDecoration(
                                labelText: 'Unit',
                              ),
                              items: unitOptions
                                  .map(
                                    (unit) => DropdownMenuItem<String>(
                                      value: unit,
                                      child: Text(unit),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                setDialogState(() {
                                  selectedUnit = value ?? selectedUnit;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _productField(
                        controller: oldPriceController,
                        label: 'Old Price (MRP)',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (value) {
                          final text = value?.trim() ?? '';
                          if (text.isEmpty) {
                            return null;
                          }
                          final oldPrice = double.tryParse(text);
                          if (oldPrice == null || oldPrice < 0) {
                            return 'Enter a valid old price';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      _productField(
                        controller: discountController,
                        label: 'Discount %',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (value) {
                          final text = value?.trim() ?? '';
                          if (text.isEmpty) {
                            return null;
                          }
                          final discount = double.tryParse(text);
                          if (discount == null ||
                              discount < 0 ||
                              discount > 100) {
                            return 'Enter a valid discount (0-100)';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      _productField(
                        controller: shortDescriptionController,
                        label: 'Short Description',
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

                    final messenger = ScaffoldMessenger.of(context);

                    final manualUrl = imageUrlController.text.trim();
                    if (manualUrl.isNotEmpty &&
                        !productImageUrls.contains(manualUrl)) {
                      productImageUrls.insert(0, manualUrl);
                    }
                    final galleryUrls = productImageUrls
                        .take(_maxProductImages)
                        .toList();

                    final data = {
                      'name': nameController.text.trim(),
                      'price': double.parse(priceController.text.trim()),
                      'category': canonicalCategory(selectedCategory ?? ''),
                      'subcategory': selectedSubcategory?.trim() ?? '',
                      'childCategory': selectedChildCategory?.trim() ?? '',
                      'imageUrl': galleryUrls.isEmpty ? '' : galleryUrls.first,
                      'imageUrls': galleryUrls,
                      'stock': int.parse(stockController.text.trim()),
                      'brand': brandController.text.trim(),
                      'weight': weightController.text.trim(),
                      'unit': selectedUnit,
                      'oldPrice':
                          double.tryParse(oldPriceController.text.trim()) ??
                          0.0,
                      'discount':
                          double.tryParse(discountController.text.trim()) ??
                          0.0,
                      'shortDescription': shortDescriptionController.text
                          .trim(),
                    };

                    try {
                      if (documentId == null) {
                        await _productsRef.add(data);
                      } else {
                        await _productsRef.doc(documentId).update(data);
                      }

                      if (!mounted || !dialogContext.mounted) {
                        return;
                      }

                      Navigator.pop(dialogContext);
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            documentId == null
                                ? 'Product added successfully'
                                : 'Product updated successfully',
                          ),
                        ),
                      );
                    } on FirebaseException catch (error) {
                      if (!mounted) {
                        return;
                      }
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            error.message ?? 'Failed to save product',
                          ),
                        ),
                      );
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    priceController.dispose();
    imageUrlController.dispose();
    stockController.dispose();
    brandController.dispose();
    weightController.dispose();
    oldPriceController.dispose();
    discountController.dispose();
    shortDescriptionController.dispose();
  }

  String _csvCell(List<dynamic> row, Map<String, int> columns, String key) {
    final index = columns[key];
    if (index == null || index >= row.length) {
      return '';
    }
    return row[index]?.toString().trim() ?? '';
  }

  String _duplicateKey(String name, String category, String unit) {
    return '${name.toLowerCase()}|${category.toLowerCase()}|${unit.toLowerCase()}';
  }

  Future<void> _importProductsFromCsv() async {
    final messenger = ScaffoldMessenger.of(context);

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      withData: true,
    );

    if (picked == null || picked.files.isEmpty) {
      return;
    }

    final bytes = picked.files.first.bytes;
    if (bytes == null || bytes.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Selected CSV file is empty.')),
      );
      return;
    }

    List<List<dynamic>> rows;
    try {
      final content = utf8
          .decode(bytes, allowMalformed: true)
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n');
      rows = const CsvToListConverter(
        eol: '\n',
        shouldParseNumbers: false,
      ).convert(content);
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Unable to read CSV file: $error')),
      );
      return;
    }

    rows = rows
        .where(
          (row) =>
              row.any((cell) => (cell?.toString().trim() ?? '').isNotEmpty),
        )
        .toList();

    if (rows.length < 2) {
      messenger.showSnackBar(
        const SnackBar(content: Text('CSV must have a header row and data.')),
      );
      return;
    }

    final headerRow = rows.first
        .map((cell) => cell?.toString().trim() ?? '')
        .toList();
    final columns = <String, int>{};
    for (final column in _csvColumns) {
      final index = headerRow.indexWhere(
        (header) => header.toLowerCase() == column.toLowerCase(),
      );
      if (index != -1) {
        columns[column] = index;
      }
    }

    final missingRequired = [
      'name',
      'price',
      'category',
      'subcategory',
      'stock',
    ].where((column) => !columns.containsKey(column)).toList();
    if (missingRequired.isNotEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'CSV is missing required columns: ${missingRequired.join(', ')}',
          ),
        ),
      );
      return;
    }

    final existingSnapshot = await _productsRef.get();
    final existingKeys = existingSnapshot.docs.map((doc) {
      final data = doc.data();
      return _duplicateKey(
        data['name']?.toString().trim() ?? '',
        data['category']?.toString().trim() ?? '',
        data['unit']?.toString().trim() ?? '',
      );
    }).toSet();

    final validProducts = <Map<String, dynamic>>[];
    var skippedCount = 0;
    var duplicateCount = 0;

    for (final row in rows.skip(1)) {
      final name = _csvCell(row, columns, 'name');
      final category = canonicalCategory(_csvCell(row, columns, 'category'));
      final subcategory = _csvCell(row, columns, 'subcategory');
      final price = double.tryParse(_csvCell(row, columns, 'price'));
      final stock = int.tryParse(_csvCell(row, columns, 'stock'));
      final rawUnit = _csvCell(row, columns, 'unit');
      final unit = _unitOptions.firstWhere(
        (option) => option.toLowerCase() == rawUnit.toLowerCase(),
        orElse: () => '',
      );

      if (name.isEmpty ||
          category.isEmpty ||
          subcategory.isEmpty ||
          price == null ||
          price <= 0 ||
          stock == null ||
          stock < 0 ||
          (rawUnit.isNotEmpty && unit.isEmpty)) {
        skippedCount++;
        continue;
      }

      final resolvedUnit = unit.isEmpty ? _unitOptions.first : unit;
      final key = _duplicateKey(name, category, resolvedUnit);
      if (existingKeys.contains(key)) {
        duplicateCount++;
        continue;
      }
      existingKeys.add(key);

      validProducts.add({
        'name': name,
        'price': price,
        'category': category,
        'subcategory': subcategory,
        'childCategory': _csvCell(row, columns, 'childCategory'),
        'imageUrl': _csvCell(row, columns, 'imageUrl'),
        'stock': stock,
        'brand': _csvCell(row, columns, 'brand'),
        'weight': _csvCell(row, columns, 'weight'),
        'unit': resolvedUnit,
        'oldPrice': double.tryParse(_csvCell(row, columns, 'oldPrice')) ?? 0.0,
        'discount': double.tryParse(_csvCell(row, columns, 'discount')) ?? 0.0,
        'shortDescription': _csvCell(row, columns, 'shortDescription'),
      });
    }

    if (!mounted) {
      return;
    }

    if (validProducts.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'No products to import. '
            '$skippedCount invalid row(s), $duplicateCount duplicate(s) skipped.',
          ),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Import Products'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${validProducts.length} product(s) will be imported.'),
              if (skippedCount > 0) ...[
                const SizedBox(height: 6),
                Text('$skippedCount invalid row(s) will be skipped.'),
              ],
              if (duplicateCount > 0) ...[
                const SizedBox(height: 6),
                Text('$duplicateCount duplicate row(s) will be skipped.'),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Import'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    final progress = ValueNotifier<int>(0);
    final navigator = Navigator.of(context);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            content: Row(
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ValueListenableBuilder<int>(
                    valueListenable: progress,
                    builder: (context, value, _) {
                      return Text(
                        'Importing products... $value / ${validProducts.length}',
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    var importedCount = 0;
    String? importError;

    try {
      for (
        var start = 0;
        start < validProducts.length;
        start += _importBatchSize
      ) {
        final end = (start + _importBatchSize) > validProducts.length
            ? validProducts.length
            : start + _importBatchSize;
        final batch = FirebaseFirestore.instance.batch();
        for (final product in validProducts.sublist(start, end)) {
          batch.set(_productsRef.doc(), product);
        }
        await batch.commit();
        importedCount = end;
        progress.value = importedCount;
      }
    } on FirebaseException catch (error) {
      importError = error.message ?? 'Failed to import products.';
    } finally {
      navigator.pop();
      progress.dispose();
    }

    if (!mounted) {
      return;
    }

    if (importError != null) {
      messenger.showSnackBar(SnackBar(content: Text(importError)));
      return;
    }

    final details = <String>[
      if (skippedCount > 0) '$skippedCount invalid row(s) skipped',
      if (duplicateCount > 0) '$duplicateCount duplicate(s) skipped',
    ];
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '$importedCount products imported successfully'
          '${details.isEmpty ? '' : ' • ${details.join(', ')}'}',
        ),
      ),
    );
    setState(() {});
  }

  String _normalizedProductKey(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  Future<void> _bulkUploadProductImages() async {
    final messenger = ScaffoldMessenger.of(context);

    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: _imageExtensions,
      withData: true,
    );

    if (picked == null || picked.files.isEmpty || !mounted) {
      return;
    }

    final files = picked.files;
    final snapshot = await _productsRef.get();
    final productsByKey =
        <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final doc in snapshot.docs) {
      final key = _normalizedProductKey(
        doc.data()['name']?.toString().trim() ?? '',
      );
      if (key.isNotEmpty) {
        productsByKey.putIfAbsent(key, () => doc);
      }
    }

    // Files like `instant_coffee_2.jpg` become extra photos for the product.
    final groupedFiles = <String, List<PlatformFile>>{};
    final matchedDocs = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    var unmatchedCount = 0;

    for (final file in files) {
      final baseName = file.name.contains('.')
          ? file.name.substring(0, file.name.lastIndexOf('.'))
          : file.name;
      final key = _normalizedProductKey(baseName);
      final doc =
          productsByKey[key] ??
          productsByKey[key.replaceAll(RegExp(r'_\d+$'), '')];

      if (doc == null) {
        unmatchedCount++;
        continue;
      }

      matchedDocs[doc.id] = doc;
      groupedFiles.putIfAbsent(doc.id, () => <PlatformFile>[]).add(file);
    }

    final matchedFileCount = groupedFiles.values.fold<int>(
      0,
      (total, list) => total + list.length,
    );

    if (!mounted) {
      return;
    }

    final progress = ValueNotifier<int>(0);
    final navigator = Navigator.of(context);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            content: Row(
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ValueListenableBuilder<int>(
                    valueListenable: progress,
                    builder: (context, value, _) {
                      return Text(
                        'Uploading images... $value / $matchedFileCount',
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    var uploadedCount = 0;
    var failedCount = 0;
    var skippedCount = 0;

    for (final entry in groupedFiles.entries) {
      final doc = matchedDocs[entry.key]!;
      final existingUrls = _existingImageUrls(doc.data());
      final urls = [...existingUrls];

      for (final file in entry.value) {
        if (urls.length >= _maxProductImages) {
          skippedCount++;
        } else {
          try {
            final url = await _uploadProductImageBytes(file);
            if (!urls.contains(url)) {
              urls.add(url);
            }
            uploadedCount++;
          } catch (_) {
            failedCount++;
          }
        }
        progress.value = progress.value + 1;
      }

      if (!listEquals(urls, existingUrls) && urls.isNotEmpty) {
        await doc.reference.update({'imageUrl': urls.first, 'imageUrls': urls});
      }
    }

    navigator.pop();
    progress.dispose();

    if (!mounted) {
      return;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '$uploadedCount image(s) uploaded \u2022 '
          '$unmatchedCount unmatched \u2022 $skippedCount over limit \u2022 '
          '$failedCount failed',
        ),
      ),
    );
  }

  Future<void> _deleteProduct(String id) async {
    try {
      await _productsRef.doc(id).delete();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Product deleted')));
    } on FirebaseException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? 'Failed to delete product')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Management'),
        actions: [
          TextButton.icon(
            onPressed: _bulkUploadProductImages,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Bulk Image Upload'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'importCsvProducts',
            onPressed: _importProductsFromCsv,
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Import CSV'),
          ),
          const SizedBox(width: 12),
          FloatingActionButton.extended(
            heroTag: 'addProduct',
            onPressed: () => _showProductDialog(),
            icon: const Icon(Icons.add),
            label: const Text('Add Product'),
          ),
        ],
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
                ),
              ),
            );
          }

          final products = [...(snapshot.data?.docs ?? [])]
            ..sort((a, b) {
              final aName = a.data()['name']?.toString() ?? '';
              final bName = b.data()['name']?.toString() ?? '';
              return aName.toLowerCase().compareTo(bName.toLowerCase());
            });

          int productCount(String? category) {
            if (category == null) {
              return products.length;
            }
            return products.where((doc) {
              return doc.data()['category']?.toString().trim() == category;
            }).length;
          }

          final filteredProducts = products.where((doc) {
            final data = doc.data();
            final matchesCategory =
                _selectedProductCategory == null ||
                data['category']?.toString().trim() == _selectedProductCategory;
            if (!matchesCategory) {
              return false;
            }
            if (_searchQuery.isEmpty) {
              return true;
            }
            final haystack = [
              data['name'],
              data['brand'],
              data['subcategory'],
              data['childCategory'],
            ].map((value) => value?.toString().toLowerCase() ?? '').join(' ');
            return haystack.contains(_searchQuery);
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value.trim().toLowerCase();
                    });
                  },
                  decoration: const InputDecoration(
                    hintText: 'Search products by name or brand',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _productCategoryFilters.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final category = index == 0
                          ? null
                          : _productCategoryFilters[index - 1];
                      final selected = _selectedProductCategory == category;
                      final label = category ?? 'All Products';

                      return ChoiceChip(
                        label: Text('$label (${productCount(category)})'),
                        selected: selected,
                        onSelected: (_) {
                          setState(() {
                            _selectedProductCategory = category;
                          });
                        },
                      );
                    },
                  ),
                ),
              ),
              Expanded(
                child: filteredProducts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.inventory_2_outlined,
                              size: 40,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'No products found',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                        itemCount: filteredProducts.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final doc = filteredProducts[index];
                          final data = doc.data();
                          final name =
                              data['name']?.toString() ?? 'Unnamed Product';
                          final price = data['price'];
                          final category =
                              data['category']?.toString() ?? 'General';
                          final stock = data['stock']?.toString() ?? '0';
                          final imageUrl =
                              data['imageUrl']?.toString().trim() ?? '';

                          return Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: colorScheme.outlineVariant,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: imageUrl.isEmpty
                                            ? Container(
                                                width: 56,
                                                height: 56,
                                                color: colorScheme
                                                    .surfaceContainerHighest,
                                                child: const Icon(
                                                  Icons.image_outlined,
                                                ),
                                              )
                                            : Image.network(
                                                imageUrl,
                                                width: 56,
                                                height: 56,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, _, _) => Container(
                                                  width: 56,
                                                  height: 56,
                                                  color: colorScheme
                                                      .surfaceContainerHighest,
                                                  child: const Icon(
                                                    Icons.broken_image_outlined,
                                                  ),
                                                ),
                                              ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              name,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text('Category: $category'),
                                            const SizedBox(height: 2),
                                            Text('Price: ₹$price'),
                                            const SizedBox(height: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: int.tryParse(stock) == 0
                                                    ? Colors.red.shade100
                                                    : Colors.green.shade100,
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                              child: Text(
                                                'Stock: $stock',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color:
                                                      int.tryParse(stock) == 0
                                                      ? Colors.red.shade800
                                                      : Colors.green.shade800,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Edit',
                                        onPressed: () => _showProductDialog(
                                          documentId: doc.id,
                                          initialData: data,
                                        ),
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                      IconButton(
                                        tooltip: 'Delete',
                                        onPressed: () => _deleteProduct(doc.id),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    ],
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
        },
      ),
    );
  }

  Widget _productField({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(labelText: label),
    );
  }
}
