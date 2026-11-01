import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../admin_dashboard.dart';
import '../driver_dashboard.dart';
import '../fare_estimator.dart';
import '../customer_ride_details.dart';
import '../logistics_options.dart';
import '../location/current_location.dart';
import '../location/google_maps_location.dart';
import '../request_repository.dart';
import '../theme/app_colors.dart';

enum FareMode { bargaining, fixed }

class HomeDashboard extends StatefulWidget {
  const HomeDashboard({required this.user, super.key});
  final User user;

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  final _requestRepo = RequestRepository();
  int _tab = 0;
  FareMode _fareMode = FareMode.fixed;
  String _service = 'City Rides';
  String _rideType = 'Car';
  String _vehicle = 'Normal (without AC)';
  final _pickupController = TextEditingController();
  final _destinationController = TextEditingController();
  double? _pickupLat;
  double? _pickupLng;
  bool _gettingLocation = false;
  bool _submitting = false;
  String? _activeRequestId;
  final Map<String, int> _declinedCounts = {};
  final Set<String> _cancellingRequests = {};

  String get _name {
    final name = widget.user.displayName?.trim();
    if (name != null && name.isNotEmpty) return name.split(' ').first;
    final email = widget.user.email;
    return email != null && email.contains('@')
        ? email.split('@').first
        : 'there';
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _gettingLocation = true);
    try {
      final location = await CurrentLocation.get();
      if (!mounted) return;
      _pickupLat = location.latitude;
      _pickupLng = location.longitude;
      _pickupController.text =
          'Current location (${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)})';
      setState(() {});
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message ?? 'Could not get your location.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _gettingLocation = false);
    }
  }

  Future<void> _openGoogleMaps() async {
    try {
      await GoogleMapsLocation.openPicker();
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? 'Could not open Google Maps.')),
      );
    }
  }

  Future<void> _pasteDestination() async {
    final text = await GoogleMapsLocation.pasteFromClipboard();
    if (!mounted) return;
    if (text == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copy a location or Maps link first.')),
      );
      return;
    }
    final coordinates = await GoogleMapsLocation.resolveCoordinates(text);
    _destinationController.text = coordinates == null
        ? text
        : 'Selected location (${coordinates.latitude.toStringAsFixed(6)}, ${coordinates.longitude.toStringAsFixed(6)})';
    setState(() {});
  }

  Future<void> _continueBooking() async {
    FocusScope.of(context).unfocus();
    if (_pickupController.text.trim().isEmpty ||
        _destinationController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter your pickup and destination first.'),
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      var destination = _destinationController.text.trim();
      final destinationCoordinates =
          await GoogleMapsLocation.resolveCoordinates(destination);
      if (destinationCoordinates != null) {
        destination =
            'Selected location (${destinationCoordinates.latitude.toStringAsFixed(6)}, ${destinationCoordinates.longitude.toStringAsFixed(6)})';
        _destinationController.text = destination;
      }
      final requestId = await _requestRepo.createRequest({
        'category': 'City Rides',
        'service': _rideType,
        'vehicleType': _vehicle.isNotEmpty ? _vehicle : _rideType,
        'pickup': _pickupController.text.trim(),
        if (_pickupLat != null) 'pickupLat': _pickupLat,
        if (_pickupLng != null) 'pickupLng': _pickupLng,
        'destination': destination,
        'fareMode': _fareMode == FareMode.bargaining ? 'bargaining' : 'fixed',
        'details': '',
        'priceFlow': 'fare_option',
      });
      if (!mounted) return;
      setState(() => _activeRequestId = requestId);
    } on FirebaseException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.code == 'permission-denied'
                ? 'Firestore rules blocked this ride request.'
                : error.message ?? 'Could not submit the ride request.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _previewRow(IconData icon, String label, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: AppColors.blue, size: 19),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Color(0xFF8792A3), fontSize: 11),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: const TextStyle(
                color: AppColors.navy,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    await GoogleSignIn.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_bookingPage(), _profilePage()];
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: SafeArea(
        child: IndexedStack(index: _tab, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFE9F0FC),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.near_me_outlined),
            selectedIcon: Icon(Icons.near_me_rounded),
            label: 'Book a ride',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _bookingPage() {
    final activeId = _activeRequestId;
    if (activeId != null) {
      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('requests')
            .doc(activeId)
            .snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data();
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return _liveRidePage(activeId, data);
        },
      );
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _requestRepo.watchCustomerRequests(),
      builder: (context, snapshot) {
        final requests = [...?snapshot.data?.docs];
        requests.sort((a, b) {
          final aTime = a.data()['createdAt'] as Timestamp?;
          final bTime = b.data()['createdAt'] as Timestamp?;
          return (bTime?.millisecondsSinceEpoch ?? 0).compareTo(
            aTime?.millisecondsSinceEpoch ?? 0,
          );
        });
        for (final request in requests) {
          final status = request.data()['status'];
          if (status == 'open' || status == 'accepted') {
            return _liveRidePage(request.id, request.data());
          }
        }
        return _bookingFormPage();
      },
    );
  }

  Widget _liveRidePage(String requestId, Map<String, dynamic> data) {
    _notifyCustomerOfDriverDecline(requestId, data);
    final status = data['status'] as String? ?? 'open';
    final terminal = status == 'completed' || status == 'cancelled';
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                switch (status) {
                  'open' => 'Waiting for a driver',
                  'accepted' => 'Driver accepted your ride',
                  'completed' => 'Ride completed',
                  'cancelled' => 'Ride cancelled',
                  _ => 'Ride status',
                },
                style: const TextStyle(
                  color: AppColors.blue,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                status == 'open'
                    ? 'Your request is visible to approved drivers. This page updates when a driver accepts.'
                    : 'Your latest ride details and status are shown here.',
                style: const TextStyle(
                  color: Color(0xFF738097),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              _previewRow(
                Icons.directions_car_outlined,
                'Ride',
                '${data['service'] ?? data['category'] ?? ''} · ${data['vehicleType'] ?? ''}',
              ),
              const SizedBox(height: 12),
              _liveRideLocation('Pickup', data['pickup']),
              const SizedBox(height: 12),
              _liveRideLocation('Destination', data['destination']),
              const SizedBox(height: 12),
              if (data['category'] == 'City Rides' ||
                  data['category'] == 'Courier Service') ...[
                if (data['category'] == 'City Rides')
                  _previewRow(
                    Icons.payments_outlined,
                    'Fare style',
                    data['fareMode'] == 'fixed' ? 'Fixed fare' : 'Bargaining',
                  ),
                const SizedBox(height: 8),
                _fareEstimateRow(
                  data['pickup'],
                  data['destination'],
                  category: data['category'] as String? ?? 'City Rides',
                  service: data['service'] as String?,
                  vehicleType: data['vehicleType'] as String?,
                ),
              ],
            ],
          ),
        ),
        if (status == 'accepted' || status == 'completed') ...[
          const SizedBox(height: 18),
          const Text(
            'Driver',
            style: TextStyle(
              color: AppColors.navy,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          _liveRideDriver(requestId),
        ],
        if (status == 'open') ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _cancellingRequests.contains(requestId)
                ? null
                : () => _confirmCancelRide(requestId),
            icon: _cancellingRequests.contains(requestId)
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.close_rounded),
            label: const Text('Cancel ride request'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: const Color(0xFFB84444),
            ),
          ),
        ],
        if (terminal) ...[
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => setState(() => _activeRequestId = null),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Book another ride'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
          ),
        ],
      ],
    );
  }

  void _notifyCustomerOfDriverDecline(
    String requestId,
    Map<String, dynamic> data,
  ) {
    final declinedBy = data['declinedBy'] as List<dynamic>? ?? const [];
    final count = declinedBy.length;
    final previousCount = _declinedCounts.putIfAbsent(requestId, () => count);
    if (count <= previousCount) return;
    _declinedCounts[requestId] = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Driver nahi le saka—doosra driver dhoond rahe hain'),
            duration: Duration(seconds: 3),
          ),
        );
    });
  }

  Future<void> _confirmCancelRide(String requestId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this ride request?'),
        content: const Text(
          'Drivers will no longer be able to accept this request.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep waiting'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancel request'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _cancellingRequests.add(requestId));
    try {
      await _requestRepo.cancelCustomerRide(requestId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ride request cancelled.')),
        );
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.code == 'permission-denied'
                  ? 'Firebase rules blocked cancellation. The ride is still active.'
                  : error.message ?? 'Could not cancel this ride.',
            ),
          ),
        );
      }
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _cancellingRequests.remove(requestId));
    }
  }

  Widget _liveRideLocation(String title, Object? value) {
    if (value == null || '$value'.trim().isEmpty)
      return const SizedBox.shrink();
    final coordinates = GoogleMapsLocation.coordinatesFrom('$value');
    final coordinateText = coordinates == null
        ? null
        : '${coordinates.latitude.toStringAsFixed(6)}, ${coordinates.longitude.toStringAsFixed(6)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(color: Color(0xFF8792A3), fontSize: 11),
        ),
        const SizedBox(height: 3),
        SelectableText(
          '$value',
          style: const TextStyle(
            color: AppColors.navy,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        if (coordinateText != null)
          Text(
            coordinateText,
            style: const TextStyle(color: Color(0xFF657188), fontSize: 12),
          ),
        Wrap(
          spacing: 4,
          children: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: coordinateText ?? '$value'),
                );
                if (mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        coordinateText == null
                            ? '$title copied.'
                            : 'Coordinates copied.',
                      ),
                    ),
                  );
              },
              icon: const Icon(Icons.copy_rounded, size: 17),
              label: Text(
                coordinateText == null ? 'Copy $title' : 'Copy coordinates',
              ),
            ),
            TextButton.icon(
              onPressed: () async {
                try {
                  if (coordinates != null) {
                    await GoogleMapsLocation.openMapAt(
                      coordinates.latitude,
                      coordinates.longitude,
                    );
                  } else {
                    await GoogleMapsLocation.openMapSearch('$value');
                  }
                } on PlatformException catch (error) {
                  if (mounted)
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(error.message ?? 'Could not open Maps.'),
                      ),
                    );
                }
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 17),
              label: const Text('Open in Maps'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _fareEstimateRow(
    Object? pickup,
    Object? destination, {
    required String category,
    String? service,
    String? vehicleType,
  }) {
    final rate = FareEstimator.rateFor(
      category: category,
      service: service,
      vehicleType: vehicleType,
    );
    return FutureBuilder<FareEstimate?>(
      future: FareEstimator.estimateResolved(
        '$pickup',
        '$destination',
        category: category,
        service: service,
        vehicleType: vehicleType,
      ),
      builder: (context, snapshot) {
        final estimate = snapshot.data;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF4FE),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                snapshot.connectionState == ConnectionState.waiting
                    ? 'Calculating ${rate.vehicleLabel.toLowerCase()} fare…'
                    : estimate == null
                    ? '${rate.vehicleLabel}: Rs ${rate.ratePerKm.toStringAsFixed(1)}/km · minimum Rs ${rate.minimumFare}'
                    : 'Estimated total: Rs ${estimate.amount}',
                style: const TextStyle(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                estimate == null
                    ? 'Enter or paste a map pin to calculate distance and total.'
                    : estimate.calculationSummary,
                style: const TextStyle(
                  color: Color(0xFF657188),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Petrol Rs ${FareEstimator.petrolPricePerLitre.toStringAsFixed(2)}/L · fuel Rs ${rate.fuelPerKm.toStringAsFixed(1)}/km · maintenance Rs ${rate.maintenancePerKm.toStringAsFixed(0)}/km · driver wages Rs ${rate.driverWagePerKm.toStringAsFixed(0)}/km',
                style: const TextStyle(
                  color: Color(0xFF738097),
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
              const Text(
                'Routing by OSRM · © OpenStreetMap contributors (ODbL). Traffic is not included.',
                style: TextStyle(color: Color(0xFF8792A3), fontSize: 10),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _liveRideDriver(String requestId) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _requestRepo.watchRideContact(requestId),
        builder: (context, snapshot) {
          final driver = snapshot.data?.data();
          if (snapshot.hasError)
            return const Text('Driver details are unavailable.');
          if (snapshot.connectionState == ConnectionState.waiting)
            return const LinearProgressIndicator();
          if (driver == null) return const Text('Driver details are loading.');
          final phone = driver['driverPhone']?.toString() ?? '';
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _previewRow(
                  Icons.person_outline_rounded,
                  'Name',
                  driver['driverName']?.toString() ?? '',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _previewRow(Icons.phone_outlined, 'Phone', phone),
                    ),
                    IconButton(
                      tooltip: 'Open WhatsApp',
                      onPressed: phone.isEmpty
                          ? null
                          : () async {
                              try {
                                await GoogleMapsLocation.openWhatsApp(phone);
                              } on PlatformException catch (error) {
                                if (mounted)
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        error.message ??
                                            'Could not open WhatsApp.',
                                      ),
                                    ),
                                  );
                              }
                            },
                      icon: const Icon(
                        Icons.chat_rounded,
                        color: Color(0xFF25D366),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _previewRow(
                  Icons.directions_car_outlined,
                  'Vehicle',
                  driver['vehicleType']?.toString() ?? '',
                ),
              ],
            ),
          );
        },
      );

  Widget _bookingFormPage() => ListView(
    padding: EdgeInsets.zero,
    children: [
      _header(),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Book your ride from here',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Choose your ride, enter the route and send the request on this screen.',
              style: TextStyle(color: Color(0xFF8792A3), fontSize: 12),
            ),
            const SizedBox(height: 16),
            _cityRidePicker(),
            if (_rideType == 'Car') ...[
              const SizedBox(height: 14),
              const Text(
                'Choose car type',
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              _vehiclePicker(),
            ],
            const SizedBox(height: 14),
            _routeCard(),
            if (_service == 'City Rides') ...[
              const SizedBox(height: 10),
              _fareEstimateRow(
                _pickupController.text,
                _destinationController.text,
                category: 'City Rides',
                service: _rideType,
                vehicleType: _vehicle,
              ),
            ],
            const SizedBox(height: 18),
            const Text(
              'Choose fare style',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            _fareOption(
              mode: FareMode.bargaining,
              title: 'Bargaining',
              description: 'Use the app estimate as a guide and agree.',
              icon: Icons.handshake_outlined,
              tag: 'POPULAR',
            ),
            const SizedBox(height: 9),
            _fareOption(
              mode: FareMode.fixed,
              title: 'Fixed fare',
              description: 'Automatic estimate based on vehicle and route.',
              icon: Icons.lock_outline_rounded,
              tag: 'NO BARGAINING',
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _submitting ? null : _continueBooking,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.near_me_rounded),
                label: Text(_submitting ? 'Sending request…' : 'Request ride'),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 26),
            const Text(
              'Other services',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            _categoryTile(
              'Moving & Logistics',
              'Choose a vehicle for your move or delivery',
              Icons.local_shipping_rounded,
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MovingLogisticsPage(),
                  ),
                );
              },
            ),
            const SizedBox(height: 11),
            _categoryTile(
              'Courier Service',
              'Send a parcel or document',
              Icons.inventory_2_outlined,
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ServiceBookingPage(
                      category: 'Courier Service',
                      service: 'Courier Service',
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    ],
  );

  Widget _categoryTile(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap,
  ) => Card(
    color: Colors.white,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(17),
      side: const BorderSide(color: Color(0xFFEDF0F4)),
    ),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFEAF0FA),
        child: Icon(icon, color: AppColors.blue),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: AppColors.navy,
          fontWeight: FontWeight.w800,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Color(0xFF8792A3), fontSize: 11),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: Color(0xFF8792A3),
      ),
      onTap: onTap,
    ),
  );
  Widget _header() => Container(
    padding: const EdgeInsets.fromLTRB(22, 15, 22, 23),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFF142944), Color(0xFF244A75)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.route_rounded, color: Colors.white),
            ),
            const SizedBox(width: 10),
            const Text(
              'CBPAK',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Profile',
              onPressed: () => setState(() => _tab = 1),
              icon: CircleAvatar(
                radius: 17,
                backgroundColor: Colors.white,
                child: Text(
                  _name[0].toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          'Where to, $_name?',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 23,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'Your journey, made simpler.',
          style: TextStyle(color: Color(0xFFD3DEEB), fontSize: 13),
        ),
      ],
    ),
  );

  Widget _servicePicker() {
    const choices = <(String, IconData)>[
      ('City Rides', Icons.local_taxi_rounded),
      ('Moving & Logistics', Icons.local_shipping_rounded),
      ('Courier Service', Icons.inventory_2_outlined),
    ];
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.6,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: choices.map((choice) {
        final selected = _service == choice.$1;
        return InkWell(
          onTap: () => setState(() {
            _service = choice.$1;
            if (_service == 'City Rides') {
              _rideType = 'Car';
              _vehicle = 'Normal (without AC)';
            } else if (_service == 'Moving & Logistics') {
              _vehicle = 'Suzuki Ravi / Pickup';
            } else {
              _vehicle = '';
            }
          }),
          borderRadius: BorderRadius.circular(15),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFFEEF4FE) : Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: selected ? AppColors.blue : const Color(0xFFE7EBF1),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  choice.$2,
                  size: 19,
                  color: selected ? AppColors.blue : const Color(0xFF738097),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    choice.$1,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? AppColors.navy
                          : const Color(0xFF56647A),
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
                if (selected)
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: AppColors.blue,
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _cityRidePicker() {
    const choices = <(String, IconData)>[
      ('Car', Icons.directions_car_rounded),
      ('Bike', Icons.two_wheeler_rounded),
      ('Rickshaw', Icons.electric_rickshaw_rounded),
    ];
    return GridView.count(
      crossAxisCount: 3,
      mainAxisSpacing: 9,
      crossAxisSpacing: 9,
      childAspectRatio: 1.35,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: choices.map((choice) {
        final selected = _rideType == choice.$1;
        return InkWell(
          onTap: () => setState(() {
            _rideType = choice.$1;
            _vehicle = choice.$1 == 'Car' ? 'Normal (without AC)' : '';
          }),
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFFEEF4FE) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? AppColors.blue : const Color(0xFFE7EBF1),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  choice.$2,
                  color: selected ? AppColors.blue : const Color(0xFF738097),
                  size: 22,
                ),
                const SizedBox(height: 5),
                Text(
                  choice.$1,
                  maxLines: 1,
                  style: TextStyle(
                    color: selected ? AppColors.navy : const Color(0xFF56647A),
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  List<String> get _vehicleOptions {
    if (_service == 'City Rides' && _rideType == 'Car') {
      return const ['Normal (without AC)', 'With AC', 'Luxury Car', 'Rental'];
    }
    if (_service == 'Moving & Logistics') {
      return const [
        'Suzuki Ravi / Pickup',
        'Mazda Mini Truck',
        'Shehzore',
        'Mazda Truck',
        'Hino Truck',
        'Suzuki Bolan',
        'Toyota Hiace',
        'Hyundai Shehzore',
        'Kia K2700',
        'Isuzu Truck',
        'JAC Truck',
        'Container Truck',
        'Flatbed Truck',
        'Closed Body Truck',
        'Open Body Truck',
      ];
    }
    return const [];
  }

  Widget _vehiclePicker() => GridView.builder(
    itemCount: _vehicleOptions.length,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      mainAxisSpacing: 9,
      crossAxisSpacing: 9,
      childAspectRatio: 2.25,
    ),
    itemBuilder: (context, index) {
      final vehicle = _vehicleOptions[index];
      final selected = _vehicle == vehicle;
      return InkWell(
        onTap: () => setState(() => _vehicle = vehicle),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEEF4FE) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.blue : const Color(0xFFE7EBF1),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                _service == 'City Rides'
                    ? Icons.directions_car_outlined
                    : Icons.local_shipping_outlined,
                size: 17,
                color: selected ? AppColors.blue : const Color(0xFF738097),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  vehicle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? AppColors.navy : const Color(0xFF56647A),
                    fontSize: 10,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  size: 15,
                  color: AppColors.blue,
                ),
            ],
          ),
        ),
      );
    },
  );

  Widget _ownerContactCard() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF7EB),
      borderRadius: BorderRadius.circular(17),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.support_agent_rounded, color: Color(0xFFCA8326), size: 21),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'The owner will contact you to discuss your request and agree on the price.',
            style: TextStyle(
              color: Color(0xFF77541F),
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ),
      ],
    ),
  );
  Widget _routeCard() => Container(
    padding: const EdgeInsets.fromLTRB(15, 8, 15, 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(19),
      border: Border.all(color: const Color(0xFFEDF0F4)),
    ),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _pickupController,
                textInputAction: TextInputAction.next,
                onChanged: (_) {
                  _pickupLat = null;
                  _pickupLng = null;
                  setState(() {});
                },
                decoration: const InputDecoration(
                  filled: false,
                  border: InputBorder.none,
                  hintText: 'Pickup location',
                  prefixIcon: Icon(
                    Icons.trip_origin_rounded,
                    size: 19,
                    color: Color(0xFF2E6BCE),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Use current location',
              onPressed: _gettingLocation ? null : _useCurrentLocation,
              icon: _gettingLocation
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location, color: AppColors.blue),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(left: 18),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              height: 16,
              child: VerticalDivider(
                width: 1,
                thickness: 1,
                color: Color(0xFFDCE2EB),
              ),
            ),
          ),
        ),
        TextField(
          controller: _destinationController,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            filled: false,
            border: InputBorder.none,
            hintText: 'Where are you going?',
            prefixIcon: Icon(
              Icons.location_on_outlined,
              size: 20,
              color: Color(0xFFEA7256),
            ),
          ),
          onSubmitted: (_) => _continueBooking(),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                onPressed: _openGoogleMaps,
                icon: const Icon(Icons.map_outlined, size: 17),
                label: const Text('Open Google Maps'),
              ),
              TextButton.icon(
                onPressed: _pasteDestination,
                icon: const Icon(Icons.content_paste_rounded, size: 17),
                label: const Text('Paste location'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _fareOption({
    required FareMode mode,
    required String title,
    required String description,
    required IconData icon,
    required String tag,
  }) {
    final selected = _fareMode == mode;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _fareMode = mode),
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEEF4FE) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? AppColors.blue : const Color(0xFFE7EBF1),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: selected ? Colors.white : const Color(0xFFF4F6F9),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: selected ? AppColors.blue : const Color(0xFF738097),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: AppColors.navy,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (selected)
                          const Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.blue,
                            size: 17,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(
                        color: Color(0xFF738097),
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                tag,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: selected ? AppColors.blue : const Color(0xFF8792A3),
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tripsPage() => _plainPage(
    icon: Icons.receipt_long_rounded,
    title: 'My rides',
    subtitle: 'Your sent requests and their status appear here.',
    child: StreamBuilder(
      stream: _requestRepo.watchCustomerRequests(),
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return const Text(
            'Requests will appear here after Firestore is set up.',
          );
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());
        final requests = [...?snapshot.data?.docs];
        requests.sort((a, b) {
          final aTime = a.data()['createdAt'] as Timestamp?;
          final bTime = b.data()['createdAt'] as Timestamp?;
          return (bTime?.millisecondsSinceEpoch ?? 0).compareTo(
            aTime?.millisecondsSinceEpoch ?? 0,
          );
        });
        if (requests.isEmpty)
          return const Column(
            children: [
              Icon(
                Icons.directions_car_filled_outlined,
                color: AppColors.blue,
                size: 38,
              ),
              SizedBox(height: 12),
              Text(
                'No requests yet',
                style: TextStyle(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 5),
              Text(
                'Create a ride, courier or moving request and it will show here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF8792A3), fontSize: 12),
              ),
            ],
          );
        return Column(
          children: [
            for (final request in requests)
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CustomerRideDetailsPage(request: request),
                  ),
                ),
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F8FA),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.data()['vehicleType'] as String? ??
                            request.data()['service'] as String? ??
                            request.data()['category'] as String? ??
                            'Request',
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${request.data()['pickup'] ?? ''} → ${request.data()['destination'] ?? ''}',
                        style: const TextStyle(
                          color: Color(0xFF657188),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Status: ${request.data()['status'] ?? 'open'}   ·   Tap for details',
                        style: const TextStyle(
                          color: AppColors.blue,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ),
    action: FilledButton(
      onPressed: () => setState(() => _tab = 0),
      child: const Text('Plan a ride'),
    ),
  );

  Widget _profilePage() => _plainPage(
    icon: Icons.person_rounded,
    title: 'Your profile',
    subtitle: widget.user.displayName ?? widget.user.email ?? 'CBPAK account',
    child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_user_outlined, color: AppColors.blue),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Signed in securely with Firebase',
              style: TextStyle(
                color: AppColors.navy,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Icon(Icons.check_circle, color: Colors.green.shade600),
        ],
      ),
    ),
    action: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DriverDashboardPage(user: widget.user),
            ),
          ),
          icon: const Icon(Icons.local_shipping_outlined),
          label: const Text('Driver mode'),
        ),
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _requestRepo.watchAdminAccess(),
          builder: (context, snapshot) {
            if (snapshot.data?.exists != true) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FilledButton.tonalIcon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminDashboardPage()),
                ),
                icon: const Icon(Icons.admin_panel_settings_outlined),
                label: const Text('Admin dashboard'),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _signOut,
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Sign out'),
        ),
      ],
    ),
  );

  Widget _plainPage({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
    Widget? action,
  }) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
    children: [
      Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF0FA),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppColors.blue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF8792A3),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 22),
      child,
      if (action != null) ...[const SizedBox(height: 16), action],
    ],
  );
}

