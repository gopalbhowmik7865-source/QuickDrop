import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final Future<Map<String, dynamic>> _settingsFuture;
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _radiusController = TextEditingController();
  final TextEditingController _deliveryChargeController =
      TextEditingController();
  final TextEditingController _freeDeliveryController = TextEditingController();
  bool _storeOpen = true;
  bool _maintenanceMode = false;
  bool _deliveryEnabled = false;
  bool _initialized = false;
  bool _isSaving = false;
  LatLng? _hubLocation;
  TimeOfDay _openingTime = const TimeOfDay(hour: 7, minute: 0);
  TimeOfDay _closingTime = const TimeOfDay(hour: 22, minute: 0);

  @override
  void initState() {
    super.initState();
    _settingsFuture = _loadSettings();
  }

  @override
  void dispose() {
    _radiusController.dispose();
    _deliveryChargeController.dispose();
    _freeDeliveryController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _loadSettings() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('settings')
        .doc('app')
        .get();

    return snapshot.data() ?? const {};
  }

  Future<void> _saveSettings(BuildContext context) async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_deliveryEnabled && _hubLocation == null) {
      _showMessage('Select the hub location before enabling delivery.');
      return;
    }
    if (FirebaseAuth.instance.currentUser == null) {
      _showMessage('Your admin session has expired. Please sign in again.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      await FirebaseFirestore.instance.collection('settings').doc('app').set({
        'storeOpen': _storeOpen,
        'maintenanceMode': _maintenanceMode,
        'hubLatitude': _hubLocation?.latitude,
        'hubLongitude': _hubLocation?.longitude,
        'deliveryRadiusKm': double.parse(_radiusController.text.trim()),
        'deliveryCharge': double.parse(_deliveryChargeController.text.trim()),
        'freeDeliveryMinimum': double.parse(
          _freeDeliveryController.text.trim(),
        ),
        'deliveryEnabled': _deliveryEnabled,
        'storeOpenTime': _timeValue(_openingTime),
        'storeCloseTime': _timeValue(_closingTime),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      _showMessage('Delivery settings updated successfully.');
    } on FirebaseException catch (error) {
      if (!mounted) return;
      _showMessage(error.message ?? 'Failed to update delivery settings.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickHubLocation() async {
    final result = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => _HubLocationPicker(initialLocation: _hubLocation),
      ),
    );
    if (result != null && mounted) setState(() => _hubLocation = result);
  }

  Future<void> _pickTime({required bool opening}) async {
    final result = await showTimePicker(
      context: context,
      initialTime: opening ? _openingTime : _closingTime,
    );
    if (result == null || !mounted) return;
    setState(() {
      if (opening) {
        _openingTime = result;
      } else {
        _closingTime = result;
      }
    });
  }

  String? _positiveNumber(String? value) {
    final parsed = double.tryParse(value?.trim() ?? '');
    return parsed == null || parsed <= 0
        ? 'Enter a number greater than 0.'
        : null;
  }

  String? _nonNegativeNumber(String? value) {
    final parsed = double.tryParse(value?.trim() ?? '');
    return parsed == null || parsed < 0
        ? 'Enter 0 or a positive number.'
        : null;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static TimeOfDay _parseTime(String? value, int fallbackHour) {
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value ?? '');
    final hour = int.tryParse(match?.group(1) ?? '');
    final minute = int.tryParse(match?.group(2) ?? '');
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return TimeOfDay(hour: fallbackHour, minute: 0);
    }
    return TimeOfDay(hour: hour, minute: minute);
  }

  static String _timeValue(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery Settings')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _settingsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('Failed to load settings.'));
          }

          if (!_initialized) {
            final settings = snapshot.data ?? const {};
            _storeOpen = settings['storeOpen'] as bool? ?? true;
            _maintenanceMode = settings['maintenanceMode'] as bool? ?? false;
            _deliveryEnabled = settings['deliveryEnabled'] as bool? ?? false;
            final latitude = (settings['hubLatitude'] as num?)?.toDouble();
            final longitude = (settings['hubLongitude'] as num?)?.toDouble();
            if (latitude != null && longitude != null) {
              _hubLocation = LatLng(latitude, longitude);
            }
            _radiusController.text =
                ((settings['deliveryRadiusKm'] as num?)?.toDouble() ?? 5)
                    .toString();
            _deliveryChargeController.text =
                ((settings['deliveryCharge'] as num?)?.toDouble() ?? 30)
                    .toString();
            _freeDeliveryController.text =
                ((settings['freeDeliveryMinimum'] as num?)?.toDouble() ?? 299)
                    .toString();
            _openingTime = _parseTime(settings['storeOpenTime']?.toString(), 7);
            _closingTime = _parseTime(
              settings['storeCloseTime']?.toString(),
              22,
            );
            _initialized = true;
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _section('Delivery Service', [
                      SwitchListTile(
                        title: const Text('Delivery Service'),
                        subtitle: const Text(
                          'Allow customers to place delivery orders',
                        ),
                        value: _deliveryEnabled,
                        onChanged: _isSaving
                            ? null
                            : (value) =>
                                  setState(() => _deliveryEnabled = value),
                      ),
                      ListTile(
                        leading: const Icon(
                          Icons.store_mall_directory_outlined,
                        ),
                        title: const Text('Hub / Store Location'),
                        subtitle: Text(
                          _hubLocation == null
                              ? 'No hub location selected'
                              : '${_hubLocation!.latitude.toStringAsFixed(6)}, ${_hubLocation!.longitude.toStringAsFixed(6)}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _isSaving ? null : _pickHubLocation,
                      ),
                      _numberField(
                        _radiusController,
                        'Delivery Radius',
                        _positiveNumber,
                        suffix: 'KM',
                      ),
                      _numberField(
                        _deliveryChargeController,
                        'Delivery Charge',
                        _nonNegativeNumber,
                        prefix: '₹ ',
                      ),
                      _numberField(
                        _freeDeliveryController,
                        'Free Delivery Minimum',
                        _nonNegativeNumber,
                        prefix: '₹ ',
                      ),
                    ]),
                    const SizedBox(height: 16),
                    _section('Store Timing', [
                      _timeTile('Opening Time', _openingTime, true),
                      _timeTile('Closing Time', _closingTime, false),
                    ]),
                    const SizedBox(height: 16),
                    _section('Existing App Controls', [
                      SwitchListTile(
                        title: const Text('Store Open'),
                        value: _storeOpen,
                        onChanged: _isSaving
                            ? null
                            : (value) => setState(() => _storeOpen = value),
                      ),
                      SwitchListTile(
                        title: const Text('Maintenance Mode'),
                        value: _maintenanceMode,
                        onChanged: _isSaving
                            ? null
                            : (value) =>
                                  setState(() => _maintenanceMode = value),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    _preview(),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _isSaving
                          ? null
                          : () => _saveSettings(context),
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(_isSaving ? 'Saving...' : 'Save / Update'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _numberField(
    TextEditingController controller,
    String label,
    FormFieldValidator<String> validator, {
    String? prefix,
    String? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: controller,
        enabled: !_isSaving,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          prefixText: prefix,
          suffixText: suffix,
          border: const OutlineInputBorder(),
        ),
        validator: validator,
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _timeTile(String label, TimeOfDay time, bool opening) {
    return ListTile(
      leading: const Icon(Icons.schedule_outlined),
      title: Text(label),
      subtitle: Text(time.format(context)),
      trailing: const Icon(Icons.edit_outlined),
      onTap: _isSaving ? null : () => _pickTime(opening: opening),
    );
  }

  Widget _preview() {
    final now = TimeOfDay.now();
    final current = now.hour * 60 + now.minute;
    final open = _openingTime.hour * 60 + _openingTime.minute;
    final close = _closingTime.hour * 60 + _closingTime.minute;
    final isOpen =
        open == close ||
        (open < close
            ? current >= open && current < close
            : current >= open || current < close);

    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current Preview',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _deliveryEnabled
                  ? 'Delivery service enabled'
                  : 'Delivery service unavailable',
            ),
            Text(isOpen ? 'Store is Open' : 'Store is currently closed'),
            Text(
              'Hours: ${_openingTime.format(context)} – ${_closingTime.format(context)}',
            ),
            Text(
              'Radius: ${_radiusController.text.trim().isEmpty ? '—' : _radiusController.text.trim()} KM',
            ),
          ],
        ),
      ),
    );
  }
}

class _HubLocationPicker extends StatefulWidget {
  const _HubLocationPicker({this.initialLocation});

  final LatLng? initialLocation;

  @override
  State<_HubLocationPicker> createState() => _HubLocationPickerState();
}

class _HubLocationPickerState extends State<_HubLocationPicker> {
  late LatLng _selectedLocation;

  @override
  void initState() {
    super.initState();
    _selectedLocation =
        widget.initialLocation ?? const LatLng(23.8315, 91.2868);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Hub Location'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(context, _selectedLocation),
            icon: const Icon(Icons.check),
            label: const Text('Use Location'),
          ),
        ],
      ),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: _selectedLocation,
          zoom: 15,
        ),
        markers: {
          Marker(markerId: const MarkerId('hub'), position: _selectedLocation),
        },
        onTap: (location) => setState(() => _selectedLocation = location),
      ),
    );
  }
}
