import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'request_repository.dart';
import 'theme/app_colors.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final _repository = RequestRepository();
  final Set<String> _approving = {};
  final Set<String> _cancelling = {};

  Future<void> _approve(String driverId) async {
    setState(() => _approving.add(driverId));
    try {
      await _repository.approveDriver(driverId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Driver approved.')),
        );
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message ?? 'Could not approve driver.')),
        );
      }
    } finally {
      if (mounted) setState(() => _approving.remove(driverId));
    }
  }

  Future<void> _cancelRide(String rideId) async {
    setState(() => _cancelling.add(rideId));
    try {
      await _repository.cancelAdminRide(rideId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ride cancelled.')),
        );
      }
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message ?? 'Could not cancel ride.')),
        );
      }
    } finally {
      if (mounted) setState(() => _cancelling.remove(rideId));
    }
  }

  Future<void> _showRideDetails(
    String rideId,
    Map<String, dynamic> data,
  ) async {
    final status = data['status'] as String? ?? 'open';
    final canCancel = status == 'open' || status == 'accepted';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ride details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detail('Status', status),
              _detail('Category', data['category'] as String?),
              _detail('Ride / service', data['service'] as String?),
              _detail('Vehicle', data['vehicleType'] as String?),
              _detail('Pickup', data['pickup'] as String?),
              _detail('Destination', data['destination'] as String?),
              _detail('Fare style', data['fareMode'] as String?),
              _detail('Pickup time', data['pickupTime'] as String?),
              _detail('Ride details', data['details'] as String?),
              _detail('Load details', data['cargoDescription'] as String?),
              _detail('Loading help', data['loader'] as String?),
              _detail('Payment', data['paymentMethod'] as String?),
              if (status == 'accepted')
                _detail('Driver', data['driverId'] == null ? null : 'Assigned'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Close'),
          ),
          if (canCancel)
            FilledButton.tonal(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Cancel ride'),
            ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final cancelConfirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this ride?'),
        content: const Text(
          'The ride will be marked cancelled and will no longer be active for the customer or driver.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep ride'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm cancellation'),
          ),
        ],
      ),
    );
    if (cancelConfirmed == true && mounted) await _cancelRide(rideId);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF4F6F9),
    appBar: AppBar(
      title: const Text('Admin dashboard'),
      backgroundColor: const Color(0xFFF4F6F9),
    ),
    body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _repository.watchAdminAccess(),
      builder: (context, adminSnapshot) {
        if (adminSnapshot.hasError) {
          return _message('Could not verify admin access.');
        }
        if (adminSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (adminSnapshot.data?.exists != true) {
          return _message('Admin access has not been configured for this account.');
        }
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _repository.watchPendingDrivers(),
          builder: (context, driversSnapshot) {
            if (driversSnapshot.hasError) {
              return _message('Could not load driver applications.');
            }
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _repository.watchAdminRides(),
              builder: (context, ridesSnapshot) {
                if (ridesSnapshot.hasError) {
                  return _message('Could not load active rides.');
                }
                if (driversSnapshot.connectionState == ConnectionState.waiting ||
                    ridesSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final drivers = driversSnapshot.data?.docs ?? [];
                final rides = [...?ridesSnapshot.data?.docs];
                rides.sort((a, b) {
                  final aTime = a.data()['createdAt'] as Timestamp?;
                  final bTime = b.data()['createdAt'] as Timestamp?;
                  return (bTime?.millisecondsSinceEpoch ?? 0)
                      .compareTo(aTime?.millisecondsSinceEpoch ?? 0);
                });
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _sectionTitle('Driver applications'),
                    if (drivers.isEmpty)
                      _emptySection('No driver profiles are waiting for review.')
                    else
                      for (final driver in drivers)
                        _driverCard(driver.id, driver.data()),
                    const SizedBox(height: 18),
                    _sectionTitle('Active rides'),
                    if (rides.isEmpty)
                      _emptySection('There are no open or accepted rides.')
                    else
                      for (final ride in rides)
                        _rideCard(ride.id, ride.data()),
                  ],
                );
              },
            );
          },
        );
      },
    ),
  );

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      title,
      style: const TextStyle(
        color: AppColors.navy,
        fontSize: 21,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  Widget _emptySection(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
    child: Text(text, style: const TextStyle(color: Color(0xFF738097))),
  );

  Widget _driverCard(String id, Map<String, dynamic> data) {
    final busy = _approving.contains(id);
    return Card(
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
              data['name'] as String? ?? 'Driver',
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            _detail('City', data['city'] as String?),
            _detail('Vehicle', data['vehicleType'] as String?),
            _detail('Registration', data['vehicleRegistration'] as String?),
            _detail('Phone', data['phone'] as String?),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : () => _approve(id),
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.verified_outlined),
                label: const Text('Approve driver'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.blue),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rideCard(String id, Map<String, dynamic> data) {
    final status = data['status'] as String? ?? 'open';
    final busy = _cancelling.contains(id);
    final title = data['vehicleType'] as String? ??
        data['service'] as String? ??
        data['category'] as String? ??
        'Ride';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE6EAF0)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showRideDetails(id, data),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Text(
                    status == 'accepted' ? 'Accepted' : 'Open',
                    style: const TextStyle(
                      color: AppColors.blue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _detail('From', data['pickup'] as String?),
              _detail('To', data['destination'] as String?),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.touch_app_outlined, size: 17, color: AppColors.blue),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Tap for full details and cancellation',
                      style: TextStyle(color: Color(0xFF657188), fontSize: 12),
                    ),
                  ),
                  if (busy)
                    const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detail(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '$label: $value',
        style: const TextStyle(color: Color(0xFF657188)),
      ),
    );
  }

  Widget _message(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFF738097), height: 1.5),
      ),
    ),
  );
}
