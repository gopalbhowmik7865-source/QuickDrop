import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models/profile_models.dart';
import 'services/profile_firestore_service.dart';
import 'widgets/profile_common_widgets.dart';
import 'app_theme.dart';

enum AuthProfileViewMode {
  profile,
  wishlist,
  savedAddresses,
  settings,
  helpSupport,
}

class AuthProfilePage extends StatefulWidget {
  const AuthProfilePage({
    super.key,
    this.viewMode = AuthProfileViewMode.profile,
  });

  final AuthProfileViewMode viewMode;

  @override
  State<AuthProfilePage> createState() => _AuthProfilePageState();
}

class _AuthProfilePageState extends State<AuthProfilePage> {
  final ProfileFirestoreService _profileService = ProfileFirestoreService();

  bool _isBootstrapping = true;
  String? _bootstrapError;
  late Future<NotificationSettingsModel> _notificationSettingsFuture;
  NotificationSettingsModel? _notificationSettingsCache;
  bool _isSavingNotificationSettings = false;

  @override
  void initState() {
    super.initState();
    _notificationSettingsFuture = _loadNotificationSettings();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _isBootstrapping = true;
      _bootstrapError = null;
      _notificationSettingsCache = null;
      _notificationSettingsFuture = _loadNotificationSettings();
    });

    try {
      await _profileService.bootstrapUserProfile();
    } catch (error, stackTrace) {
      _recordProfileError(error, stackTrace: stackTrace);
      _bootstrapError = 'Coming Soon';
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isBootstrapping = false;
    });
  }

  void _recordProfileError(Object error, {StackTrace? stackTrace}) {
    developer.log(
      'Profile operation failed.',
      name: 'QuickDropProfileUI',
      error: error,
      stackTrace: stackTrace,
    );

    if (error is FirebaseException) {
      final message = error.message ?? '';
      if (error.code == 'failed-precondition') {
        final match = RegExp(r'https://console\.firebase\.google\.com\S+').firstMatch(message);
        if (match != null) {
          debugPrint('Required Firestore index: ${match.group(0)}');
        }
      }
    }
  }

  void _showProfileMessage(String message) {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showEditProfileDialog(UserProfileModel profile) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: profile.name);
    final phoneController = TextEditingController(text: profile.phoneNumber);

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
                        return 'Please enter your name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Mobile Number'),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter mobile number';
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

                try {
                  await _profileService.updateUserProfile(
                    name: nameController.text.trim(),
                    phoneNumber: phoneController.text.trim(),
                  );
                } catch (error, stackTrace) {
                  _recordProfileError(error, stackTrace: stackTrace);
                  _showProfileMessage('Coming Soon');
                  return;
                }

                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    nameController.dispose();
    phoneController.dispose();
  }

  Future<void> _showAddressForm(UserProfileModel profile, {AddressModel? existing}) async {
    final formKey = GlobalKey<FormState>();
    final labelController = TextEditingController(text: existing?.label ?? 'Home');
    final recipientController = TextEditingController(
      text: existing?.recipientName ?? profile.name,
    );
    final phoneController = TextEditingController(
      text: existing?.phoneNumber ?? profile.phoneNumber,
    );
    final line1Controller = TextEditingController(text: existing?.line1 ?? '');
    final line2Controller = TextEditingController(text: existing?.line2 ?? '');
    final cityController = TextEditingController(text: existing?.city ?? '');
    final stateController = TextEditingController(text: existing?.state ?? '');
    final pincodeController = TextEditingController(text: existing?.pincode ?? '');
    final landmarkController = TextEditingController(text: existing?.landmark ?? '');
    var isDefault = existing?.isDefault ?? false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 14,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 18,
          ),
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    existing == null ? 'Add Address' : 'Edit Address',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: labelController,
                    decoration: const InputDecoration(labelText: 'Label (Home/Office)'),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty) ? 'Enter label' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: recipientController,
                    decoration: const InputDecoration(labelText: 'Recipient Name'),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty) ? 'Enter recipient' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Mobile Number'),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty) ? 'Enter mobile number' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: line1Controller,
                    decoration: const InputDecoration(labelText: 'Address Line 1'),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty) ? 'Enter address line 1' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: line2Controller,
                    decoration: const InputDecoration(labelText: 'Address Line 2 (Optional)'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: cityController,
                          decoration: const InputDecoration(labelText: 'City'),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty) ? 'Enter city' : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: stateController,
                          decoration: const InputDecoration(labelText: 'State'),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty) ? 'Enter state' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: pincodeController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Pincode'),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty) ? 'Enter pincode' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: landmarkController,
                    decoration: const InputDecoration(labelText: 'Landmark (Optional)'),
                  ),
                  const SizedBox(height: 8),
                  StatefulBuilder(
                    builder: (context, setSheetState) {
                      return SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Set as default address'),
                        value: isDefault,
                        onChanged: (value) {
                          setSheetState(() {
                            isDefault = value;
                          });
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () async {
                        if (!(formKey.currentState?.validate() ?? false)) {
                          return;
                        }

                        try {
                          if (existing == null) {
                            await _profileService.addAddress(
                              label: labelController.text.trim(),
                              recipientName: recipientController.text.trim(),
                              phoneNumber: phoneController.text.trim(),
                              line1: line1Controller.text.trim(),
                              line2: line2Controller.text.trim(),
                              city: cityController.text.trim(),
                              state: stateController.text.trim(),
                              pincode: pincodeController.text.trim(),
                              landmark: landmarkController.text.trim(),
                              isDefault: isDefault,
                            );
                          } else {
                            await _profileService.updateAddress(
                              existing.id,
                              label: labelController.text.trim(),
                              recipientName: recipientController.text.trim(),
                              phoneNumber: phoneController.text.trim(),
                              line1: line1Controller.text.trim(),
                              line2: line2Controller.text.trim(),
                              city: cityController.text.trim(),
                              state: stateController.text.trim(),
                              pincode: pincodeController.text.trim(),
                              landmark: landmarkController.text.trim(),
                              isDefault: isDefault,
                            );
                          }
                        } catch (error, stackTrace) {
                          _recordProfileError(error, stackTrace: stackTrace);
                          _showProfileMessage('Coming Soon');
                          return;
                        }

                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext);
                        }
                      },
                      child: Text(existing == null ? 'Save Address' : 'Update Address'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    labelController.dispose();
    recipientController.dispose();
    phoneController.dispose();
    line1Controller.dispose();
    line2Controller.dispose();
    cityController.dispose();
    stateController.dispose();
    pincodeController.dispose();
    landmarkController.dispose();
  }

  Future<void> _showAddWishlistDialog() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
            child: SizedBox(
              height: MediaQuery.of(sheetContext).size.height * 0.66,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Add to Wishlist',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('products')
                          .limit(30)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        if (snapshot.hasError) {
                          return const Center(
                            child: Text(
                              'Coming Soon',
                              textAlign: TextAlign.center,
                            ),
                          );
                        }

                        final docs = snapshot.data?.docs ?? [];
                        if (docs.isEmpty) {
                          return const EmptyStateCard(
                            icon: Icons.inventory_2_outlined,
                            message: 'Coming Soon',
                          );
                        }

                        return ListView.separated(
                          itemCount: docs.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final product = docs[index].data();
                            final productId = docs[index].id;
                            final name = (product['name'] ?? '').toString();
                            final price = (product['price'] ?? '').toString();

                            return Container(
                              decoration: BoxDecoration(
                                color: QuickDropColors.mint,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: QuickDropColors.border),
                              ),
                              child: ListTile(
                                title: Text(
                                  name.isNotEmpty ? name : 'Nothing found',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                subtitle: Text(price.isNotEmpty ? 'Price: ₹$price' : 'Price not available'),
                                trailing: IconButton(
                                  onPressed: () async {
                                    try {
                                      await _profileService.addToWishlist(productId);
                                      _showProfileMessage('Added to wishlist');
                                    } catch (error, stackTrace) {
                                      _recordProfileError(error, stackTrace: stackTrace);
                                      _showProfileMessage('Coming Soon');
                                    }
                                  },
                                  icon: const Icon(Icons.favorite_border),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _toggleNotifications(
    NotificationSettingsModel current, {
    bool? orderUpdates,
    bool? promotions,
    bool? systemAlerts,
  }) async {
    final next = NotificationSettingsModel(
      orderUpdates: orderUpdates ?? current.orderUpdates,
      promotions: promotions ?? current.promotions,
      systemAlerts: systemAlerts ?? current.systemAlerts,
      updatedAt: DateTime.now(),
    );

    setState(() {
      _notificationSettingsCache = next;
      _isSavingNotificationSettings = true;
    });

    try {
      await _profileService.saveNotificationSettings(
        orderUpdates: next.orderUpdates,
        promotions: next.promotions,
        systemAlerts: next.systemAlerts,
      ).timeout(const Duration(seconds: 10));
    } on TimeoutException catch (error, stackTrace) {
      _recordProfileError(error, stackTrace: stackTrace);
      debugPrint('Notification settings save timed out.');
      if (!mounted) {
        return;
      }
      setState(() {
        _notificationSettingsCache = current;
      });
      _showProfileMessage('Unable to save notification settings. Please try again.');
    } on FirebaseException catch (error, stackTrace) {
      _recordProfileError(error, stackTrace: stackTrace);
      debugPrint('Notification settings save Firebase error: ${error.code} ${error.message}');
      if (!mounted) {
        return;
      }
      setState(() {
        _notificationSettingsCache = current;
      });
      _showProfileMessage('Unable to save notification settings. Please try again.');
    } catch (error, stackTrace) {
      _recordProfileError(error, stackTrace: stackTrace);
      debugPrint('Notification settings save error: $error');
      if (!mounted) {
        return;
      }
      setState(() {
        _notificationSettingsCache = current;
      });
      _showProfileMessage('Unable to save notification settings. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isSavingNotificationSettings = false;
        });
      }
    }
  }

  Future<NotificationSettingsModel> _loadNotificationSettings() async {
    try {
      return await _profileService.getOrCreateNotificationSettings(
        timeout: const Duration(seconds: 10),
      );
    } on TimeoutException catch (error, stackTrace) {
      _recordProfileError(error, stackTrace: stackTrace);
      debugPrint('Notification settings load timed out.');
      rethrow;
    } on FirebaseException catch (error, stackTrace) {
      _recordProfileError(error, stackTrace: stackTrace);
      debugPrint('Notification settings load Firebase error: ${error.code} ${error.message}');
      rethrow;
    } catch (error, stackTrace) {
      _recordProfileError(error, stackTrace: stackTrace);
      debugPrint('Notification settings load error: $error');
      rethrow;
    }
  }

  void _reloadNotificationSettings() {
    setState(() {
      _notificationSettingsCache = null;
      _notificationSettingsFuture = _loadNotificationSettings();
    });
  }

  Future<SupportInfoModel?> _loadSupportInfo() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('app_support')
          .doc('customer_support')
          .get()
          .timeout(const Duration(seconds: 10));

      if (!snapshot.exists) {
        return null;
      }

      return SupportInfoModel.fromFirestore(snapshot.data());
    } on FirebaseException catch (error, stackTrace) {
      _recordProfileError(error, stackTrace: stackTrace);
      debugPrint('Support fetch Firebase error: ${error.code} ${error.message}');
      return null;
    } catch (error, stackTrace) {
      _recordProfileError(error, stackTrace: stackTrace);
      debugPrint('Support fetch error: $error');
      return null;
    }
  }

  Future<void> _openPhone(String phone) async {
    final digits = phone.replaceAll(' ', '');
    final uri = Uri.parse('tel:$digits');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      _showProfileMessage('Coming Soon');
    }
  }

  Future<void> _openWhatsApp(String phone) async {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse('https://wa.me/$digits');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      _showProfileMessage('Coming Soon');
    }
  }

  Future<void> _openEmail(String email) async {
    final uri = Uri(
      scheme: 'mailto',
      path: email,
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      _showProfileMessage('Coming Soon');
    }
  }

  Future<void> _shareQuickDrop() async {
    String? shareMessage;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('app_content')
          .doc('share_quickdrop')
          .get();
      final data = snapshot.data();
      final firestoreMessage = (data?['message'] ?? '').toString().trim();
      if (firestoreMessage.isNotEmpty) {
        shareMessage = firestoreMessage;
      }
    } catch (error, stackTrace) {
      _recordProfileError(error, stackTrace: stackTrace);
    }

    if (shareMessage == null || shareMessage.isEmpty) {
      _showProfileMessage('Coming Soon');
      return;
    }

    await SharePlus.instance.share(
      ShareParams(
        text: shareMessage,
        subject: 'QuickDrop Go',
      ),
    );
  }

  Future<void> _rateApp() async {
    String? targetUrl;
    String title = 'Rate QuickDrop';
    String message =
        'Enjoying QuickDrop?\n\nPlease rate us on Google Play after the app is published.';

    try {
      final config = await FirebaseFirestore.instance
          .collection('app_content')
          .doc('rate_app')
          .get();
      final data = config.data();
      final firestoreTitle = (data?['title'] ?? '').toString().trim();
      final firestoreMessage = (data?['message'] ?? '').toString().trim();
      if (firestoreTitle.isNotEmpty) {
        title = firestoreTitle;
      }
      if (firestoreMessage.isNotEmpty) {
        message = firestoreMessage;
      }
      targetUrl = (data?['url'] ?? '').toString().trim();
    } catch (error, stackTrace) {
      _recordProfileError(error, stackTrace: stackTrace);
    }

    if (targetUrl == null || targetUrl.isEmpty) {
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
      return;
    }

    final uri = Uri.tryParse(targetUrl);
    if (uri == null) {
      _showProfileMessage('Coming Soon');
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      _showProfileMessage('Coming Soon');
    }
  }

  void _openContentPage(String title, String docId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AppContentPage(
          pageTitle: title,
          documentId: docId,
          profileService: _profileService,
        ),
      ),
    );
  }

  String _pageTitle() {
    switch (widget.viewMode) {
      case AuthProfileViewMode.profile:
        return 'Profile';
      case AuthProfileViewMode.wishlist:
        return 'Wishlist';
      case AuthProfileViewMode.savedAddresses:
        return 'Saved Addresses';
      case AuthProfileViewMode.settings:
        return 'Settings';
      case AuthProfileViewMode.helpSupport:
        return 'Help & Support';
    }
  }

  List<Widget> _sectionsForProfile(UserProfileModel profile) {
    switch (widget.viewMode) {
      case AuthProfileViewMode.profile:
        return [
          _buildProfileHeader(profile),
          _buildAccountDetails(profile),
          _buildAddressSection(profile),
          _buildUtilitiesSection(),
        ];
      case AuthProfileViewMode.wishlist:
        return [_buildWishlistSection()];
      case AuthProfileViewMode.savedAddresses:
        return [_buildAddressSection(profile)];
      case AuthProfileViewMode.settings:
        return [_buildNotificationSection()];
      case AuthProfileViewMode.helpSupport:
        return [_buildSupportSection()];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_pageTitle()),
        backgroundColor: QuickDropColors.background,
        foregroundColor: QuickDropColors.darkText,
        elevation: 0,
      ),
      body: Container(
        color: QuickDropColors.background,
        child: _isBootstrapping
            ? const Center(child: CircularProgressIndicator())
            : _bootstrapError != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off_outlined, color: QuickDropColors.primary, size: 44),
                          const SizedBox(height: 10),
                          const Text('Coming Soon', textAlign: TextAlign.center),
                          const SizedBox(height: 10),
                          FilledButton(
                            onPressed: _bootstrap,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : StreamBuilder<UserProfileModel>(
                    stream: _profileService.userProfileStream(),
                    builder: (context, profileSnapshot) {
                      if (profileSnapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (profileSnapshot.hasError || !profileSnapshot.hasData) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: const Text('Coming Soon', textAlign: TextAlign.center),
                          ),
                        );
                      }

                      final profile = profileSnapshot.data!;

                      return RefreshIndicator(
                        onRefresh: _bootstrap,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final isWide = constraints.maxWidth > 680;

                            final sections = _sectionsForProfile(profile);

                            if (!isWide) {
                              return ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
                                children: sections,
                              );
                            }

                            if (widget.viewMode != AuthProfileViewMode.profile) {
                              return ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
                                children: sections,
                              );
                            }

                            return ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
                              children: [
                                sections.first,
                                const SizedBox(height: 8),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        children: [
                                          sections[1],
                                          sections[2],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        children: [
                                          sections[3],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      );
                    },
                  ),
      ),
    );
  }

  Widget _buildProfileHeader(UserProfileModel profile) {
    final name = profile.name.isNotEmpty ? profile.name : 'Coming Soon';
    final phone = profile.phoneNumber.isNotEmpty ? profile.phoneNumber : 'Not available';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: QuickDropColors.primaryLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: QuickDropColors.primary.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: Colors.white.withValues(alpha: 0.72),
            child: const Icon(
              Icons.person_rounded,
              size: 44,
              color: QuickDropColors.darkText,
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
                    fontFamily: 'Poppins',
                    color: QuickDropColors.darkText,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  phone,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: QuickDropColors.secondaryText,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountDetails(UserProfileModel profile) {
    return ProfileSectionCard(
      title: 'User Information',
      subtitle: 'Live profile data from Firestore',
      icon: Icons.person_outline,
      action: TextButton.icon(
        onPressed: () => _showEditProfileDialog(profile),
        icon: const Icon(Icons.edit_outlined, size: 16),
        label: const Text('Edit'),
      ),
      child: Column(
        children: [
          ProfileInfoRow(
            label: 'Name',
            value: profile.name.isNotEmpty ? profile.name : 'Not available',
            icon: Icons.badge_outlined,
          ),
          ProfileInfoRow(
            label: 'Mobile Number',
            value: profile.phoneNumber.isNotEmpty ? profile.phoneNumber : 'Not available',
            icon: Icons.call_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildAddressSection(UserProfileModel profile) {
    return ProfileSectionCard(
      title: 'Saved Addresses',
      subtitle: 'Add, edit and remove delivery addresses',
      icon: Icons.location_on_outlined,
      action: IconButton(
        onPressed: () => _showAddressForm(profile),
        icon: const Icon(Icons.add_circle_outline),
      ),
      child: StreamBuilder<List<AddressModel>>(
        stream: _profileService.addressStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LinearProgressIndicator();
          }

          if (snapshot.hasError) {
            return const Text('Coming Soon');
          }

          final addresses = snapshot.data ?? const <AddressModel>[];
          if (addresses.isEmpty) {
            return const EmptyStateCard(
              icon: Icons.location_city_outlined,
              message: 'No saved addresses yet.',
            );
          }

          return Column(
            children: addresses.map((address) {
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFCF8F2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFF0E4D2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          address.label,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        if (address.isDefault)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD4B06A),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'Default',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => _showAddressForm(profile, existing: address),
                          icon: const Icon(Icons.edit_outlined, size: 19),
                        ),
                        IconButton(
                          onPressed: () async {
                            try {
                              await _profileService.deleteAddress(address.id);
                            } catch (error, stackTrace) {
                              _recordProfileError(error, stackTrace: stackTrace);
                              _showProfileMessage('Coming Soon');
                            }
                          },
                          icon: const Icon(Icons.delete_outline, size: 19),
                        ),
                      ],
                    ),
                    Text(address.recipientName, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(address.phoneNumber),
                    const SizedBox(height: 4),
                    Text(address.fullAddress),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Widget _buildWishlistSection() {
    return ProfileSectionCard(
      title: 'Wishlist',
      subtitle: 'Products you saved for later',
      icon: Icons.favorite_border,
      action: IconButton(
        onPressed: _showAddWishlistDialog,
        icon: const Icon(Icons.add_circle_outline),
      ),
      child: StreamBuilder<List<WishlistItemModel>>(
        stream: _profileService.wishlistStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LinearProgressIndicator();
          }

          if (snapshot.hasError) {
            return const Text('Coming Soon');
          }

          final wishlist = snapshot.data ?? const <WishlistItemModel>[];
          if (wishlist.isEmpty) {
            return const EmptyStateCard(
              icon: Icons.favorite_outline,
              message: 'Your wishlist is empty.',
            );
          }

          return Column(
            children: wishlist.map((item) {
              return FutureBuilder<Map<String, dynamic>?>(
                future: _profileService.getProduct(item.productId),
                builder: (context, productSnapshot) {
                  final product = productSnapshot.data;
                  final name = (product?['name'] ?? '').toString();
                  final price = (product?['price'] ?? '').toString();

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCF8F2),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFF0E4D2)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF6EBDD),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.shopping_bag_outlined, color: Color(0xFFB0893C)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name.isNotEmpty ? name : 'Nothing found',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF3F3527),
                                ),
                              ),
                              if (price.isNotEmpty)
                                Text(
                                  '₹$price',
                                  style: const TextStyle(color: Color(0xFF8B7B66)),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () async {
                            try {
                              await _profileService.removeFromWishlist(item.productId);
                            } catch (error, stackTrace) {
                              _recordProfileError(error, stackTrace: stackTrace);
                              _showProfileMessage('Coming Soon');
                            }
                          },
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  );
                },
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Widget _buildNotificationSection() {
    return ProfileSectionCard(
      title: 'Notification Settings',
      subtitle: 'Stored in Firestore for FCM-ready preferences',
      icon: Icons.notifications_active_outlined,
      child: FutureBuilder<NotificationSettingsModel>(
        future: _notificationSettingsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              _notificationSettingsCache == null) {
            return const LinearProgressIndicator();
          }

          if (snapshot.hasError && _notificationSettingsCache == null) {
            final message = snapshot.error is TimeoutException
                ? 'Notification settings are taking too long to load.'
                : 'Could not load notification settings right now.';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _reloadNotificationSettings,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            );
          }

          final settings = _notificationSettingsCache ?? snapshot.data;
          if (settings == null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Could not load notification settings right now.'),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _reloadNotificationSettings,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            );
          }

          return Column(
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Order Updates'),
                value: settings.orderUpdates,
                onChanged: _isSavingNotificationSettings
                    ? null
                    : (value) => _toggleNotifications(settings, orderUpdates: value),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Promotions'),
                value: settings.promotions,
                onChanged: _isSavingNotificationSettings
                    ? null
                    : (value) => _toggleNotifications(settings, promotions: value),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('System Alerts'),
                value: settings.systemAlerts,
                onChanged: _isSavingNotificationSettings
                    ? null
                    : (value) => _toggleNotifications(settings, systemAlerts: value),
              ),
              if (_isSavingNotificationSettings) const LinearProgressIndicator(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSupportSection() {
    return ProfileSectionCard(
      title: 'Help & Support',
      subtitle: 'Live support info from Firestore',
      icon: Icons.support_agent_outlined,
      child: FutureBuilder<SupportInfoModel?>(
        future: _loadSupportInfo(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LinearProgressIndicator();
          }

          final support = snapshot.data;
          if (support == null) {
            return const EmptyStateCard(
              icon: Icons.info_outline,
              message: 'Support information is unavailable.',
            );
          }

          final hasAnyField = support.phone.isNotEmpty ||
              support.whatsapp.isNotEmpty ||
              support.email.isNotEmpty ||
              support.message.isNotEmpty;

          if (!hasAnyField) {
            return const EmptyStateCard(
              icon: Icons.info_outline,
              message: 'Support information is unavailable.',
            );
          }

          return Column(
            children: [
              if (support.phone.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: QuickDropColors.mint,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: QuickDropColors.border),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.call_outlined, color: Colors.black),
                    title: const Text('Phone', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(support.phone),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () => _openPhone(support.phone),
                  ),
                ),
              if (support.whatsapp.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: QuickDropColors.mint,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: QuickDropColors.border),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.chat_outlined, color: Colors.black),
                    title: const Text('WhatsApp', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(support.whatsapp),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () => _openWhatsApp(support.whatsapp),
                  ),
                ),
              if (support.email.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: QuickDropColors.mint,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: QuickDropColors.border),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.email_outlined, color: Colors.black),
                    title: const Text('Email', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(support.email),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () => _openEmail(support.email),
                  ),
                ),
              if (support.message.isNotEmpty)
                ProfileInfoRow(
                  label: 'Message',
                  value: support.message,
                  icon: Icons.info_outline,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildUtilitiesSection() {
    return ProfileSectionCard(
      title: 'Utilities',
      subtitle: 'Share app, legal docs and app feedback',
      icon: Icons.apps_outage_outlined,
      child: Column(
        children: [
          _utilityTile(
            icon: Icons.ios_share_outlined,
            title: 'Share QuickDrop',
            onTap: _shareQuickDrop,
          ),
          _utilityTile(
            icon: Icons.info_outline,
            title: 'About Us',
            onTap: () => _openContentPage('About Us', 'about_us'),
          ),
          _utilityTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            onTap: () => _openContentPage('Privacy Policy', 'privacy_policy'),
          ),
          _utilityTile(
            icon: Icons.gavel_outlined,
            title: 'Terms & Conditions',
            onTap: () => _openContentPage('Terms & Conditions', 'terms_conditions'),
          ),
          _utilityTile(
            icon: Icons.star_border,
            title: 'Rate App',
            onTap: _rateApp,
          ),
        ],
      ),
    );
  }

  Widget _utilityTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFCF8F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0E4D2)),
      ),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFFB0893C)),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF3F3527),
          ),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }

}

class AppContentPage extends StatelessWidget {
  const AppContentPage({
    super.key,
    required this.pageTitle,
    required this.documentId,
    required this.profileService,
  });

  final String pageTitle;
  final String documentId;
  final ProfileFirestoreService profileService;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(pageTitle)),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [QuickDropColors.primaryLight, QuickDropColors.mint, QuickDropColors.background],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: StreamBuilder<Map<String, dynamic>?>(
          stream: profileService.appContentStream(documentId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: const Text('Coming Soon', textAlign: TextAlign.center),
                ),
              );
            }

            final data = snapshot.data;
            if (data == null) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Coming Soon',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            final title = (data['title'] ?? pageTitle).toString();
            final content = (data['content'] ?? '').toString();
            final updatedAt = data['updatedAt'] is Timestamp
                ? (data['updatedAt'] as Timestamp).toDate()
                : null;

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: QuickDropColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF11274E),
                        ),
                      ),
                      if (updatedAt != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Updated on ${updatedAt.day}/${updatedAt.month}/${updatedAt.year}',
                          style: const TextStyle(
                            color: Color(0xFF5D6F8F),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Text(
                        content.isNotEmpty
                            ? content
                            : 'Coming Soon',
                        style: const TextStyle(
                          height: 1.5,
                          fontSize: 15,
                          color: Color(0xFF1E2F4E),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
