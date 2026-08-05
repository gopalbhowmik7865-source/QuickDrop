import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final Future<Map<String, dynamic>> _settingsFuture;
  final TextEditingController _deliveryChargeController = TextEditingController();
  bool _storeOpen = true;
  bool _maintenanceMode = false;
  bool _initialized = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _settingsFuture = _loadSettings();
  }

  @override
  void dispose() {
    _deliveryChargeController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _loadSettings() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('settings')
        .doc('app')
        .get();

    final data = snapshot.data();
    return {
      'storeOpen': data?['storeOpen'] as bool? ?? true,
      'maintenanceMode': data?['maintenanceMode'] as bool? ?? false,
      'deliveryCharge': (data?['deliveryCharge'] as num?)?.toDouble() ?? 0.0,
    };
  }

  Future<void> _saveSettings(BuildContext context) async {
    final parsedDeliveryCharge =
        double.tryParse(_deliveryChargeController.text.trim());

    if (parsedDeliveryCharge == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid delivery charge.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await FirebaseFirestore.instance.collection('settings').doc('app').set({
        'storeOpen': _storeOpen,
        'maintenanceMode': _maintenanceMode,
        'deliveryCharge': parsedDeliveryCharge,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved successfully.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save settings. Please try again.')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _isSaving
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : TextButton(
                    onPressed: () => _saveSettings(context),
                    child: const Text('Save'),
                  ),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _settingsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Failed to load settings. Please try again.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final settings = snapshot.data ??
              {
                'storeOpen': true,
                'maintenanceMode': false,
                'deliveryCharge': 0.0,
              };

          if (!_initialized) {
            _storeOpen = settings['storeOpen'] as bool;
            _maintenanceMode = settings['maintenanceMode'] as bool;
            _deliveryChargeController.text =
                (settings['deliveryCharge'] as double).toStringAsFixed(2);
            _initialized = true;
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SwitchListTile(
                title: const Text('Store Open'),
                value: _storeOpen,
                onChanged: _isSaving
                    ? null
                    : (value) {
                        setState(() {
                          _storeOpen = value;
                        });
                      },
              ),
              SwitchListTile(
                title: const Text('Maintenance Mode'),
                value: _maintenanceMode,
                onChanged: _isSaving
                    ? null
                    : (value) {
                        setState(() {
                          _maintenanceMode = value;
                        });
                      },
              ),
              ListTile(
                title: const Text('Delivery Charge'),
                subtitle: TextField(
                  controller: _deliveryChargeController,
                  enabled: !_isSaving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    prefixText: 'Rs ',
                    hintText: '0.00',
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
