import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'location/google_maps_location.dart';

class FareRate {
  const FareRate({
    required this.vehicleLabel,
    required this.minimumFare,
    required this.kmPerLitre,
    required this.maintenancePerKm,
    required this.driverWagePerKm,
  });

  final String vehicleLabel;
  final int minimumFare;
  final double kmPerLitre;
  final double maintenancePerKm;
  final double driverWagePerKm;

  double get fuelPerKm => FareEstimator.petrolPricePerLitre / kmPerLitre;
  double get ratePerKm => fuelPerKm + maintenancePerKm + driverWagePerKm;
}

class FareEstimate {
  const FareEstimate({
    required this.directDistanceKm,
    required this.estimatedRoadDistanceKm,
    required this.fareBeforeRounding,
    required this.amount,
    required this.rate,
    required this.minimumApplied,
  });

  final double directDistanceKm;
  final double estimatedRoadDistanceKm;
  final double fareBeforeRounding;
  final int amount;
  final FareRate rate;
  final bool minimumApplied;

  String get calculationSummary => minimumApplied
      ? 'Minimum fare Rs ${rate.minimumFare} applied · rounded up to Rs 10: Rs $amount'
      : '${estimatedRoadDistanceKm.toStringAsFixed(2)} km × Rs ${rate.ratePerKm.toStringAsFixed(2)}/km = Rs ${fareBeforeRounding.toStringAsFixed(0)} · rounded up to Rs 10: Rs $amount';
}

class FareEstimator {
  static const petrolPricePerLitre = 337.91;
  static const _osrmHost = 'router.project-osrm.org';
  static final Map<String, Future<double?>> _roadDistanceCache = {};
  static Future<void> _requestQueue = Future<void>.value();
  static DateTime _lastRouteRequest = DateTime.fromMillisecondsSinceEpoch(0);

  static FareRate rateFor({
    required String category,
    String? service,
    String? vehicleType,
  }) {
    if (category == 'Courier Service') {
      return const FareRate(
        vehicleLabel: 'Bike courier',
        minimumFare: 150,
        kmPerLitre: 40,
        maintenancePerKm: 3,
        driverWagePerKm: 8,
      );
    }

    final vehicle = '${vehicleType ?? ''} ${service ?? ''}'.toLowerCase();
    if (vehicle.contains('luxury')) {
      return const FareRate(
        vehicleLabel: 'Luxury car',
        minimumFare: 500,
        kmPerLitre: 7,
        maintenancePerKm: 20,
        driverWagePerKm: 30,
      );
    }
    if (vehicle.contains('rental')) {
      return const FareRate(
        vehicleLabel: 'Rental car',
        minimumFare: 800,
        kmPerLitre: 8,
        maintenancePerKm: 20,
        driverWagePerKm: 25,
      );
    }
    if (vehicle.contains('with ac')) {
      return const FareRate(
        vehicleLabel: 'Car with AC',
        minimumFare: 300,
        kmPerLitre: 9,
        maintenancePerKm: 12,
        driverWagePerKm: 20,
      );
    }
    if (vehicle.contains('car')) {
      return const FareRate(
        vehicleLabel: 'Car without AC',
        minimumFare: 250,
        kmPerLitre: 12,
        maintenancePerKm: 10,
        driverWagePerKm: 18,
      );
    }
    if (vehicle.contains('rickshaw')) {
      return const FareRate(
        vehicleLabel: 'Rickshaw',
        minimumFare: 150,
        kmPerLitre: 20,
        maintenancePerKm: 7,
        driverWagePerKm: 12,
      );
    }
    return const FareRate(
      vehicleLabel: 'Bike',
      minimumFare: 100,
      kmPerLitre: 40,
      maintenancePerKm: 4,
      driverWagePerKm: 10,
    );
  }

  static Future<FareEstimate?> estimateResolved(
    String? pickup,
    String? destination, {
    required String category,
    String? service,
    String? vehicleType,
  }) async {
    if (pickup == null || destination == null) return null;
    final from = await GoogleMapsLocation.resolveCoordinates(pickup);
    final to = await GoogleMapsLocation.resolveCoordinates(destination);
    if (from == null || to == null) return null;
    final rate = rateFor(
      category: category,
      service: service,
      vehicleType: vehicleType,
    );
    final distances = _directDistance(from, to);
    final roadDistance = await _roadDistance(from, to);
    if (roadDistance == null) return null;
    final rawFare = roadDistance * rate.ratePerKm;
    final fareBeforeRounding = math.max(rate.minimumFare, rawFare).toDouble();
    final amount = (fareBeforeRounding / 10).ceil() * 10;
    return FareEstimate(
      directDistanceKm: distances,
      estimatedRoadDistanceKm: roadDistance,
      fareBeforeRounding: fareBeforeRounding,
      amount: amount,
      rate: rate,
      minimumApplied: rawFare < rate.minimumFare,
    );
  }

  static Future<double?> _roadDistance(
    ({double latitude, double longitude}) from,
    ({double latitude, double longitude}) to,
  ) {
    final key =
        '${from.latitude},${from.longitude};${to.latitude},${to.longitude}';
    final cached = _roadDistanceCache.putIfAbsent(
      key,
      () => _fetchRoadDistance(from, to),
    );
    return cached.then((distance) {
      if (distance == null && identical(_roadDistanceCache[key], cached)) {
        _roadDistanceCache.remove(key);
      }
      return distance;
    });
  }

  static Future<double?> _fetchRoadDistance(
    ({double latitude, double longitude}) from,
    ({double latitude, double longitude}) to,
  ) async {
    final previousRequest = _requestQueue;
    final nextRequest = Completer<void>();
    _requestQueue = nextRequest.future;
    await previousRequest;
    final elapsed = DateTime.now().difference(_lastRouteRequest);
    if (elapsed < const Duration(seconds: 1)) {
      await Future<void>.delayed(const Duration(seconds: 1) - elapsed);
    }
    _lastRouteRequest = DateTime.now();
    nextRequest.complete();

    final coordinates =
        '${from.longitude},${from.latitude};${to.longitude},${to.latitude}';
    final uri = Uri.https(_osrmHost, '/route/v1/driving/$coordinates', {
      'overview': 'false',
      'steps': 'false',
    });
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 12));
      request.headers.set(HttpHeaders.userAgentHeader, 'CBPAK Android app');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        return null;
      }
      final decoded = jsonDecode(await response.transform(utf8.decoder).join());
      if (decoded is! Map<String, dynamic> || decoded['code'] != 'Ok') {
        return null;
      }
      final routes = decoded['routes'];
      if (routes is! List || routes.isEmpty || routes.first is! Map) {
        return null;
      }
      final meters = (routes.first as Map)['distance'];
      if (meters is! num || meters <= 0) return null;
      return meters / 1000;
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static double _directDistance(
    ({double latitude, double longitude}) from,
    ({double latitude, double longitude}) to,
  ) {
    const earthRadiusKm = 6371.0;
    final lat1 = _radians(from.latitude);
    final lat2 = _radians(to.latitude);
    final deltaLat = _radians(to.latitude - from.latitude);
    final deltaLng = _radians(to.longitude - from.longitude);
    final a =
        math.pow(math.sin(deltaLat / 2), 2) +
        math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(deltaLng / 2), 2);
    return 2 * earthRadiusKm * math.asin(math.sqrt(a));
  }

  static double _radians(double degrees) => degrees * math.pi / 180;
}
