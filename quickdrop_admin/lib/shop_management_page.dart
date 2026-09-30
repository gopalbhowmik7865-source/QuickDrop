import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import 'firebase_options.dart';

final String _googlePlacesApiKey = String.fromEnvironment(
  'GOOGLE_PLACES_API_KEY',
  defaultValue: DefaultFirebaseOptions.android.apiKey,
);

class _PlaceSuggestion {
  const _PlaceSuggestion({required this.id, required this.description});

  final String id;
  final String description;
}

class _PlaceSelection {
  const _PlaceSelection({
    required this.address,
    required this.area,
    required this.location,
  });

  final String address;
  final String area;
  final LatLng location;
}

class _PlacesSearchException implements Exception {
  const _PlacesSearchException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _GooglePlacesClient {
  const _GooglePlacesClient();

  static const _center = '23.8315,91.2868';

  Future<List<_PlaceSuggestion>> autocomplete(String input) async {
    _ensureConfigured();
    final response = await http.get(
      Uri.https('maps.googleapis.com', '/maps/api/place/autocomplete/json', {
        'input': input,
        'location': _center,
        'radius': '30000',
        'components': 'country:in',
        'language': 'en',
        'key': _googlePlacesApiKey,
      }),
    );
    final data = _decode(response);
    final predictions = data['predictions'];
    if (predictions is! List) return const [];
    return predictions
        .whereType<Map>()
        .map(
          (item) => _PlaceSuggestion(
            id: item['place_id']?.toString() ?? '',
            description: item['description']?.toString() ?? '',
          ),
        )
        .where((item) => item.id.isNotEmpty && item.description.isNotEmpty)
        .toList();
  }

  Future<_PlaceSelection> details(_PlaceSuggestion suggestion) async {
    _ensureConfigured();
    final response = await http.get(
      Uri.https('maps.googleapis.com', '/maps/api/place/details/json', {
        'place_id': suggestion.id,
        'fields': 'formatted_address,address_components,geometry',
        'language': 'en',
        'key': _googlePlacesApiKey,
      }),
    );
    final data = _decode(response);
    final result = data['result'];
    if (result is! Map) {
      throw const _PlacesSearchException('Google returned no place details.');
    }
    final geometry = result['geometry'];
    final location = geometry is Map ? geometry['location'] : null;
    final latitude = location is Map
        ? double.tryParse(location['lat']?.toString() ?? '')
        : null;
    final longitude = location is Map
        ? double.tryParse(location['lng']?.toString() ?? '')
        : null;
    if (latitude == null || longitude == null) {
      throw const _PlacesSearchException('Selected place has no coordinates.');
    }

    final components = result['address_components'];
    final area = components is List
        ? components
              .whereType<Map>()
              .where((component) {
                final types = component['types'];
                return types is List &&
                    types.any(
                      (type) =>
                          type == 'sublocality' ||
                          type == 'sublocality_level_1' ||
                          type == 'locality',
                    );
              })
              .map((component) => component['long_name']?.toString() ?? '')
              .firstWhere((value) => value.isNotEmpty, orElse: () => '')
        : '';

    return _PlaceSelection(
      address:
          result['formatted_address']?.toString() ?? suggestion.description,
      area: area,
      location: LatLng(latitude, longitude),
    );
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode != 200) {
      throw const _PlacesSearchException('Google Places request failed.');
    }
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) {
      throw const _PlacesSearchException(
        'Google Places returned an invalid response.',
      );
    }
    final status = data['status']?.toString() ?? '';
    if (status != 'OK' && status != 'ZERO_RESULTS') {
      throw _PlacesSearchException(
        status == 'REQUEST_DENIED'
            ? 'Google Places API is disabled or the API key is restricted.'
            : 'Google Places error: $status',
      );
    }
    return data;
  }

  void _ensureConfigured() {
    if (_googlePlacesApiKey.trim().isEmpty) {
      throw const _PlacesSearchException(
        'Google Places search is not configured. Add a Places-enabled Google Maps API key.',
      );
    }
  }
}

class ShopManagementPage extends StatefulWidget {
  const ShopManagementPage({super.key});

  @override
  State<ShopManagementPage> createState() => _ShopManagementPageState();
}

class _ShopManagementPageState extends State<ShopManagementPage> {
  final CollectionReference<Map<String, dynamic>> _shopsRef = FirebaseFirestore
      .instance
      .collection('shops');

