import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import 'auth_service.dart';
import 'main.dart';
import 'login_page.dart';

class AuthProfilePage extends StatefulWidget {
  const AuthProfilePage({super.key});

  @override
  State<AuthProfilePage> createState() => _AuthProfilePageState();
}

class _AuthProfilePageState extends State<AuthProfilePage> {
  final AuthService _authService = AuthService();

  bool _isLoading = true;
  bool _isSaving = false;

  String _name = '-';
  String _phone = '-';
  String _address = '-';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
    });

    try {
      developer.log(
        'Profile load start: reading local user session.',
        name: 'QuickDropAuth',
      );

      final profile = await _authService.loadCurrentUserProfile();
      if (!mounted || profile == null) {
        developer.log(
          'Profile load result: profile is null (session not available).',
          name: 'QuickDropAuth',
        );
        return;
      }

      setState(() {
        _name = (profile['name'] as String?)?.trim().isNotEmpty == true
            ? (profile['name'] as String)
            : '-';
        _phone = (profile['phoneNumber'] as String?)?.trim().isNotEmpty == true
            ? (profile['phoneNumber'] as String)
            : (profile['phone'] as String?)?.trim().isNotEmpty == true
            ? (profile['phone'] as String)
            : '-';
        _address = (profile['address'] as String?)?.trim().isNotEmpty == true
            ? (profile['address'] as String)
            : '-';
      });

      developer.log(
        'Profile load success: name=$_name, phone=$_phone',
        name: 'QuickDropAuth',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      developer.log('Profile load failed: $error', name: 'QuickDropAuth');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showEditProfileDialog() async {
    final nameController = TextEditingController(text: _name == '-' ? '' : _name);
    final addressController = TextEditingController(
      text: _address == '-' ? '' : _address,
    );
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Edit Profile'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: addressController,
                  decoration: const InputDecoration(labelText: 'Address'),
                  minLines: 2,
                  maxLines: 3,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter address';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _isSaving
                  ? null
                  : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: _isSaving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) {
                        return;
                      }
                      setState(() {
                        _isSaving = true;
                      });
                      try {
                        developer.log('Profile save start.', name: 'QuickDropAuth');

                        await _authService.updateCurrentUserProfile(
                          name: nameController.text.trim(),
                          address: addressController.text.trim(),
                        );

                        developer.log(
                          'Profile save success.',
                          name: 'QuickDropAuth',
                        );

                        if (!mounted || !dialogContext.mounted) {
                          return;
                        }
                        Navigator.pop(dialogContext);
                        await _loadProfile();
                      } catch (error) {
                        if (!mounted || !dialogContext.mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(
                            content: Text(
                              error.toString().replaceFirst('Exception: ', ''),
                            ),
                          ),
                        );
                      } finally {
                        if (mounted) {
                          setState(() {
                            _isSaving = false;
                          });
                        }
                      }
                    },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    nameController.dispose();
    addressController.dispose();
  }

  Future<void> _logout() async {
    try {
      await _authService.signOut();

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => LoginPage(
            cartNotifier: ValueNotifier<List<CartItem>>([]),
          ),
        ),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  String _initialsFromName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == '-') {
      return 'QD';
    }

    final parts = trimmed.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) {
      return 'QD';
    }

    if (parts.length == 1) {
      return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1).toUpperCase();
    }

    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  Widget _buildAvatarHeader(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 390;

    return Container(
      padding: EdgeInsets.fromLTRB(18, isCompact ? 18 : 22, 18, 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0A4FBD), Color(0xFF0F6CFF), Color(0xFF55B2FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade200.withValues(alpha: 0.75),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: isCompact ? 76 : 88,
            height: isCompact ? 76 : 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 2.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
              gradient: const LinearGradient(
                colors: [Color(0xFFEDF5FF), Color(0xFFCFE4FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Center(
              child: Text(
                _initialsFromName(_name),
                style: TextStyle(
                  color: const Color(0xFF0A4FBD),
                  fontSize: isCompact ? 22 : 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.phone_outlined, color: Colors.white, size: 14),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _phone,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Manage your QuickDrop Go account details',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoTile({required String label, required String value, required IconData icon}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.blue.shade50),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade100.withValues(alpha: 0.45),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF3FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF0B63F6), size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blueGrey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final stackButtons = width < 420;

    final editButton = SizedBox(
      height: 50,
      child: OutlinedButton.icon(
        onPressed: _showEditProfileDialog,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFF0B63F6)),
          foregroundColor: const Color(0xFF0B63F6),
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: const Icon(Icons.edit_outlined),
        label: const Text(
          'Edit Profile',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );

    final logoutButton = SizedBox(
      height: 50,
      child: ElevatedButton.icon(
        onPressed: _logout,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0B63F6),
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: const Icon(Icons.logout_rounded),
        label: const Text(
          'Logout',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );

    if (stackButtons) {
      return Column(
        children: [
          SizedBox(width: double.infinity, child: editButton),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: logoutButton),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: editButton),
        const SizedBox(width: 10),
        Expanded(child: logoutButton),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Profile',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: const Color(0xFF102755),
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFEAF3FF), Color(0xFFF7FAFF), Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                children: [
                  _buildAvatarHeader(context),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Colors.blue.shade50),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.shade100.withValues(alpha: 0.35),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Account Details',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF102755),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Update your personal information for smoother deliveries',
                          style: TextStyle(
                            color: Colors.blueGrey.shade600,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _infoTile(label: 'Name', value: _name, icon: Icons.person_outline),
                        _infoTile(
                          label: 'Phone Number',
                          value: _phone,
                          icon: Icons.phone_outlined,
                        ),
                        _infoTile(
                          label: 'Address',
                          value: _address,
                          icon: Icons.location_on_outlined,
                        ),
                        const SizedBox(height: 4),
                        _buildActionButtons(context),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