class CityRideTypePage extends StatelessWidget {
  const CityRideTypePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF4F6F9),
    appBar: AppBar(
      title: const Text('City Rides'),
      backgroundColor: const Color(0xFFF4F6F9),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Choose your ride',
          style: TextStyle(
            color: AppColors.navy,
            fontSize: 21,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Each option opens its own booking page.',
          style: TextStyle(color: Color(0xFF8792A3), fontSize: 12),
        ),
        const SizedBox(height: 18),
        _rideCard(
          context,
          'Car',
          'Choose comfort and fare style',
          Icons.directions_car_rounded,
        ),
        const SizedBox(height: 11),
        _rideCard(
          context,
          'Bike',
          'A quick ride around town',
          Icons.two_wheeler_rounded,
        ),
        const SizedBox(height: 11),
        _rideCard(
          context,
          'Rickshaw',
          'A convenient city ride',
          Icons.electric_rickshaw_rounded,
        ),
      ],
    ),
  );

  Widget _rideCard(
    BuildContext context,
    String name,
    String caption,
    IconData icon,
  ) => Card(
    color: Colors.white,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(17),
      side: const BorderSide(color: Color(0xFFEDF0F4)),
    ),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFEAF0FA),
        child: Icon(icon, color: AppColors.blue),
      ),
      title: Text(
        name,
        style: const TextStyle(
          color: AppColors.navy,
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Text(
        caption,
        style: const TextStyle(color: Color(0xFF8792A3), fontSize: 11),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ServiceBookingPage(category: 'City Rides', service: name),
        ),
      ),
    ),
  );
}