  Future<void> _showShopDialog({
    DocumentSnapshot<Map<String, dynamic>>? shop,
  }) async {
    final data = shop?.data() ?? const <String, dynamic>{};
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(
      text: data['name']?.toString() ?? '',
    );
    final addressController = TextEditingController(
      text: data['address']?.toString() ?? '',
    );
    final areaController = TextEditingController(
      text: data['area']?.toString() ?? '',
    );
    final phoneController = TextEditingController(
      text: data['phone']?.toString() ?? '',
    );
    final latitudeController = TextEditingController(
      text: data['latitude']?.toString() ?? '',
    );
    final longitudeController = TextEditingController(
      text: data['longitude']?.toString() ?? '',
    );
    String imageUrl = data['imageUrl']?.toString() ?? '';
    bool isActive = data['isActive'] as bool? ?? true;
    bool uploading = false;

    LatLng? savedLocation;
    final latitude = (data['latitude'] as num?)?.toDouble();
    final longitude = (data['longitude'] as num?)?.toDouble();
    if (latitude != null && longitude != null) {
      savedLocation = LatLng(latitude, longitude);
    }

    Future<void> pickImage(StateSetter setDialogState) async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      final bytes = result?.files.single.bytes;
      if (bytes == null || bytes.isEmpty) return;
      setDialogState(() => uploading = true);
      try {
        final safeName = result!.files.single.name.replaceAll(
          RegExp(r'[^a-zA-Z0-9._-]'),
          '_',
        );
        final ref = FirebaseStorage.instance.ref().child(
          'shop_images/${DateTime.now().millisecondsSinceEpoch}_$safeName',
        );
        await ref.putData(Uint8List.fromList(bytes));
        imageUrl = await ref.getDownloadURL();
      } finally {
        if (context.mounted) setDialogState(() => uploading = false);
      }
    }

    Future<void> pickLocation(StateSetter setDialogState) async {
      final result = await Navigator.of(context).push<LatLng>(
        MaterialPageRoute(
          builder: (_) => _ShopLocationPicker(initialLocation: savedLocation),
        ),
      );
      if (result == null) return;
      savedLocation = result;
      latitudeController.text = result.latitude.toStringAsFixed(6);
      longitudeController.text = result.longitude.toStringAsFixed(6);
      setDialogState(() {});
    }

