import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

class LocationContextResult {
  const LocationContextResult({
    required this.context,
    this.notice = '',
    this.latitude,
    this.longitude,
    this.accuracyMeters,
    this.addressLine = '',
    this.locality = '',
    this.adminArea = '',
    this.country = '',
  });

  final String context;
  final String notice;
  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;
  final String addressLine;
  final String locality;
  final String adminArea;
  final String country;
}

class LocationContextService {
  const LocationContextService({
    MethodChannel channel = const MethodChannel('essential/location_context'),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<LocationContextResult> currentForWeb() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return const LocationContextResult(
          context: '',
          notice: '位置情報へのアクセスが許可されなかったため、利用可能な情報だけで回答します。',
        );
      }
      final position = await Geolocator.getCurrentPosition(
        timeLimit: const Duration(seconds: 12),
      );
      final address = await _reverseGeocode(position);
      final addressContext = _formatAddressContext(address, position);
      return LocationContextResult(
        context: addressContext,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        addressLine: address['addressLine']?.toString() ?? '',
        locality: address['locality']?.toString() ?? '',
        adminArea: address['adminArea']?.toString() ?? '',
        country: address['country']?.toString() ?? '',
      );
    } catch (error) {
      debugPrint('Location context unavailable: $error');
      return const LocationContextResult(
        context: '',
        notice: '位置情報を取得できなかったため、利用可能な情報だけで回答します。',
      );
    }
  }

  Future<Map<Object?, Object?>> _reverseGeocode(Position position) async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'reverseGeocode',
        <String, Object?>{
          'latitude': position.latitude,
          'longitude': position.longitude,
        },
      );
      return result ?? const <Object?, Object?>{};
    } catch (error) {
      debugPrint('Reverse geocode failed: $error');
      return const <Object?, Object?>{};
    }
  }

  String _formatAddressContext(
    Map<Object?, Object?> address,
    Position position,
  ) {
    final addressLine = address['addressLine']?.toString().trim() ?? '';
    final locality = address['locality']?.toString().trim() ?? '';
    final subAdminArea = address['subAdminArea']?.toString().trim() ?? '';
    final adminArea = address['adminArea']?.toString().trim() ?? '';
    final country = address['country']?.toString().trim() ?? '';
    final parts = <String>[
      if (addressLine.isNotEmpty) addressLine,
      if (addressLine.isEmpty && locality.isNotEmpty) locality,
      if (addressLine.isEmpty && subAdminArea.isNotEmpty) subAdminArea,
      if (addressLine.isEmpty && adminArea.isNotEmpty) adminArea,
      if (country.isNotEmpty) country,
    ];
    final coordinate =
        '緯度 ${position.latitude.toStringAsFixed(6)}, '
        '経度 ${position.longitude.toStringAsFixed(6)}, '
        '精度 約${position.accuracy.toStringAsFixed(0)}m';
    if (parts.isEmpty) {
      return coordinate;
    }
    return '住所 ${parts.join(' / ')} ($coordinate)';
  }
}
