import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'admin_order_details_page.dart';
import 'push_notification_service.dart';
import 'firebase_options.dart';
import 'category_routing.dart';

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

bool _canCancelOrder(OrderStatus status) {
  return status != OrderStatus.delivered && status != OrderStatus.cancelled;
}

bool _canTransitionOrderStatus(OrderStatus current, OrderStatus next) {
  switch (current) {
    case OrderStatus.pending:
      return next == OrderStatus.accepted || next == OrderStatus.cancelled;
    case OrderStatus.accepted:
      return next == OrderStatus.packed || next == OrderStatus.cancelled;
    case OrderStatus.packed:
      return next == OrderStatus.outForDelivery || next == OrderStatus.cancelled;
    case OrderStatus.outForDelivery:
      return next == OrderStatus.delivered || next == OrderStatus.cancelled;
    case OrderStatus.delivered:
    case OrderStatus.cancelled:
      return false;
  }
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

        if (snapshot.hasData) {
          return const DashboardPage();
        }

        return const LoginPage();
      },
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
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
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
    OrderStatus.outForDelivery,
    OrderStatus.delivered,
    OrderStatus.cancelled,
  ];

  OrderStatus? _selectedStatus = OrderStatus.pending;

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
          {
            'status': nextStatus.label,
            'updatedAt': Timestamp.now(),
          },
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

  Future<void> _markOrderDelivered(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    OrderStatus currentStatus,
  ) async {
    await _updateOrderStatus(
      context,
      doc,
      currentStatus,
      OrderStatus.delivered,
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
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
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
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
                      data['customerName'] ?? data['name'] ?? data['ownerName'],
                    );
                    final phone = _displayValue(
                      data['phoneNumber'] ?? data['phone'] ?? data['ownerPhone'],
                    );
                    final address = _displayValue(
                      data['deliveryAddress'] ?? data['address'],
                    );
                    final orderStatus = _orderStatusFromValue(data['status']);
                    final statusLabel = orderStatus == OrderStatus.cancelled
                        ? 'Order Cancelled'
                        : orderStatus.label;
                    final statusColor = _orderStatusColor(orderStatus);
                    final statusIcon = _orderStatusIcon(orderStatus);
                    final paymentMethod = _displayValue(data['paymentMethod']);
                    final paymentStatus = _displayValue(data['paymentStatus']);
                    final paymentIdValue = data['paymentId']?.toString().trim() ?? '';
                    final paymentId = paymentIdValue.isEmpty ? null : paymentIdValue;
                    final totalAmount = _displayAmount(data['totalAmount']);

                      return Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: colorScheme.outlineVariant),
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
                                      style: Theme.of(context).textTheme.titleMedium
                                          ?.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  Chip(
                                    avatar: Icon(
                                      statusIcon,
                                      size: 16,
                                      color: statusColor,
                                    ),
                                    label: Text(statusLabel),
                                    backgroundColor:
                                        statusColor.withValues(alpha: 0.12),
                                    side: BorderSide(
                                      color: statusColor.withValues(alpha: 0.22),
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
                              _OrderDetailRow(label: 'Customer', value: customerName),
                              _OrderDetailRow(label: 'Phone', value: phone),
                              _OrderDetailRow(label: 'Address', value: address),
                              _OrderDetailRow(label: 'Payment Method', value: paymentMethod),
                              _OrderDetailRow(label: 'Payment Status', value: paymentStatus),
                              if (paymentId != null)
                                _OrderDetailRow(label: 'Payment ID', value: paymentId),
                              _OrderDetailRow(label: 'Total', value: totalAmount),
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
                              if (orderStatus == OrderStatus.pending) ...[
                                const SizedBox(height: 6),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: () => _updateOrderStatus(
                                      context,
                                      doc,
                                      orderStatus,
                                      OrderStatus.accepted,
                                    ),
                                    icon: const Icon(Icons.check_circle_outline),
                                    label: const Text('Accept'),
                                  ),
                                ),
                              ],
                              if (orderStatus == OrderStatus.accepted) ...[
                                const SizedBox(height: 6),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: () => _updateOrderStatus(
                                      context,
                                      doc,
                                      orderStatus,
                                      OrderStatus.packed,
                                    ),
                                    icon: const Icon(Icons.inventory_2_outlined),
                                    label: const Text('Packed'),
                                  ),
                                ),
                              ],
                              if (orderStatus == OrderStatus.packed) ...[
                                const SizedBox(height: 6),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: () => _updateOrderStatus(
                                      context,
                                      doc,
                                      orderStatus,
                                      OrderStatus.outForDelivery,
                                    ),
                                    icon: const Icon(Icons.local_shipping_outlined),
                                    label: const Text('Out for Delivery'),
                                  ),
                                ),
                              ],
                              if (orderStatus == OrderStatus.outForDelivery) ...[
                                const SizedBox(height: 6),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: () => _markOrderDelivered(
                                      context,
                                      doc,
                                      orderStatus,
                                    ),
                                    icon: const Icon(Icons.done_all_outlined),
                                    label: const Text('Delivered'),
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
  static final List<String> _mainCategories = categorySubcategoryMap.keys.toList();

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

  Future<String?> _pickAndUploadProductImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final file = result.files.first;
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
        : null;
    String? selectedSubcategory = initialData?['subcategory']?.toString().trim();
    if (selectedSubcategory != null && selectedSubcategory.isEmpty) {
      selectedSubcategory = null;
    }
    String? selectedChildCategory = initialData?['childCategory']?.toString().trim();
    if (selectedChildCategory != null && selectedChildCategory.isEmpty) {
      selectedChildCategory = null;
    }
    final imageUrlController = TextEditingController(
      text: initialData?['imageUrl']?.toString() ?? '',
    );
    final stockController = TextEditingController(
      text: initialData?['stock']?.toString() ?? '',
    );
    bool isImageUploading = false;
    String selectedImageLabel = imageUrlController.text.trim().isEmpty
        ? 'No image selected'
        : 'Image URL ready';

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
                        value: selectedCategory,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                        ),
                        items: _mainCategories
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
                        value: selectedSubcategory,
                        decoration: const InputDecoration(
                          labelText: 'Subcategory',
                        ),
                        items: buildSubcategoryOptions(selectedCategory ?? '')
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
                          if (value == null || value!.trim().isEmpty) {
                            return 'Please select subcategory';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: selectedChildCategory,
                        decoration: const InputDecoration(
                          labelText: 'Child Category',
                        ),
                        items: buildChildCategoryOptions(selectedSubcategory)
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
                          if (value == null || value.trim().isEmpty) {
                            return 'Please select child category';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
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
                            onPressed: isImageUploading
                                ? null
                                : () async {
                                    try {
                                      if (!context.mounted ||
                                          !dialogContext.mounted) {
                                        return;
                                      }
                                      setDialogState(() {
                                        isImageUploading = true;
                                        selectedImageLabel =
                                            'Uploading image...';
                                      });

                                      final url =
                                          await _pickAndUploadProductImage();

                                      if (!context.mounted ||
                                          !dialogContext.mounted) {
                                        return;
                                      }

                                      if (url != null) {
                                        imageUrlController.text = url;
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Image uploaded successfully',
                                            ),
                                          ),
                                        );
                                        if (context.mounted) {
                                          setDialogState(() {
                                            selectedImageLabel =
                                                'Image URL ready';
                                          });
                                        }
                                      } else {
                                        if (context.mounted) {
                                          setDialogState(() {
                                            selectedImageLabel =
                                                'No image selected';
                                          });
                                        }
                                      }
                                    } catch (error) {
                                      if (context.mounted &&
                                          dialogContext.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Image upload failed: $error',
                                            ),
                                          ),
                                        );
                                      }
                                      if (context.mounted) {
                                        setDialogState(() {
                                          selectedImageLabel =
                                              'No image selected';
                                        });
                                      }
                                    } finally {
                                      if (context.mounted &&
                                          dialogContext.mounted) {
                                        setDialogState(() {
                                          isImageUploading = false;
                                        });
                                      }
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
                                : const Icon(Icons.upload_file),
                            label: const Text('Upload Image'),
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

                    final data = {
                      'name': nameController.text.trim(),
                      'price': double.parse(priceController.text.trim()),
                      'category': canonicalCategory(selectedCategory ?? ''),
                      'subcategory': selectedSubcategory?.trim() ?? '',
                      'childCategory': selectedChildCategory?.trim() ?? '',
                      'imageUrl': imageUrlController.text.trim(),
                      'stock': int.parse(stockController.text.trim()),
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
      appBar: AppBar(title: const Text('Product Management')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showProductDialog(),
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

          if (products.isEmpty) {
            return Center(
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
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: products.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = products[index];
              final data = doc.data();
              final name = data['name']?.toString() ?? 'Unnamed Product';
              final price = data['price'];
              final category = data['category']?.toString() ?? 'General';
              final stock = data['stock']?.toString() ?? '0';

              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text('Category: $category'),
                                const SizedBox(height: 2),
                                Text('Price: ₹$price'),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: int.tryParse(stock) == 0
                                        ? Colors.red.shade100
                                        : Colors.green.shade100,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    'Stock: $stock',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: int.tryParse(stock) == 0
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