    Future<void> searchLocation(StateSetter setDialogState) async {
      final selection = await showDialog<_PlaceSelection>(
        context: context,
        builder: (_) => const _PlaceSearchDialog(),
      );
      if (selection == null) return;
      savedLocation = selection.location;
      addressController.text = selection.address;
      areaController.text = selection.area;
      latitudeController.text = selection.location.latitude.toStringAsFixed(6);
      longitudeController.text = selection.location.longitude.toStringAsFixed(
        6,
      );
      setDialogState(() {});
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(shop == null ? 'Add Shop' : 'Edit Shop'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (imageUrl.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Image.network(
                          imageUrl,
                          height: 90,
                          fit: BoxFit.contain,
                        ),
                      ),
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Shop Name'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Enter shop name'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: uploading
                                ? null
                                : () => pickImage(setDialogState),
                            icon: uploading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.upload_file_outlined),
                            label: const Text('Shop Image'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => pickLocation(setDialogState),
                            icon: const Icon(Icons.map_outlined),
                            label: Text(
                              savedLocation == null
                                  ? 'Pick Location'
                                  : 'Location Set',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => searchLocation(setDialogState),
                            icon: const Icon(Icons.search_outlined),
                            label: const Text('Search Location'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: addressController,
                      decoration: const InputDecoration(
                        labelText: 'Full Address',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Enter address'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: areaController,
                      decoration: const InputDecoration(
                        labelText: 'Area / Locality',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: latitudeController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Latitude',
                            ),
                            validator: (value) =>
                                double.tryParse(value?.trim() ?? '') == null
                                ? 'Required'
                                : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: longitudeController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Longitude',
                            ),
                            validator: (value) =>
                                double.tryParse(value?.trim() ?? '') == null
                                ? 'Required'
                                : null,
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Active Shop'),
                      value: isActive,
                      onChanged: (value) =>
                          setDialogState(() => isActive = value),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false) || uploading) {
                  return;
                }
                final payload = <String, dynamic>{
                  'storeId': shop?.id,
                  'name': nameController.text.trim(),
                  'imageUrl': imageUrl,
                  'address': addressController.text.trim(),
                  'area': areaController.text.trim(),
                  'phone': phoneController.text.trim(),
                  'latitude': double.parse(latitudeController.text.trim()),
                  'longitude': double.parse(longitudeController.text.trim()),
                  'isActive': isActive,
                  'updatedAt': FieldValue.serverTimestamp(),
                };
                if (shop == null) {
                  final reference = _shopsRef.doc();
                  payload['storeId'] = reference.id;
                  payload['createdAt'] = FieldValue.serverTimestamp();
                  await reference.set(payload);
                } else {
                  await shop.reference.update(payload);
                }
                if (dialogContext.mounted) Navigator.pop(dialogContext, true);
              },
              child: Text(shop == null ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    addressController.dispose();
    areaController.dispose();
    phoneController.dispose();
    latitudeController.dispose();
    longitudeController.dispose();
    if (result == true && mounted) setState(() {});
  }

  Future<void> _deleteShop(DocumentSnapshot<Map<String, dynamic>> shop) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete shop?'),
        content: Text('Delete ${shop.data()?['name'] ?? 'this shop'}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final inventorySnapshot = await shop.reference
        .collection('inventory')
        .get();
    for (var start = 0; start < inventorySnapshot.docs.length; start += 400) {
      final batch = FirebaseFirestore.instance.batch();
      final end = (start + 400).clamp(0, inventorySnapshot.docs.length);
      for (final inventoryDocument in inventorySnapshot.docs.sublist(
        start,
        end,
      )) {
        batch.delete(inventoryDocument.reference);
      }
      await batch.commit();
    }
    await shop.reference.delete();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Shop deleted.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shop Management'),
        actions: [
          FilledButton.icon(
            onPressed: () => _showShopDialog(),
            icon: const Icon(Icons.add_business_outlined),
            label: const Text('Add Shop'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _shopsRef.orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Unable to load shops.\n${snapshot.error}'),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final shops = snapshot.data?.docs ?? const [];
          if (shops.isEmpty) {
            return const Center(child: Text('No shops added yet.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: shops.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final shop = shops[index];
              final data = shop.data();
              final active = data['isActive'] as bool? ?? false;
              return Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  leading: SizedBox(
                    width: 64,
                    height: 64,
                    child: data['imageUrl']?.toString().isNotEmpty == true
                        ? Image.network(
                            data['imageUrl'].toString(),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                const Icon(Icons.storefront_outlined, size: 36),
                          )
                        : const Icon(Icons.storefront_outlined, size: 36),
                  ),
                  title: Text(data['name']?.toString() ?? 'Unnamed shop'),
                  subtitle: Text(
                    '${data['area'] ?? data['address'] ?? ''}\n${active ? 'Active' : 'Inactive'}',
                  ),
                  isThreeLine: true,
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        tooltip: 'Manage Products',
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ShopInventoryPage(
                              shopId: shop.id,
                              shopName: data['name']?.toString() ?? 'Shop',
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.inventory_2_outlined),
                      ),
                      IconButton(
                        onPressed: () => _showShopDialog(shop: shop),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        onPressed: () => _deleteShop(shop),
                        icon: const Icon(Icons.delete_outline),
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
}

class ShopInventoryPage extends StatefulWidget {
  const ShopInventoryPage({
    super.key,
    required this.shopId,
    required this.shopName,
  });

  final String shopId;
  final String shopName;

  @override
  State<ShopInventoryPage> createState() => _ShopInventoryPageState();
}

class _ShopInventoryPageState extends State<ShopInventoryPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _saveInventory(
    String productId,
    bool available,
    int stock,
  ) async {
    await FirebaseFirestore.instance
        .collection('shops')
        .doc(widget.shopId)
        .collection('inventory')
        .doc(productId)
        .set({
          'productId': productId,
          'available': available,
          'stock': stock < 0 ? 0 : stock,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<void> _editInventory(
    String productId,
    Map<String, dynamic> current,
  ) async {
    final controller = TextEditingController(
      text: (current['stock'] as num?)?.toInt().toString() ?? '0',
    );
    bool available = current['available'] as bool? ?? false;
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Shop Inventory'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text('Available'),
                  value: available,
                  onChanged: (value) => setDialogState(() => available = value),
                ),
                TextFormField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Stock Quantity',
                  ),
                  validator: (value) =>
                      int.tryParse(value?.trim() ?? '') == null
                      ? 'Enter a whole number'
                      : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                await _saveInventory(
                  productId,
                  available,
                  int.parse(controller.text.trim()),
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Shop Inventory • ${widget.shopName}')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('products')
            .orderBy('name')
            .snapshots(),
        builder: (context, productSnapshot) {
          if (productSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (productSnapshot.hasError) {
            return Center(
              child: Text('Unable to load products.\n${productSnapshot.error}'),
            );
          }
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('shops')
                .doc(widget.shopId)
                .collection('inventory')
                .snapshots(),
            builder: (context, inventorySnapshot) {
              if (inventorySnapshot.connectionState ==
                  ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final inventory = {
                for (final doc in inventorySnapshot.data?.docs ?? const [])
                  doc.id: doc.data(),
              };
              final products = (productSnapshot.data?.docs ?? const []).where((
                doc,
              ) {
                if (_searchQuery.isEmpty) return true;
                final data = doc.data();
                return '${data['name'] ?? ''} ${data['category'] ?? ''} ${data['subcategory'] ?? ''}'
                    .toLowerCase()
                    .contains(_searchQuery);
              }).toList();
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) => setState(
                        () => _searchQuery = value.trim().toLowerCase(),
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Search products',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: products.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final product = products[index];
                        final data = product.data();
                        final current =
                            inventory[product.id] ?? const <String, dynamic>{};
                        final available =
                            current['available'] as bool? ?? false;
                        final stock = (current['stock'] as num?)?.toInt() ?? 0;
                        return Card(
                          child: ListTile(
                            title: Text(data['name']?.toString() ?? 'Product'),
                            subtitle: Text(
                              '${data['category'] ?? ''} • ${available && stock > 0 ? 'Available' : 'Unavailable'} • Stock: $stock',
                            ),
                            trailing: FilledButton.tonal(
                              onPressed: () =>
                                  _editInventory(product.id, current),
                              child: const Text('Manage'),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _ShopLocationPicker extends StatefulWidget {
  const _ShopLocationPicker({this.initialLocation});

  final LatLng? initialLocation;

  @override
  State<_ShopLocationPicker> createState() => _ShopLocationPickerState();
}

class _PlaceSearchDialog extends StatefulWidget {
  const _PlaceSearchDialog();

  @override
  State<_PlaceSearchDialog> createState() => _PlaceSearchDialogState();
}

class _PlaceSearchDialogState extends State<_PlaceSearchDialog> {
  final _controller = TextEditingController();
  final _client = const _GooglePlacesClient();
  Timer? _debounce;
  List<_PlaceSuggestion> _suggestions = const [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _search(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 3) {
      setState(() {
        _suggestions = const [];
        _error = null;
        _loading = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() {
        _loading = true;
        _error = null;
      });
      try {
        final suggestions = await _client.autocomplete(query);
        if (!mounted) return;
        setState(() => _suggestions = suggestions);
      } on _PlacesSearchException catch (error) {
        if (!mounted) return;
        setState(() {
          _suggestions = const [];
          _error = error.message;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _suggestions = const [];
          _error = 'Unable to search Google Places right now.';
        });
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  Future<void> _select(_PlaceSuggestion suggestion) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final selection = await _client.details(suggestion);
      if (mounted) Navigator.pop(context, selection);
    } on _PlacesSearchException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Unable to load the selected place.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Search Location'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _search,
              decoration: const InputDecoration(
                labelText: 'Search shop, road, area or address',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: LinearProgressIndicator(),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_suggestions.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _suggestions.length,
                  itemBuilder: (context, index) {
                    final suggestion = _suggestions[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.location_on_outlined),
                      title: Text(suggestion.description),
                      onTap: () => _select(suggestion),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _ShopLocationPickerState extends State<_ShopLocationPicker> {
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
        title: const Text('Select Shop Location'),
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
          Marker(markerId: const MarkerId('shop'), position: _selectedLocation),
        },
        onTap: (location) => setState(() => _selectedLocation = location),
      ),
    );
  }
}