class MovingLogisticsPage extends StatefulWidget {
  const MovingLogisticsPage({super.key});

  static const vehicleOptions = LogisticsOptions.vehicles;

  @override
  State<MovingLogisticsPage> createState() => _MovingLogisticsPageState();
}

class _MovingLogisticsPageState extends State<MovingLogisticsPage> {
  final _requestRepo = RequestRepository();
  final _pickup = TextEditingController();
  final _destination = TextEditingController();
  final _cargo = TextEditingController();
  String _vehicle = 'Suzuki Ravi / Pickup';
  String _pickupTime = 'Up to 1 hour';
  String _loader = 'One loader';
  String _payment = 'Cash';
  bool _closedBody = false;
  bool _passenger = false;
  bool _schedule = false;
  DateTime? _scheduledAt;
  double? _pickupLat;
  double? _pickupLng;
  bool _gettingLocation = false;

  @override
  void dispose() {
    _pickup.dispose();
    _destination.dispose();
    _cargo.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _gettingLocation = true);
    try {
      final location = await CurrentLocation.get();
      if (!mounted) return;
      _pickupLat = location.latitude;
      _pickupLng = location.longitude;
      _pickup.text =
          'Current location (${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)})';
      setState(() {});
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message ?? 'Could not get your location.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _gettingLocation = false);
    }
  }

  Future<void> _openGoogleMaps() async {
    try {
      await GoogleMapsLocation.openPicker();
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? 'Could not open Google Maps.')),
      );
    }
  }

  Future<void> _pasteDestination() async {
    final text = await GoogleMapsLocation.pasteFromClipboard();
    if (!mounted) return;
    if (text == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copy a location or Maps link first.')),
      );
      return;
    }
    final coordinates = GoogleMapsLocation.coordinatesFrom(text);
    setState(() {
      _destination.text = coordinates == null
          ? text
          : 'Selected location (${coordinates.latitude.toStringAsFixed(6)}, ${coordinates.longitude.toStringAsFixed(6)})';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          coordinates == null
              ? 'Location link pasted. Tap it to review or edit.'
              : 'Location and coordinates added.',
        ),
      ),
    );
  }

  Future<void> _chooseVehicle() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(22, 8, 22, 12),
                child: Text(
                  'Select vehicle size and type',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: MovingLogisticsPage.vehicleOptions.length,
                  itemBuilder: (context, index) {
                    final option = MovingLogisticsPage.vehicleOptions[index];
                    return ListTile(
                      leading: Icon(
                        option.toLowerCase().contains('rickshaw')
                            ? Icons.electric_rickshaw_rounded
                            : Icons.local_shipping_outlined,
                        color: AppColors.blue,
                      ),
                      title: Text(
                        option,
                        style: const TextStyle(color: AppColors.navy),
                      ),
                      trailing: option == _vehicle
                          ? const Icon(
                              Icons.check_circle,
                              color: AppColors.blue,
                            )
                          : null,
                      onTap: () => Navigator.pop(context, option),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) setState(() => _vehicle = selected);
  }

  Future<void> _schedulePickup() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 180)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null || !mounted) return;
    setState(() {
      _schedule = true;
      _pickupTime = 'Scheduled delivery';
      _scheduledAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _createRequest() async {
    FocusScope.of(context).unfocus();
    if (_pickup.text.trim().isEmpty || _destination.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add pickup and destination first.'),
        ),
      );
      return;
    }
    final scheduleLabel = _scheduledAt == null
        ? _pickupTime
        : '${_scheduledAt!.day}/${_scheduledAt!.month} at ${TimeOfDay.fromDateTime(_scheduledAt!).format(context)}';
    try {
      await _requestRepo.createRequest({
        'category': 'Moving & Logistics',
        'service': 'Moving & Logistics',
        'vehicleType': _vehicle,
        'pickup': _pickup.text.trim(),
        if (_pickupLat != null) 'pickupLat': _pickupLat,
        if (_pickupLng != null) 'pickupLng': _pickupLng,
        'destination': _destination.text.trim(),
        'pickupTime': scheduleLabel,
        'loader': _loader,
        'paymentMethod': _payment,
        'closedBodyRequired': _closedBody,
        'passengerRide': _passenger,
        'cargoDescription': _cargo.text.trim(),
        'priceFlow': 'customer_owner_discussion',
      });
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Request submitted'),
          content: const Text(
            'Your request is saved. Approved vehicle owners can review it and discuss the final details and price with you.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } on FirebaseException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.code == 'permission-denied'
                ? 'Firestore security rules need to be connected first.'
                : error.message ?? 'Could not submit the request.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF4F6F9),
    appBar: AppBar(
      title: const Text('Moving & Logistics'),
      backgroundColor: const Color(0xFFF4F6F9),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 110),
      children: [
        const Text(
          'Plan your move',
          style: TextStyle(
            color: AppColors.navy,
            fontSize: 23,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'Choose a vehicle and share the job details with its owner.',
          style: TextStyle(color: Color(0xFF8792A3)),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _formField(
                'Pickup location',
                _pickup,
                Icons.trip_origin_rounded,
                onChanged: (_) {
                  _pickupLat = null;
                  _pickupLng = null;
                },
              ),
            ),
            IconButton(
              onPressed: _gettingLocation ? null : _useCurrentLocation,
              tooltip: 'Use current location',
              icon: _gettingLocation
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location, color: AppColors.blue),
            ),
          ],
        ),
        const SizedBox(height: 11),
        _formField(
          'Destination (type or paste location)',
          _destination,
          Icons.location_on_outlined,
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: _openGoogleMaps,
              icon: const Icon(Icons.map_outlined),
              label: const Text('Open Google Maps'),
            ),
            TextButton.icon(
              onPressed: _pasteDestination,
              icon: const Icon(Icons.content_paste_rounded),
              label: const Text('Paste location'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _sectionTitle('Pickup time'),
        const SizedBox(height: 9),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _choice(
              '10–20 min',
              _pickupTime == '10–20 min',
              () => setState(() {
                _pickupTime = '10–20 min';
                _schedule = false;
                _scheduledAt = null;
              }),
            ),
            _choice(
              'Up to 1 hour',
              _pickupTime == 'Up to 1 hour',
              () => setState(() {
                _pickupTime = 'Up to 1 hour';
                _schedule = false;
                _scheduledAt = null;
              }),
            ),
            _choice('Schedule delivery', _schedule, _schedulePickup),
          ],
        ),
        if (_scheduledAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Scheduled: ${_scheduledAt!.day}/${_scheduledAt!.month} at ${TimeOfDay.fromDateTime(_scheduledAt!).format(context)}',
              style: const TextStyle(
                color: AppColors.blue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        const SizedBox(height: 20),
        _sectionTitle('Vehicle size and type'),
        const SizedBox(height: 8),
        InkWell(
          onTap: _chooseVehicle,
          borderRadius: BorderRadius.circular(15),
          child: _panel(
            Row(
              children: [
                const Icon(
                  Icons.local_shipping_outlined,
                  color: AppColors.blue,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Selected vehicle',
                        style: TextStyle(
                          color: Color(0xFF8792A3),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _vehicle,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.expand_more_rounded, color: Color(0xFF8792A3)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        _formField(
          'Cargo description (optional)',
          _cargo,
          Icons.inventory_2_outlined,
          maxLines: 2,
        ),
        const SizedBox(height: 20),
        _sectionTitle('People and payment'),
        const SizedBox(height: 9),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _choice(
              'No loader',
              _loader == 'No loader',
              () => setState(() => _loader = 'No loader'),
            ),
            _choice(
              '👷 One loader',
              _loader == 'One loader',
              () => setState(() => _loader = 'One loader'),
            ),
            _choice(
              '👷👷 Two loaders',
              _loader == 'Two loaders',
              () => setState(() => _loader = 'Two loaders'),
            ),
          ],
        ),
        const SizedBox(height: 13),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _choice(
              '💵 Cash',
              _payment == 'Cash',
              () => setState(() => _payment = 'Cash'),
            ),
            _choice(
              'Easypaisa',
              _payment == 'Easypaisa',
              () => setState(() => _payment = 'Easypaisa'),
            ),
            _choice(
              'JazzCash',
              _payment == 'JazzCash',
              () => setState(() => _payment = 'JazzCash'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _toggleOption(
          'Closed body required',
          _closedBody,
          (value) => setState(() => _closedBody = value),
          Icons.inventory_2_outlined,
        ),
        _toggleOption(
          '1 passenger ride',
          _passenger,
          (value) => setState(() => _passenger = value),
          Icons.person_outline_rounded,
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Cargo photo attachment will be added with request uploads.',
              ),
            ),
          ),
          icon: const Icon(Icons.add_a_photo_outlined),
          label: const Text('Add cargo photo (optional)'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.blue,
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: const BorderSide(color: Color(0xFFD7E2F2)),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Final details and price are discussed between you and the vehicle owner.',
          style: TextStyle(color: Color(0xFF738097), fontSize: 12, height: 1.4),
        ),
      ],
    ),
    bottomNavigationBar: SafeArea(
      minimum: const EdgeInsets.fromLTRB(18, 8, 18, 12),
      child: FilledButton.icon(
        onPressed: _createRequest,
        icon: const Icon(Icons.add_circle_outline_rounded),
        label: const Text('Create request'),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.blue,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    ),
  );

  Widget _sectionTitle(String text) => Text(
    text,
    style: const TextStyle(
      color: AppColors.navy,
      fontSize: 15,
      fontWeight: FontWeight.w800,
    ),
  );

  Widget _formField(
    String label,
    TextEditingController controller,
    IconData icon, {
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) => TextField(
    controller: controller,
    maxLines: maxLines,
    onChanged: onChanged,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: AppColors.blue),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: Color(0xFFE6EAF0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: Color(0xFFE6EAF0)),
      ),
    ),
  );

  Widget _panel(Widget child) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: const Color(0xFFE6EAF0)),
    ),
    child: child,
  );

  Widget _choice(String label, bool selected, VoidCallback onTap) => ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onTap(),
    showCheckmark: false,
    selectedColor: const Color(0xFFE4EEFC),
    backgroundColor: Colors.white,
    side: BorderSide(
      color: selected ? AppColors.blue : const Color(0xFFE3E8EF),
    ),
    labelStyle: TextStyle(
      color: selected ? AppColors.blue : AppColors.navy,
      fontWeight: FontWeight.w600,
      fontSize: 12,
    ),
  );

  Widget _toggleOption(
    String label,
    bool value,
    ValueChanged<bool> onChanged,
    IconData icon,
  ) => _panel(
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Icon(icon, color: AppColors.blue, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.navy,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.blue,
          ),
        ],
      ),
    ),
  );
}

