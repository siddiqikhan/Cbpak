import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'fare_estimator.dart';
import 'logistics_options.dart';
import 'location/google_maps_location.dart';
import 'request_repository.dart';
import 'theme/app_colors.dart';

class DriverDashboardPage extends StatefulWidget {
  const DriverDashboardPage({required this.user, super.key});
  final User user;

  @override
  State<DriverDashboardPage> createState() => _DriverDashboardPageState();
}

class _DriverDashboardPageState extends State<DriverDashboardPage> {
  final _repo = RequestRepository();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _city = TextEditingController();
  final _registration = TextEditingController();
  String? _vehicleType;
  int _selectedTab = 0;
  final Set<String> _completing = {};
  static const _driverVehicleOptions = <String>[
    'Car',
    'Bike',
    'Rickshaw',
    ...LogisticsOptions.vehicles,
  ];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name.text = widget.user.displayName ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _city.dispose();
    _registration.dispose();
    super.dispose();
  }

  Future<void> _submitProfile() async {
    if (_vehicleType == null ||
        [
          _name,
          _phone,
          _city,
          _registration,
        ].any((c) => c.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete all driver and vehicle details.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _repo.saveDriverProfile(
        name: _name.text,
        phone: _phone.text,
        city: _city.text,
        vehicleType: _vehicleType!,
        vehicleRegistration: _registration.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Driver profile submitted for review.')),
        );
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_errorText(error))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _errorText(FirebaseException error) =>
      error.code == 'permission-denied'
      ? 'Firebase security rules need to be set up before this can be saved.'
      : error.message ?? 'Could not connect to Firebase. Please try again.';

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _repo.watchDriverProfile(),
        builder: (context, snapshot) {
          final profile = snapshot.data?.data();
          final approved = profile?['status'] == 'approved';
          return Scaffold(
            backgroundColor: const Color(0xFFF4F6F9),
            appBar: AppBar(
              title: const Text('Driver mode'),
              backgroundColor: const Color(0xFFF4F6F9),
              leading: PopupMenuButton<int>(
                icon: const Icon(Icons.menu_rounded),
                tooltip: 'Driver mode menu',
                onSelected: (selection) {
                  if (selection == 3) {
                    Navigator.of(context).pop();
                  } else {
                    setState(() => _selectedTab = selection);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 0,
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.travel_explore_outlined),
                      title: Text('Available requests'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 1,
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.person_outline_rounded),
                      title: Text('Driver profile'),
                    ),
                  ),
                  PopupMenuDivider(),
                  PopupMenuItem(
                    value: 3,
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.swap_horiz_rounded),
                      title: Text('Customer mode'),
                    ),
                  ),
                ],
              ),
            ),
            body: snapshot.hasError
                ? _message(
                    Icons.cloud_off_outlined,
                    'Firebase setup is needed',
                    'Driver profiles and requests will appear here after the database and security rules are connected.',
                  )
                : snapshot.connectionState == ConnectionState.waiting
                ? const Center(child: CircularProgressIndicator())
                : profile == null
                ? _profileForm()
                : !approved
                ? _pendingProfile(profile)
                : _approvedPage(profile),
            bottomNavigationBar: approved ? _driverNavigation() : null,
          );
        },
      );

  Widget _driverNavigation() => NavigationBar(
    selectedIndex: _selectedTab,
    onDestinationSelected: (index) => setState(() => _selectedTab = index),
    destinations: const [
      NavigationDestination(
        icon: Icon(Icons.travel_explore_outlined),
        selectedIcon: Icon(Icons.travel_explore_rounded),
        label: 'Requests',
      ),
      NavigationDestination(
        icon: Icon(Icons.person_outline_rounded),
        selectedIcon: Icon(Icons.person_rounded),
        label: 'Profile',
      ),
    ],
  );

  Widget _approvedPage(Map<String, dynamic> profile) =>
      _selectedTab == 0 ? _driverWorkPage() : _driverProfile(profile);

  Widget _driverWorkPage() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text(
        'Driver requests',
        style: TextStyle(
          color: AppColors.navy,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 14),
      _requestSection(
        stream: _repo.watchOpenRequests(),
        title: 'Available requests',
        emptyMessage: 'New customer requests will show here.',
        available: true,
      ),
      const SizedBox(height: 20),
      _requestSection(
        stream: _repo.watchDriverRequests(),
        title: 'Ride history',
        emptyMessage: 'Rides you accept and complete will appear here.',
        available: false,
      ),
    ],
  );

  Widget _driverProfile(Map<String, dynamic> profile) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text(
        'Driver profile',
        style: TextStyle(
          color: AppColors.navy,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 14),
      Card(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFE6EAF0)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 27,
                backgroundColor: Color(0xFFEAF0FA),
                child: Icon(Icons.person_rounded, color: AppColors.blue),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile['name'] as String? ?? 'Driver',
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'Approved driver',
                      style: TextStyle(color: Color(0xFF31834D)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.verified_rounded, color: Color(0xFF39A45A)),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      _profileSection('Contact details', [
        _profileDetail(Icons.phone_outlined, 'Phone', profile['phone']),
        _profileDetail(Icons.location_city_outlined, 'City', profile['city']),
      ]),
      const SizedBox(height: 12),
      _profileSection('Vehicle details', [
        _profileDetail(
          Icons.local_shipping_outlined,
          'Vehicle type',
          profile['vehicleType'],
        ),
        _profileDetail(
          Icons.confirmation_number_outlined,
          'Registration',
          profile['vehicleRegistration'],
        ),
      ]),
    ],
  );

  Widget _profileSection(String title, List<Widget> details) => Card(
    color: Colors.white,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: Color(0xFFE6EAF0)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
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
          const SizedBox(height: 9),
          ...details,
        ],
      ),
    ),
  );

  Widget _profileDetail(IconData icon, String label, Object? value) {
    final text = value?.toString() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF738097), size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF8792A3),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileForm() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text(
        'Set up your driver profile',
        style: TextStyle(
          color: AppColors.navy,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 7),
      const Text(
        'Add your contact and vehicle details. Accounts are reviewed before requests become visible.',
        style: TextStyle(color: Color(0xFF738097), height: 1.45),
      ),
      const SizedBox(height: 18),
      _input('Full name', _name, Icons.person_outline_rounded),
      const SizedBox(height: 11),
      _input('Phone number', _phone, Icons.phone_outlined, TextInputType.phone),
      const SizedBox(height: 11),
      _input('City', _city, Icons.location_city_outlined),
      const SizedBox(height: 11),
      DropdownButtonFormField<String>(
        initialValue: _vehicleType,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Vehicle type',
          prefixIcon: Icon(Icons.local_shipping_outlined),
        ),
        items: _driverVehicleOptions
            .map(
              (type) => DropdownMenuItem(
                value: type,
                child: Text(type, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) setState(() => _vehicleType = value);
        },
      ),
      const SizedBox(height: 11),
      _input(
        'Vehicle registration',
        _registration,
        Icons.confirmation_number_outlined,
      ),
      const SizedBox(height: 18),
      FilledButton(
        onPressed: _saving ? null : _submitProfile,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.blue,
          padding: const EdgeInsets.symmetric(vertical: 15),
        ),
        child: _saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text('Submit for review'),
      ),
    ],
  );

  Widget _pendingProfile(Map<String, dynamic> profile) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      _message(
        Icons.hourglass_top_rounded,
        'Profile submitted',
        'Your driver and vehicle details are waiting for review. Request access opens after the account is approved.',
      ),
      const SizedBox(height: 12),
      _profileSection('Submitted driver details', [
        _profileDetail(
          Icons.person_outline_rounded,
          'Full name',
          profile['name'],
        ),
        _profileDetail(Icons.phone_outlined, 'Phone', profile['phone']),
        _profileDetail(Icons.location_city_outlined, 'City', profile['city']),
        _profileDetail(
          Icons.local_shipping_outlined,
          'Vehicle type',
          profile['vehicleType'],
        ),
        _profileDetail(
          Icons.confirmation_number_outlined,
          'Registration',
          profile['vehicleRegistration'],
        ),
      ]),
    ],
  );

  Widget _input(
    String label,
    TextEditingController controller,
    IconData icon, [
    TextInputType? keyboard,
  ]) => TextField(
    controller: controller,
    keyboardType: keyboard,
    decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
  );

  Widget _message(IconData icon, String title, String message) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.blue, size: 54),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF738097), height: 1.5),
        ),
      ],
    ),
  );

  Widget _requestSection({
    required Stream<QuerySnapshot<Map<String, dynamic>>> stream,
    required String title,
    required String emptyMessage,
    required bool available,
  }) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: stream,
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return _sectionMessage(
          title,
          'Could not load requests. Check the Firebase connection.',
        );
      if (snapshot.connectionState == ConnectionState.waiting)
        return _sectionMessage(title, 'Loading…');
      final requests = [...?snapshot.data?.docs];
      if (available) {
        requests.removeWhere((request) {
          final declinedBy =
              request.data()['declinedBy'] as List<dynamic>? ?? const [];
          return declinedBy.contains(widget.user.uid);
        });
      }
      requests.sort((a, b) {
        final aTime = a.data()['createdAt'] as Timestamp?;
        final bTime = b.data()['createdAt'] as Timestamp?;
        return (bTime?.millisecondsSinceEpoch ?? 0).compareTo(
          aTime?.millisecondsSinceEpoch ?? 0,
        );
      });
      final completedCount = requests
          .where((request) => request.data()['status'] == 'completed')
          .length;
      final sectionTitle = available
          ? title
          : '$title · $completedCount completed / ${requests.length} total';
      if (requests.isEmpty) return _sectionMessage(sectionTitle, emptyMessage);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sectionTitle,
            style: const TextStyle(
              color: AppColors.navy,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          for (final request in requests)
            _requestCard(request.id, request.data(), available: available),
        ],
      );
    },
  );

  Widget _sectionMessage(String title, String message) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          style: const TextStyle(color: Color(0xFF738097), height: 1.4),
        ),
      ],
    ),
  );

  Widget _requestCard(
    String id,
    Map<String, dynamic> data, {
    required bool available,
  }) => InkWell(
    onTap: () => _openRequestDetails(id, data, available: available),
    borderRadius: BorderRadius.circular(16),
    child: Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE6EAF0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              data['vehicleType'] as String? ??
                  data['service'] as String? ??
                  'Service request',
              style: const TextStyle(
                color: AppColors.navy,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            _route(Icons.trip_origin_rounded, data['pickup'] as String? ?? ''),
            const SizedBox(height: 7),
            _route(
              Icons.location_on_outlined,
              data['destination'] as String? ?? '',
            ),
            const SizedBox(height: 8),
            if (data['category'] == 'City Rides' ||
                data['category'] == 'Courier Service')
              _fareSummary(data),
            if ((data['cargoDescription'] as String? ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                data['cargoDescription'] as String,
                style: const TextStyle(color: Color(0xFF657188)),
              ),
            ],
            if ((data['pickupTime'] as String? ?? '').isNotEmpty)
              Text(
                'Pickup: ${data['pickupTime']}',
                style: const TextStyle(color: Color(0xFF657188), fontSize: 12),
              ),
            if ((data['loader'] as String? ?? '').isNotEmpty)
              Text(
                'Help: ${data['loader']}',
                style: const TextStyle(color: Color(0xFF657188), fontSize: 12),
              ),
            if ((data['paymentMethod'] as String? ?? '').isNotEmpty)
              Text(
                'Payment: ${data['paymentMethod']}',
                style: const TextStyle(color: Color(0xFF657188), fontSize: 12),
              ),
            const SizedBox(height: 13),
            if (!available) ...[
              Text(
                'Status: ${_statusLabel(data['status'] as String?)}',
                style: const TextStyle(
                  color: AppColors.blue,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (data['status'] == 'accepted') ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _completing.contains(id)
                        ? null
                        : () => _completeRide(id),
                    icon: _completing.contains(id)
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_circle_outline_rounded),
                    label: const Text('Complete ride'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.blue,
                    ),
                  ),
                ),
              ],
            ] else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _decline(id),
                      child: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _accept(id),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.blue,
                      ),
                      child: const Text('Accept'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    ),
  );

  Future<void> _openRequestDetails(
    String id,
    Map<String, dynamic> data, {
    required bool available,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => DriverRequestDetailsPage(
        requestId: id,
        data: data,
        available: available,
        onAccept: () => _accept(id),
        onDecline: () => _decline(id),
      ),
    ),
  );

  Widget _route(IconData icon, String text) => Row(
    children: [
      Icon(icon, color: AppColors.blue, size: 18),
      const SizedBox(width: 9),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            color: AppColors.navy,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );

  Widget _fareSummary(Map<String, dynamic> data) {
    final category = data['category'] as String? ?? 'City Rides';
    final service = data['service'] as String?;
    final vehicleType = data['vehicleType'] as String?;
    final rate = FareEstimator.rateFor(
      category: category,
      service: service,
      vehicleType: vehicleType,
    );
    return FutureBuilder<FareEstimate?>(
      future: FareEstimator.estimateResolved(
        data['pickup'] as String?,
        data['destination'] as String?,
        category: category,
        service: service,
        vehicleType: vehicleType,
      ),
      builder: (context, snapshot) => Text(
        snapshot.data == null
            ? '${rate.vehicleLabel}: Rs ${rate.ratePerKm.toStringAsFixed(1)}/km · minimum Rs ${rate.minimumFare}'
            : snapshot.data!.calculationSummary,
        style: const TextStyle(
          color: AppColors.blue,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Future<bool> _accept(String id) async {
    try {
      await _repo.acceptRequest(id);
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Request accepted.')));
      return true;
    } on FirebaseException catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_errorText(error))));
      return false;
    } on StateError catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      return false;
    }
  }

  String _statusLabel(String? status) => switch (status) {
    'accepted' => 'Accepted',
    'completed' => 'Completed',
    'cancelled' => 'Cancelled',
    _ => 'Open',
  };

  Future<void> _completeRide(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Complete this ride?'),
        content: const Text(
          'This will mark the ride as completed for you and the customer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Complete ride'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _completing.add(id));
    try {
      await _repo.completeDriverRide(id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Ride marked completed.')));
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_errorText(error))));
      }
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _completing.remove(id));
    }
  }

  Future<bool> _decline(String id) async {
    try {
      await _repo.declineRequest(id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Request declined.')));
      }
      return true;
    } on FirebaseException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_errorText(error))));
      }
      return false;
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
      return false;
    }
  }
}

