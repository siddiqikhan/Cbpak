import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'location/google_maps_location.dart';

import 'request_repository.dart';
import 'theme/app_colors.dart';

class CustomerRideDetailsPage extends StatelessWidget {
  const CustomerRideDetailsPage({required this.request, super.key});

  final QueryDocumentSnapshot<Map<String, dynamic>> request;

  @override
  Widget build(BuildContext context) {
    final data = request.data();
    final status = data['status'] as String? ?? 'open';
    final accepted = status == 'accepted' || status == 'completed';
    return Scaffold(
      appBar: AppBar(title: const Text('Ride details')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            _statusLabel(status),
            style: const TextStyle(
              color: AppColors.blue,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          _detail('Service', data['service'] ?? data['category']),
          _detail('Vehicle', data['vehicleType']),
          _locationDetail(context, 'Pickup', data['pickup']),
          _locationDetail(context, 'Destination', data['destination']),
          _detail('Fare option', data['fareMode']),
          _detail('Details', data['details']),
          _detail('Pickup time', data['pickupTime']),
          if (accepted) ...[
            const SizedBox(height: 12),
            const Text(
              'Driver',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            StreamBuilder(
              stream: RequestRepository().watchRideContact(request.id),
              builder: (context, snapshot) {
                final contact = snapshot.data?.data();
                if (snapshot.hasError) {
                  return const Text('Driver contact could not be loaded.');
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LinearProgressIndicator();
                }
                if (contact == null) {
                  return const Text(
                    'Driver contact is unavailable for this earlier ride.',
                  );
                }
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5FC),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _detail('Name', contact['driverName']),
                      _phoneDetail(
                        context,
                        contact['driverPhone']?.toString() ?? '',
                      ),
                      _detail('Vehicle', contact['vehicleType']),
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _locationDetail(BuildContext context, String title, Object? value) {
    if (value == null || '$value'.trim().isEmpty)
      return const SizedBox.shrink();
    final coordinates = GoogleMapsLocation.coordinatesFrom('$value');
    if (coordinates == null) return _detail(title, value);
    final coordinateText =
        '${coordinates.latitude.toStringAsFixed(6)}, ${coordinates.longitude.toStringAsFixed(6)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Color(0xFF8792A3), fontSize: 12),
          ),
          const SizedBox(height: 3),
          SelectableText(
            '$value',
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w600,
            ),
          ),
          SelectableText(
            coordinateText,
            style: const TextStyle(color: Color(0xFF657188), fontSize: 12),
          ),
          Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: coordinateText));
                  if (context.mounted)
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Coordinates copied.')),
                    );
                },
                icon: const Icon(Icons.copy_rounded, size: 17),
                label: const Text('Copy coordinates'),
              ),
              TextButton.icon(
                onPressed: () async {
                  try {
                    await GoogleMapsLocation.openMapAt(
                      coordinates.latitude,
                      coordinates.longitude,
                    );
                  } on PlatformException catch (error) {
                    if (context.mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            error.message ?? 'Could not open Maps.',
                          ),
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
      ),
    );
  }

  Widget _phoneDetail(BuildContext context, String phone) {
    if (phone.trim().isEmpty) return _detail('Phone', phone);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Phone',
            style: TextStyle(color: Color(0xFF8792A3), fontSize: 12),
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  phone,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  try {
                    await GoogleMapsLocation.openWhatsApp(phone);
                  } on PlatformException catch (error) {
                    if (context.mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            error.message ?? 'Could not open WhatsApp.',
                          ),
                        ),
                      );
                  }
                },
                icon: const Icon(Icons.chat_rounded, size: 17),
                label: const Text('WhatsApp'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detail(String title, Object? value) {
    if (value == null || '$value'.trim().isEmpty)
      return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Color(0xFF8792A3), fontSize: 12),
          ),
          const SizedBox(height: 3),
          Text(
            '$value',
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String status) => switch (status) {
    'open' => 'Waiting for a driver',
    'accepted' => 'Driver accepted your ride',
    'completed' => 'Ride completed',
    'cancelled' => 'Ride cancelled',
    _ => status,
  };
}
