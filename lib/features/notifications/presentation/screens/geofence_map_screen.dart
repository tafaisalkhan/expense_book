import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:myexpence/core/theme/app_theme.dart';
import 'package:myexpence/core/utils/date_formatters.dart';
import 'package:myexpence/features/expenses/domain/models/expense.dart';
import 'package:myexpence/features/expenses/domain/models/expense_classification.dart';
import 'package:myexpence/features/notifications/domain/models/geofence_target.dart';
import 'package:myexpence/features/notifications/domain/models/location_notification.dart';
import 'package:myexpence/features/notifications/domain/services/location_permission_service.dart';
import 'package:myexpence/features/notifications/presentation/providers/location_notification_providers.dart';
import 'package:uuid/uuid.dart';

class GeofenceMapScreen extends ConsumerStatefulWidget {
  const GeofenceMapScreen({super.key});

  @override
  ConsumerState<GeofenceMapScreen> createState() => _GeofenceMapScreenState();
}

class _GeofenceMapScreenState extends ConsumerState<GeofenceMapScreen> {
  late final TextEditingController _nameController;
  final MapController _mapController = MapController();

  LatLng _selectedPoint = const LatLng(31.5204, 74.3587);
  LatLng _userCurrentGpsPoint = const LatLng(31.5204, 74.3587);
  bool _isFetchingLocation = false;
  double _radiusMeters = 200;
  double _currentZoom = 15.0;
  LocationType _locationType = LocationType.petrolPump;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: LocationType.petrolPump.label);
    _fetchDeviceLocation();
  }

  Future<void> _fetchDeviceLocation() async {
    setState(() {
      _isFetchingLocation = true;
    });

    final loc = await LocationPermissionService.getCurrentDeviceLocation();
    final double lat = (loc['latitude'] as num?)?.toDouble() ?? 31.5204;
    final double lng = (loc['longitude'] as num?)?.toDouble() ?? 74.3587;

    if (mounted) {
      setState(() {
        _userCurrentGpsPoint = LatLng(lat, lng);
        _selectedPoint = _userCurrentGpsPoint;
        _isFetchingLocation = false;
      });
      _mapController.move(_userCurrentGpsPoint, _currentZoom);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _zoomIn() {
    setState(() {
      _currentZoom = (_currentZoom + 1.0).clamp(3.0, 19.0);
      _mapController.move(_selectedPoint, _currentZoom);
    });
  }

  void _zoomOut() {
    setState(() {
      _currentZoom = (_currentZoom - 1.0).clamp(3.0, 19.0);
      _mapController.move(_selectedPoint, _currentZoom);
    });
  }

  Future<void> _recenterUserLocation() async {
    await _fetchDeviceLocation();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('📍 Map centered on your current GPS location (${_userCurrentGpsPoint.latitude.toStringAsFixed(4)}, ${_userCurrentGpsPoint.longitude.toStringAsFixed(4)})'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showMarkerActionBottomSheet({
    required String title,
    required LocationType locationType,
    required LatLng point,
    GeofenceTarget? target,
  }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    locationType == LocationType.petrolPump
                        ? Icons.local_gas_station
                        : (locationType == LocationType.superMarket ? Icons.shopping_cart : Icons.store),
                    color: AppTheme.primaryColor,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${locationType.label} • (${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)})',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),

              // Button 1: Add Expense for this Marker
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    final nowStr = DateTime.now().toIso8601String();
                    final draftExpense = Expense(
                      uuid: '',
                      amount: 0.0,
                      categoryId: locationType.defaultCategoryId,
                      classification: ExpenseClassification.required,
                      expenseDate: DateFormatters.formatDateIso(DateTime.now()),
                      createdAt: nowStr,
                      updatedAt: nowStr,
                      merchant: title,
                      notes: 'Expense at $title (${locationType.label})',
                    );
                    context.push('/add', extra: draftExpense);
                  },
                  icon: const Icon(Icons.add_circle_outline),
                  label: Text('➕ Add Expense for $title', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _saveGeofence() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final target = GeofenceTarget(
      id: const Uuid().v4(),
      name: name,
      locationType: _locationType,
      latitude: _selectedPoint.latitude,
      longitude: _selectedPoint.longitude,
      radiusMeters: _radiusMeters,
    );

    ref.read(locationNotificationProvider.notifier).addGeofenceTarget(target);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('🎯 Saved Geofence target "$name" (${_locationType.label})!')),
      );
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Real Map Location Picker'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: 'My Location',
            onPressed: _recenterUserLocation,
          ),
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Save Geofence',
            onPressed: _saveGeofence,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Real OpenStreetMap Interactive View (Showing Petrol Pumps, Malls, Roads & Shops)
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _selectedPoint,
                      initialZoom: _currentZoom,
                      minZoom: 3.0,
                      maxZoom: 19.0,
                      onTap: (tapPosition, point) {
                        setState(() {
                          _selectedPoint = point;
                        });
                      },
                    ),
                    children: [
                      // Real Map Tiles (OpenStreetMap - Google Map equivalent streets, petrol pumps & places)
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.myexpense.book',
                      ),

                      // Geofence Radius Circle Layer
                      CircleLayer(
                        circles: [
                          CircleMarker(
                            point: _selectedPoint,
                            radius: _radiusMeters,
                            useRadiusInMeter: true,
                            color: AppTheme.primaryColor.withValues(alpha: 0.22),
                            borderColor: AppTheme.primaryColor,
                            borderStrokeWidth: 2.5,
                          ),
                        ],
                      ),

                      // Location Pins Layer
                      MarkerLayer(
                        markers: [
                          // User GPS Marker
                          Marker(
                            point: _userCurrentGpsPoint,
                            width: 44,
                            height: 44,
                            child: GestureDetector(
                              onTap: () => _showMarkerActionBottomSheet(
                                title: 'My GPS Location',
                                locationType: _locationType,
                                point: _userCurrentGpsPoint,
                              ),
                              child: const Icon(Icons.person_pin_circle, color: Colors.blue, size: 40),
                            ),
                          ),
                          // Selected Geofence Target Pin
                          Marker(
                            point: _selectedPoint,
                            width: 50,
                            height: 50,
                            child: GestureDetector(
                              onTap: () => _showMarkerActionBottomSheet(
                                title: _nameController.text.trim().isNotEmpty ? _nameController.text.trim() : _locationType.label,
                                locationType: _locationType,
                                point: _selectedPoint,
                              ),
                              child: const Icon(Icons.location_pin, color: Colors.red, size: 50),
                            ),
                          ),
                          // Saved Geofence Target Pins
                          ...ref.watch(locationNotificationProvider).savedGeofences.map((target) {
                            return Marker(
                              point: LatLng(target.latitude, target.longitude),
                              width: 44,
                              height: 44,
                              child: GestureDetector(
                                onTap: () => _showMarkerActionBottomSheet(
                                  title: target.name,
                                  locationType: target.locationType,
                                  point: LatLng(target.latitude, target.longitude),
                                  target: target,
                                ),
                                child: Icon(
                                  target.locationType == LocationType.petrolPump
                                      ? Icons.local_gas_station
                                      : (target.locationType == LocationType.superMarket ? Icons.shopping_cart : Icons.store),
                                  color: AppTheme.primaryColor,
                                  size: 36,
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ],
                  ),

                  // Coordinates Header Display
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.my_location, color: Colors.greenAccent, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            'Lat: ${_selectedPoint.latitude.toStringAsFixed(4)}, Lng: ${_selectedPoint.longitude.toStringAsFixed(4)} (Zoom: ${_currentZoom.round()})',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // User Location Badge
                  Positioned(
                    bottom: 16,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.blue[800],
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                      ),
                      child: Row(
                        children: [
                          if (_isFetchingLocation)
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          else
                            const Icon(Icons.person_pin_circle, color: Colors.white, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            _isFetchingLocation
                                ? 'Acquiring GPS Location...'
                                : 'Your GPS: ${_userCurrentGpsPoint.latitude.toStringAsFixed(4)}, ${_userCurrentGpsPoint.longitude.toStringAsFixed(4)}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Floating Map Zoom In / Zoom Out Controls
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Column(
                      children: [
                        FloatingActionButton.small(
                          heroTag: 'btnZoomInReal',
                          onPressed: _zoomIn,
                          backgroundColor: Colors.white,
                          child: const Icon(Icons.add, color: Colors.black87),
                        ),
                        const SizedBox(height: 8),
                        FloatingActionButton.small(
                          heroTag: 'btnZoomOutReal',
                          onPressed: _zoomOut,
                          backgroundColor: Colors.white,
                          child: const Icon(Icons.remove, color: Colors.black87),
                        ),
                        const SizedBox(height: 8),
                        FloatingActionButton.small(
                          heroTag: 'btnMyLocReal',
                          onPressed: _recenterUserLocation,
                          backgroundColor: AppTheme.primaryColor,
                          child: const Icon(Icons.gps_fixed, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Bottom Geofence Settings Controls Panel
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.42,
              ),
              child: Card(
                margin: EdgeInsets.zero,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                elevation: 8,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.place, color: AppTheme.primaryColor),
                          const SizedBox(width: 8),
                          const Text('Geofence Settings', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                          const Spacer(),
                          Chip(
                            avatar: const Icon(Icons.radar, size: 14, color: AppTheme.primaryColor),
                            label: Text('${_radiusMeters.round()}m radius', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<LocationType>(
                        value: _locationType,
                        decoration: const InputDecoration(
                          labelText: 'Category / Location Type *',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        ),
                        items: LocationType.values.map((t) {
                          return DropdownMenuItem(
                            value: t,
                            child: Text('${t.label} (${t.defaultCategoryName})', style: const TextStyle(fontSize: 12)),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _locationType = val;
                              _nameController.text = val.label;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Place Name *',
                          hintText: 'e.g. Shell Petrol Pump, Metro Super Market',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        ),
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Text('Radius:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [20, 50, 100, 200, 500].map((r) {
                                  final isSelected = _radiusMeters.round() == r;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 6.0),
                                    child: ChoiceChip(
                                      label: Text('${r}m', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : AppTheme.primaryColor)),
                                      selected: isSelected,
                                      selectedColor: AppTheme.primaryColor,
                                      backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                                      visualDensity: VisualDensity.compact,
                                      onSelected: (_) => setState(() => _radiusMeters = r.toDouble()),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Slider(
                              value: _radiusMeters,
                              min: 10,
                              max: 1000,
                              divisions: 99,
                              label: '${_radiusMeters.round()}m',
                              activeColor: AppTheme.primaryColor,
                              onChanged: (val) => setState(() => _radiusMeters = val),
                            ),
                          ),
                          Text('${_radiusMeters.round()}m', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Live Proximity & Distance Calculation Badge
                      Builder(builder: (context) {
                        final double liveDist = Geolocator.distanceBetween(
                          _userCurrentGpsPoint.latitude,
                          _userCurrentGpsPoint.longitude,
                          _selectedPoint.latitude,
                          _selectedPoint.longitude,
                        );
                        final bool isInsideRange = liveDist <= _radiusMeters;
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isInsideRange ? Colors.green.shade50 : Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: isInsideRange ? Colors.green : Colors.orange),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isInsideRange ? Icons.check_circle : Icons.warning_amber_rounded,
                                color: isInsideRange ? Colors.green.shade700 : Colors.orange.shade800,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  isInsideRange
                                      ? '🟢 Inside Range (${liveDist.round()}m away <= ${_radiusMeters.round()}m)'
                                      : '🔴 Outside Range (${liveDist.round()}m away > ${_radiusMeters.round()}m)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isInsideRange ? Colors.green.shade900 : Colors.orange.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.green,
                                side: const BorderSide(color: Colors.green),
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () async {
                                final name = _nameController.text.trim().isNotEmpty ? _nameController.text.trim() : _locationType.label;
                                final target = GeofenceTarget(
                                  id: const Uuid().v4(),
                                  name: name,
                                  locationType: _locationType,
                                  latitude: _selectedPoint.latitude,
                                  longitude: _selectedPoint.longitude,
                                  radiusMeters: _radiusMeters,
                                );
                                await ref.read(locationNotificationProvider.notifier).simulateEnterGeofence(target);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('🟢 Triggered ENTER Range for "$name"! Notification posted.')),
                                  );
                                }
                              },
                              icon: const Icon(Icons.login, size: 16),
                              label: const Text('🟢 Test Enter', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () async {
                                final name = _nameController.text.trim().isNotEmpty ? _nameController.text.trim() : _locationType.label;
                                final target = GeofenceTarget(
                                  id: const Uuid().v4(),
                                  name: name,
                                  locationType: _locationType,
                                  latitude: _selectedPoint.latitude,
                                  longitude: _selectedPoint.longitude,
                                  radiusMeters: _radiusMeters,
                                );
                                await ref.read(locationNotificationProvider.notifier).simulateExitGeofence(target);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('🔴 Triggered EXIT Range for "$name"! Notification posted.')),
                                  );
                                }
                              },
                              icon: const Icon(Icons.logout, size: 16),
                              label: const Text('🔴 Test Exit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _saveGeofence,
                        icon: const Icon(Icons.save, size: 18),
                        label: const Text('Save & Set Geofence Zone', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
