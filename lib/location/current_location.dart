import 'package:flutter/services.dart';

class CurrentLocation {
  static const _channel = MethodChannel('cbpak/location');

  static Future<({double latitude, double longitude})> get() async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'getCurrentLocation',
    );
    final latitude = result?['latitude'] as num?;
    final longitude = result?['longitude'] as num?;
    if (latitude == null || longitude == null) {
      throw PlatformException(
        code: 'location_unavailable',
        message: 'Phone location could not be read. Enter it manually instead.',
      );
    }
    return (latitude: latitude.toDouble(), longitude: longitude.toDouble());
  }
}
