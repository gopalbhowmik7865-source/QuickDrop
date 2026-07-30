import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../services/location_service.dart';

class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({
    super.key,
    this.title = 'Select Location',
    this.initialPosition,
  });

  final String title;
  final LatLng? initialPosition;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  static const String _googlePlacesApiKey =
      'AIzaSyCjf0K9nQ94IhqeVPt-SgiQGsImZ74D3cs';
  static const String _androidPackageName = 'com.example.quickdrop';
  static const String _androidCertSha1 =
      'BC:95:A8:E8:91:B2:62:01:15:BE:67:D8:DB:EE:C4:26:30:0E:E8:34';
  static const CameraPosition _fallbackCameraPosition = CameraPosition(
    target: LatLng(23.8315, 91.2868),
    zoom: 14,
  );

  final LocationService _locationService = const LocationService();

  GoogleMapController? _mapController;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  int _autocompleteRequestCount = 0;
  String _lastDispatchedQuery = '';

  LatLng? _selectedLatLng;
  bool _isLoadingLocation = true;
  bool _hasLocationPermission = false;
  bool _isLoadingSuggestions = false;
  String? _errorMessage;
  List<_PlaceSuggestion> _suggestions = <_PlaceSuggestion>[];
  String _placesSessionToken = DateTime.now().microsecondsSinceEpoch.toString();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchControllerChanged);
    _initializeLocation();
  }

  void _onSearchControllerChanged() {
    _onSearchQueryChanged(_searchController.text);
  }

  Future<void> _initializeLocation() async {
    setState(() {
      _isLoadingLocation = true;
      _errorMessage = null;
    });

    try {
      if (widget.initialPosition != null) {
        _selectedLatLng = widget.initialPosition;
        _hasLocationPermission = await _hasGrantedLocationPermission();
      } else {
        final position = await _locationService.getCurrentPosition();
        _selectedLatLng = LatLng(position.latitude, position.longitude);
        _hasLocationPermission = true;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingLocation = false;
      });

      final mapController = _mapController;
      final selectedLatLng = _selectedLatLng;
      if (mapController != null && selectedLatLng != null) {
        await mapController.animateCamera(
          CameraUpdate.newLatLngZoom(selectedLatLng, 16),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingLocation = false;
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<bool> _hasGrantedLocationPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  void _onSearchQueryChanged(String query) {
    final trimmed = query.trim();
    if (trimmed == _lastDispatchedQuery) {
      return;
    }
    _lastDispatchedQuery = trimmed;

    debugPrint('QuickDropPlaces Search text: "$trimmed"');
    unawaited(_fetchPlaceSuggestions(trimmed));
  }

  Future<void> _fetchPlaceSuggestions(String query) async {
    if (query.isEmpty) {
      if (!mounted) {
        return;
      }

      setState(() {
        _suggestions = <_PlaceSuggestion>[];
        _isLoadingSuggestions = false;
      });
      return;
    }

    setState(() {
      _isLoadingSuggestions = true;
    });

    try {
      _autocompleteRequestCount += 1;
      final requestId = _autocompleteRequestCount;

      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/autocomplete/json',
        <String, String>{
          'input': query,
          'key': _googlePlacesApiKey,
          'sessiontoken': _placesSessionToken,
          'components': 'country:in',
        },
      );

      const requestHeaders = <String, String>{
        'X-Android-Package': _androidPackageName,
        'X-Android-Cert': _androidCertSha1,
      };

      final response = await http.get(uri, headers: requestHeaders);
      debugPrint('QuickDropPlaces Request #$requestId URL: $uri');
      debugPrint('QuickDropPlaces Request #$requestId headers: $requestHeaders');
      debugPrint('QuickDropPlaces Request #$requestId status: ${response.statusCode}');
      debugPrint('QuickDropPlaces Request #$requestId response: ${response.body}');
      if (response.statusCode != 200) {
        throw Exception('Search failed (${response.statusCode})');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final status = decoded['status']?.toString() ?? '';
      if (status != 'OK' && status != 'ZERO_RESULTS') {
        final message = decoded['error_message']?.toString();
        throw Exception(message ?? 'Places API error: $status');
      }

      final predictions = (decoded['predictions'] as List<dynamic>? ?? <dynamic>[])
          .cast<Map<String, dynamic>>();
      final suggestions = predictions
          .map(
            (prediction) => _PlaceSuggestion(
              placeId: prediction['place_id']?.toString() ?? '',
              description: prediction['description']?.toString() ?? '',
            ),
          )
          .where((suggestion) => suggestion.placeId.isNotEmpty)
          .toList(growable: false);

      if (!mounted) {
        return;
      }

      setState(() {
        _suggestions = suggestions;
        _isLoadingSuggestions = false;
      });
    } catch (error, stackTrace) {
      debugPrint('QuickDropPlaces Request failed: $error');
      developer.log(
        'Places Autocomplete failed: $error',
        name: 'QuickDropPlaces',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingSuggestions = false;
        _suggestions = <_PlaceSuggestion>[];
      });
    }
  }

  Future<void> _onSuggestionSelected(_PlaceSuggestion suggestion) async {
    _searchController.text = suggestion.description;
    _searchFocusNode.unfocus();
    setState(() {
      _suggestions = <_PlaceSuggestion>[];
    });

    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/details/json',
        <String, String>{
          'place_id': suggestion.placeId,
          'fields': 'geometry',
          'key': _googlePlacesApiKey,
          'sessiontoken': _placesSessionToken,
        },
      );

      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Location lookup failed (${response.statusCode})');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final status = decoded['status']?.toString() ?? '';
      if (status != 'OK') {
        final message = decoded['error_message']?.toString();
        throw Exception(message ?? 'Place details error: $status');
      }

      final location =
          ((decoded['result'] as Map<String, dynamic>)['geometry'] as Map<String, dynamic>)['location']
              as Map<String, dynamic>;

      final lat = (location['lat'] as num).toDouble();
      final lng = (location['lng'] as num).toDouble();
      final selected = LatLng(lat, lng);

      if (!mounted) {
        return;
      }

      setState(() {
        _selectedLatLng = selected;
        _placesSessionToken = DateTime.now().microsecondsSinceEpoch.toString();
      });

      await _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(selected, 16),
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

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    
    // Optimize map rendering
    controller.setMapStyle(null); // Use default style

    final selectedLatLng = _selectedLatLng;
    if (selectedLatLng != null) {
      controller.animateCamera(
        CameraUpdate.newLatLngZoom(selectedLatLng, 16),
      );
    }
  }

  void _onMapTap(LatLng latLng) {
    setState(() {
      _selectedLatLng = latLng;
    });
  }

  void _confirmLocation() {
    final selectedLatLng = _selectedLatLng;
    if (selectedLatLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a location first.')),
      );
      return;
    }

    Navigator.of(context).pop(selectedLatLng);
  }

  Set<Marker> _buildMarkers() {
    final selectedLatLng = _selectedLatLng;
    if (selectedLatLng == null) {
      return <Marker>{};
    }

    return <Marker>{
      Marker(
        markerId: const MarkerId('selected_location'),
        position: selectedLatLng,
      ),
    };
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchControllerChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedLatLng = _selectedLatLng;
    final initialCameraPosition = selectedLatLng == null
        ? _fallbackCameraPosition
        : CameraPosition(target: selectedLatLng, zoom: 16);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: initialCameraPosition,
            onMapCreated: _onMapCreated,
            myLocationEnabled: _hasLocationPermission,
            myLocationButtonEnabled: _hasLocationPermission,
            markers: _buildMarkers(),
            onTap: _onMapTap,
            mapType: MapType.normal,
            zoomGesturesEnabled: true,
            scrollGesturesEnabled: true,
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: true,
            liteModeEnabled: false,
            compassEnabled: true,
            mapToolbarEnabled: true,
            cameraTargetBounds: CameraTargetBounds.unbounded,
            minMaxZoomPreference: const MinMaxZoomPreference(0, 21),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Material(
                    elevation: 3,
                    borderRadius: BorderRadius.circular(12),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      onChanged: _onSearchQueryChanged,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search place',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _isLoadingSuggestions
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : (_searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {
                                        _suggestions = <_PlaceSuggestion>[];
                                      });
                                    },
                                  )
                                : null),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  if (_suggestions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x22000000),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _suggestions.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final suggestion = _suggestions[index];
                          return ListTile(
                            dense: true,
                            title: Text(
                              suggestion.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _onSuggestionSelected(suggestion),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_isLoadingLocation)
            const Center(child: CircularProgressIndicator()),
          if (_errorMessage != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 88,
              child: Material(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: Colors.red.shade700),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _confirmLocation,
            child: const Text('Confirm Location'),
          ),
        ),
      ),
    );
  }
}

class _PlaceSuggestion {
  const _PlaceSuggestion({required this.placeId, required this.description});

  final String placeId;
  final String description;
}
