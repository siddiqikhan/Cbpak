import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

class GoogleMapsLocation {
  static const _channel = MethodChannel('cbpak/location');
  static final Map<String, Future<({double latitude, double longitude})?>>
  _coordinateCache = {};

  static Future<void> openPicker() =>
      _channel.invokeMethod<void>('openGoogleMapsPicker');

  static Future<void> openMapAt(double latitude, double longitude) =>
      _channel.invokeMethod<void>('openMapAt', {
        'latitude': latitude,
        'longitude': longitude,
      });

  static Future<void> openMapSearch(String query) =>
      _channel.invokeMethod<void>('openMapSearch', {'query': query});

  static Future<void> openWhatsApp(String phone) =>
      _channel.invokeMethod<void>('openWhatsApp', {'phone': phone});

  static Future<String?> pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  static ({double latitude, double longitude})? coordinatesFrom(String text) {
    final patterns = <RegExp>[
      RegExp(r'@(-?\d{1,2}\.\d+),\s*(-?\d{1,3}\.\d+)'),
      RegExp(
        r'[?&](?:q|query|destination)=(-?\d{1,2}\.\d+),\s*(-?\d{1,3}\.\d+)',
      ),
      RegExp(r'!3d(-?\d{1,2}\.\d+)!4d(-?\d{1,3}\.\d+)'),
      RegExp(r'(-?\d{1,2}\.\d+)\s*,\s*(-?\d{1,3}\.\d+)'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match == null) continue;
      final latitude = double.tryParse(match.group(1)!);
      final longitude = double.tryParse(match.group(2)!);
      if (latitude == null || longitude == null) continue;
      if (latitude.abs() > 90 || longitude.abs() > 180) continue;
      return (latitude: latitude, longitude: longitude);
    }
    return null;
  }

  static Future<({double latitude, double longitude})?> resolveCoordinates(
    String text,
  ) {
    final direct = coordinatesFrom(text);
    if (direct != null) return Future.value(direct);
    final uri = Uri.tryParse(text.trim());
    if (uri == null || !_isMapsShortLink(uri)) return Future.value(null);
    return _coordinateCache
        .putIfAbsent(text, () => _resolveShortLink(uri))
        .then((coordinates) {
          if (coordinates == null) _coordinateCache.remove(text);
          return coordinates;
        });
  }

  static Future<({double latitude, double longitude})?> _resolveShortLink(
    Uri uri,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    var current = uri;
    try {
      for (var redirects = 0; redirects <= 8; redirects++) {
        if (!_isGoogleMapsHost(current.host) || current.scheme != 'https') {
          return null;
        }
        final request = await client
            .getUrl(current)
            .timeout(const Duration(seconds: 8));
        request.followRedirects = false;
        request.headers.set(
          HttpHeaders.userAgentHeader,
          'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36',
        );
        final response = await request.close().timeout(
          const Duration(seconds: 8),
        );
        final fromUrl = coordinatesFrom(current.toString());
        if (fromUrl != null) {
          await response.drain<void>();
          return fromUrl;
        }
        if (response.isRedirect) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          await response.drain<void>();
          if (location == null) return null;
          current = current.resolve(location);
          continue;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          await response.drain<void>();
          return null;
        }
        final body = StringBuffer();
        var read = 0;
        await for (final chunk in response.transform(utf8.decoder)) {
          final remaining = 1024 * 1024 - read;
          if (remaining <= 0) break;
          final part = chunk.length <= remaining
              ? chunk
              : chunk.substring(0, remaining);
          body.write(part);
          read += part.length;
        }
        return coordinatesFrom(body.toString());
      }
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
    return null;
  }

  static bool _isMapsShortLink(Uri uri) =>
      uri.scheme == 'https' &&
      (uri.host == 'maps.app.goo.gl' ||
          (uri.host == 'goo.gl' && uri.path.startsWith('/maps')));

  static bool _isGoogleMapsHost(String host) =>
      host == 'maps.app.goo.gl' ||
      host == 'goo.gl' ||
      host == 'google.com' ||
      host.endsWith('.google.com') ||
      host == 'googleusercontent.com' ||
      host.endsWith('.googleusercontent.com');
}