class DriverRequestDetailsPage extends StatelessWidget {
  const DriverRequestDetailsPage({
    required this.requestId,
    required this.data,
    required this.available,
    required this.onAccept,
    required this.onDecline,
    super.key,
  });

  final String requestId;
  final Map<String, dynamic> data;
  final bool available;
  final Future<bool> Function() onAccept;
  final Future<bool> Function() onDecline;

  @override
  Widget build(BuildContext context) {
    final category = data['category'] as String? ?? 'City Rides';
    final service = data['service'] as String?;
    final vehicleType = data['vehicleType'] as String?;
    final estimate = FareEstimator.estimateResolved(
      data['pickup'] as String?,
      data['destination'] as String?,
      category: category,
      service: service,
      vehicleType: vehicleType,
    );
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text('Request details'),
        backgroundColor: const Color(0xFFF4F6F9),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            data['vehicleType'] as String? ??
                data['service'] as String? ??
                'Ride request',
            style: const TextStyle(
              color: AppColors.navy,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${data['category'] ?? ''} · ${data['service'] ?? ''}',
            style: const TextStyle(color: Color(0xFF738097)),
          ),
          const SizedBox(height: 16),
          _location(context, 'Pickup', data['pickup']),
          const SizedBox(height: 12),
          _location(context, 'Destination', data['destination']),
          if (category == 'City Rides' || category == 'Courier Service') ...[
            const SizedBox(height: 12),
            FutureBuilder<FareEstimate?>(
              future: estimate,
              builder: (context, snapshot) => _fareCard(
                snapshot.data,
                rate: FareEstimator.rateFor(
                  category: category,
                  service: service,
                  vehicleType: vehicleType,
                ),
                loading: snapshot.connectionState == ConnectionState.waiting,
              ),
            ),
          ],
          const SizedBox(height: 12),
          _infoCard('Ride details', [
            _detail('Fare style', data['fareMode']),
            _detail('Pickup time', data['pickupTime']),
            _detail('Payment', data['paymentMethod']),
            _detail('Customer', data['customerName']),
            _detail('Help / loader', data['loader']),
            _detail(
              'Cargo / notes',
              data['cargoDescription'] ?? data['details'],
            ),
            _detail('Status', data['status']),
          ]),
          if (available) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      if (await onDecline() && context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      if (await onAccept() && context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.blue,
                    ),
                    child: const Text('Accept request'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _location(BuildContext context, String title, Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE6EAF0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
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
            const SizedBox(height: 5),
            SelectableText(text),
            FutureBuilder<({double latitude, double longitude})?>(
              future: GoogleMapsLocation.resolveCoordinates(text),
              builder: (context, snapshot) {
                final coordinates =
                    snapshot.data ?? GoogleMapsLocation.coordinatesFrom(text);
                final coordinateText = coordinates == null
                    ? null
                    : '${coordinates.latitude.toStringAsFixed(6)}, ${coordinates.longitude.toStringAsFixed(6)}';
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (coordinateText != null) ...[
                      const SizedBox(height: 3),
                      SelectableText(
                        coordinateText,
                        style: const TextStyle(
                          color: Color(0xFF738097),
                          fontSize: 12,
                        ),
                      ),
                    ],
                    Wrap(
                      spacing: 4,
                      children: [
                        TextButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: coordinateText ?? text),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    coordinateText == null
                                        ? '$title copied.'
                                        : '$title coordinates copied.',
                                  ),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.copy_rounded, size: 17),
                          label: Text(
                            coordinateText == null
                                ? 'Copy $title'
                                : 'Copy coordinates',
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            try {
                              if (coordinates == null) {
                                await GoogleMapsLocation.openMapSearch(text);
                              } else {
                                await GoogleMapsLocation.openMapAt(
                                  coordinates.latitude,
                                  coordinates.longitude,
                                );
                              }
                            } on PlatformException catch (error) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      error.message ?? 'Could not open Maps.',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.open_in_new_rounded, size: 17),
                          label: const Text('Open in Maps'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _fareCard(
    FareEstimate? estimate, {
    required FareRate rate,
    required bool loading,
  }) => Card(
    color: const Color(0xFFEEF4FE),
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.route_rounded, color: AppColors.blue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Distance & fare estimate',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  loading
                      ? 'Resolving the destination pin…'
                      : estimate == null
                      ? '${rate.vehicleLabel}: Rs ${rate.ratePerKm.toStringAsFixed(1)}/km · minimum Rs ${rate.minimumFare}. Could not read both pins or get a road route; check connection and try again.'
                      : estimate.calculationSummary,
                  style: const TextStyle(
                    color: Color(0xFF657188),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                if (estimate != null)
                  const Text(
                    'Routing by OSRM · © OpenStreetMap contributors (ODbL). Traffic is not included.',
                    style: TextStyle(color: Color(0xFF8792A3), fontSize: 11),
                  ),
                if (estimate != null)
                  Text(
                    'Petrol Rs ${FareEstimator.petrolPricePerLitre.toStringAsFixed(2)}/L · fuel Rs ${estimate.rate.fuelPerKm.toStringAsFixed(1)}/km · maintenance Rs ${estimate.rate.maintenancePerKm.toStringAsFixed(0)}/km · driver wages Rs ${estimate.rate.driverWagePerKm.toStringAsFixed(0)}/km',
                    style: const TextStyle(
                      color: Color(0xFF738097),
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                Text(
                  'Petrol Rs ${FareEstimator.petrolPricePerLitre.toStringAsFixed(2)}/L · fuel Rs ${rate.fuelPerKm.toStringAsFixed(1)}/km · maintenance Rs ${rate.maintenancePerKm.toStringAsFixed(0)}/km · driver wages Rs ${rate.driverWagePerKm.toStringAsFixed(0)}/km',
                  style: const TextStyle(
                    color: Color(0xFF738097),
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _infoCard(String title, List<Widget> details) => Card(
    color: Colors.white,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: Color(0xFFE6EAF0)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(15),
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
          const SizedBox(height: 10),
          ...details,
        ],
      ),
    ),
  );

  Widget _detail(String label, Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF8792A3), fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(
            text,
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