class MovingVehiclePage extends StatelessWidget {
  const MovingVehiclePage({super.key});

  static const vehicles = [
    'Suzuki Ravi / Pickup',
    'Mazda Mini Truck',
    'Shehzore',
    'Mazda Truck',
    'Hino Truck',
    'Suzuki Bolan',
    'Toyota Hiace',
    'Hyundai Shehzore',
    'Kia K2700',
    'Isuzu Truck',
    'JAC Truck',
    'Container Truck',
    'Flatbed Truck',
    'Closed Body Truck',
    'Open Body Truck',
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF4F6F9),
    appBar: AppBar(
      title: const Text('Moving & Logistics'),
      backgroundColor: const Color(0xFFF4F6F9),
    ),
    body: GridView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: vehicles.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.65,
      ),
      itemBuilder: (context, index) {
        final vehicle = vehicles[index];
        return Card(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: const BorderSide(color: Color(0xFFEDF0F4)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(15),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ServiceBookingPage(
                  category: 'Moving & Logistics',
                  service: vehicle,
                  vehicleType: vehicle,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.local_shipping_outlined,
                    color: AppColors.blue,
                    size: 24,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    vehicle,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
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

class ServiceBookingPage extends StatefulWidget {
  const ServiceBookingPage({
    required this.category,
    required this.service,
    this.vehicleType,
    super.key,
  });
  final String category;
  final String service;
  final String? vehicleType;

  @override
  State<ServiceBookingPage> createState() => _ServiceBookingPageState();
}

class _ServiceBookingPageState extends State<ServiceBookingPage> {
  final _requestRepo = RequestRepository();
  FareMode _fareMode = FareMode.fixed;
  String _carClass = 'Normal (without AC)';
  final _pickupController = TextEditingController();
  final _destinationController = TextEditingController();
  final _detailsController = TextEditingController();
  double? _pickupLat;
  double? _pickupLng;
  bool _gettingLocation = false;

  bool get _isCityRide => widget.category == 'City Rides';
  bool get _isCourier => widget.category == 'Courier Service';
  bool get _hasAutomaticFare => _isCityRide || _isCourier;
  bool get _isCar => _isCityRide && widget.service == 'Car';
  bool get _ownerContactFlow => !_hasAutomaticFare;

  @override
  void dispose() {
    _pickupController.dispose();
    _destinationController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _gettingLocation = true);
    try {
      final location = await CurrentLocation.get();
      if (!mounted) return;
      _pickupLat = location.latitude;
      _pickupLng = location.longitude;
      _pickupController.text =
          'Current location (${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)})';
      setState(() {});
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message ?? 'Could not get your location.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _gettingLocation = false);
    }
  }

  Future<void> _openGoogleMaps() async {
    try {
      await GoogleMapsLocation.openPicker();
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? 'Could not open Google Maps.')),
      );
    }
  }

  Future<void> _pasteDestination() async {
    final text = await GoogleMapsLocation.pasteFromClipboard();
    if (!mounted) return;
    if (text == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copy a location or Maps link first.')),
      );
      return;
    }
    final coordinates = await GoogleMapsLocation.resolveCoordinates(text);
    setState(() {
      _destinationController.text = coordinates == null
          ? text
          : 'Selected location (${coordinates.latitude.toStringAsFixed(6)}, ${coordinates.longitude.toStringAsFixed(6)})';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          coordinates == null
              ? 'Location link pasted. Tap it to review or edit.'
              : 'Location and coordinates added.',
        ),
      ),
    );
  }

  Future<void> _showPreview() async {
    FocusScope.of(context).unfocus();
    if (_pickupController.text.trim().isEmpty ||
        _destinationController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter your pickup and destination first.'),
        ),
      );
      return;
    }
    try {
      var destination = _destinationController.text.trim();
      final destinationCoordinates =
          await GoogleMapsLocation.resolveCoordinates(destination);
      if (destinationCoordinates != null) {
        destination =
            'Selected location (${destinationCoordinates.latitude.toStringAsFixed(6)}, ${destinationCoordinates.longitude.toStringAsFixed(6)})';
        _destinationController.text = destination;
      }
      final fareEstimate = _hasAutomaticFare
          ? await FareEstimator.estimateResolved(
              _pickupController.text.trim(),
              destination,
              category: widget.category,
              service: widget.service,
              vehicleType: _vehicleForRequest,
            )
          : null;
      await _requestRepo.createRequest({
        'category': widget.category,
        'service': widget.service,
        'vehicleType': _vehicleForRequest,
        'pickup': _pickupController.text.trim(),
        if (_pickupLat != null) 'pickupLat': _pickupLat,
        if (_pickupLng != null) 'pickupLng': _pickupLng,
        'destination': destination,
        'fareMode': _isCityRide
            ? (_fareMode == FareMode.bargaining ? 'bargaining' : 'fixed')
            : _isCourier
            ? 'fixed'
            : null,
        'details': _detailsController.text.trim(),
        'priceFlow': _hasAutomaticFare
            ? 'fare_option'
            : 'customer_owner_discussion',
      });
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Request submitted'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row('Category', widget.category),
              _row(_isCityRide ? 'Ride type' : 'Service', widget.service),
              if (_isCar) _row('Car option', _carClass),
              if (_isCourier) _row('Courier vehicle', 'Bike'),
              _row('Pickup', _pickupController.text.trim()),
              _row('Destination', _destinationController.text.trim()),
              if (_hasAutomaticFare)
                _row(
                  'Automatic estimate',
                  fareEstimate == null
                      ? 'Coordinates needed for a total'
                      : fareEstimate.calculationSummary,
                ),
              if (_detailsController.text.trim().isNotEmpty)
                _row('Details', _detailsController.text.trim()),
              const SizedBox(height: 14),
              Text(
                _ownerContactFlow
                    ? 'Your request is saved. The owner can review it and discuss the details and price with you.'
                    : 'Your ride request is saved and available for approved drivers to review.',
                style: const TextStyle(
                  color: Color(0xFF738097),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Got it'),
            ),
          ],
        ),
      );
    } on FirebaseException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.code == 'permission-denied'
                ? 'Firestore security rules need to be connected first.'
                : error.message ?? 'Could not submit the request.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  String get _vehicleForRequest => _isCourier
      ? 'Bike'
      : widget.vehicleType ?? (_isCar ? _carClass : widget.service);

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF8792A3), fontSize: 10),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Widget _fareEstimateRow() {
    final rate = FareEstimator.rateFor(
      category: widget.category,
      service: widget.service,
      vehicleType: _vehicleForRequest,
    );
    return FutureBuilder<FareEstimate?>(
      future: FareEstimator.estimateResolved(
        _pickupController.text.trim(),
        _destinationController.text.trim(),
        category: widget.category,
        service: widget.service,
        vehicleType: _vehicleForRequest,
      ),
      builder: (context, snapshot) {
        final estimate = snapshot.data;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF4FE),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                snapshot.connectionState == ConnectionState.waiting
                    ? 'Calculating ${rate.vehicleLabel.toLowerCase()} fare…'
                    : estimate == null
                    ? '${rate.vehicleLabel}: Rs ${rate.ratePerKm.toStringAsFixed(1)}/km · minimum Rs ${rate.minimumFare}'
                    : 'Estimated total: Rs ${estimate.amount}',
                style: const TextStyle(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                estimate == null
                    ? 'Could not read both pins or get a road route. Check connection and try again.'
                    : estimate.calculationSummary,
                style: const TextStyle(
                  color: Color(0xFF657188),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Petrol Rs ${FareEstimator.petrolPricePerLitre.toStringAsFixed(2)}/L · fuel Rs ${rate.fuelPerKm.toStringAsFixed(1)}/km · maintenance Rs ${rate.maintenancePerKm.toStringAsFixed(0)}/km · driver wages Rs ${rate.driverWagePerKm.toStringAsFixed(0)}/km',
                style: const TextStyle(
                  color: Color(0xFF738097),
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
              const Text(
                'Routing by OSRM · © OpenStreetMap contributors (ODbL). Traffic is not included.',
                style: TextStyle(color: Color(0xFF8792A3), fontSize: 10),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF4F6F9),
    appBar: AppBar(
      title: Text(widget.service),
      backgroundColor: const Color(0xFFF4F6F9),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Text(
          widget.service,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          _ownerContactFlow
              ? 'Share the details; the owner will discuss the price with you.'
              : _isCourier
              ? 'Courier service uses a bike. The app estimates fare from route and running costs.'
              : 'Enter your route and choose how to agree on the fare.',
          style: const TextStyle(
            color: Color(0xFF8792A3),
            fontSize: 12,
            height: 1.5,
          ),
        ),
        if (_isCar) ...[
          const SizedBox(height: 20),
          const Text(
            'Choose car type',
            style: TextStyle(
              color: AppColors.navy,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['Normal (without AC)', 'With AC', 'Luxury Car', 'Rental']
                .map(
                  (name) => ChoiceChip(
                    label: Text(name),
                    selected: _carClass == name,
                    onSelected: (_) => setState(() => _carClass = name),
                  ),
                )
                .toList(),
          ),
        ],
        const SizedBox(height: 20),
        _locationFields(),
        if (_ownerContactFlow || _isCourier) ...[
          const SizedBox(height: 15),
          TextField(
            controller: _detailsController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: widget.category == 'Courier Service'
                  ? 'Parcel details'
                  : 'Items / load details',
              hintText: widget.category == 'Courier Service'
                  ? 'What do you need to send?'
                  : 'Describe items and approximate load',
              alignLabelWithHint: true,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (_ownerContactFlow) ...[const SizedBox(height: 14), _ownerNote()],
        ],
        if (_hasAutomaticFare) ...[
          const SizedBox(height: 14),
          _fareEstimateRow(),
        ],
        if (_isCityRide) ...[
          const SizedBox(height: 20),
          const Text(
            'Choose fare style',
            style: TextStyle(
              color: AppColors.navy,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          _fareTile(
            FareMode.bargaining,
            'Bargaining',
            'Offer your fare and agree with the driver.',
            Icons.handshake_outlined,
          ),
          const SizedBox(height: 9),
          _fareTile(
            FareMode.fixed,
            'Fixed fare',
            'No bargaining; confirm the displayed fare.',
            Icons.lock_outline_rounded,
          ),
        ],
        const SizedBox(height: 22),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _showPreview,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('Continue'),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _locationFields() => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
    ),
    child: Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _gettingLocation ? null : _useCurrentLocation,
            icon: _gettingLocation
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location, size: 18),
            label: const Text('Use current location for pickup'),
          ),
        ),
        TextField(
          controller: _pickupController,
          onChanged: (_) {
            _pickupLat = null;
            _pickupLng = null;
          },
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.trip_origin_rounded, color: AppColors.blue),
            hintText: 'Pickup',
            border: InputBorder.none,
            filled: false,
          ),
        ),
        const Divider(height: 1, indent: 54, endIndent: 15),
        TextField(
          controller: _destinationController,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            prefixIcon: Icon(
              Icons.location_on_outlined,
              color: Color(0xFFEA7256),
            ),
            hintText: 'Type or paste Maps / WhatsApp location',
            border: InputBorder.none,
            filled: false,
          ),
          onSubmitted: (_) => _showPreview(),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: _openGoogleMaps,
                icon: const Icon(Icons.map_outlined),
                label: const Text('Open Google Maps'),
              ),
              TextButton.icon(
                onPressed: _pasteDestination,
                icon: const Icon(Icons.content_paste_rounded),
                label: const Text('Paste location'),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _ownerNote() => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF7EB),
      borderRadius: BorderRadius.circular(15),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.support_agent_rounded, color: Color(0xFFCA8326), size: 21),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'The owner will contact you to discuss your request and agree on the price.',
            style: TextStyle(
              color: Color(0xFF77541F),
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _fareTile(
    FareMode mode,
    String title,
    String description,
    IconData icon,
  ) {
    final selected = _fareMode == mode;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _fareMode = mode),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEEF4FE) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.blue : const Color(0xFFE7EBF1),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: selected ? AppColors.blue : const Color(0xFF738097),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: const TextStyle(
                        color: Color(0xFF738097),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.blue,
                  size: 19,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
