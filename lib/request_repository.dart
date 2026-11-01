import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RequestRepository {
  RequestRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sign in before creating a request.');
    return user.uid;
  }

  Future<String> createRequest(Map<String, Object?> details) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sign in before creating a request.');
    final document = await _firestore.collection('requests').add({
      ...details,
      'customerId': user.uid,
      'customerName': user.displayName ?? 'CBPAK customer',
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return document.id;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchCustomerRequests() =>
      _firestore
          .collection('requests')
          .where('customerId', isEqualTo: _uid)
          .snapshots();

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchRideContact(
    String requestId,
  ) => _firestore.collection('rideContacts').doc(requestId).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> watchOpenRequests() => _firestore
      .collection('requests')
      .where('status', isEqualTo: 'open')
      .snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> watchDriverRequests() =>
      _firestore
          .collection('requests')
          .where('driverId', isEqualTo: _uid)
          .snapshots();

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchDriverProfile() =>
      _firestore.collection('drivers').doc(_uid).snapshots();

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchAdminAccess() =>
      _firestore.collection('admins').doc(_uid).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> watchPendingDrivers() =>
      _firestore
          .collection('drivers')
          .where('status', isEqualTo: 'pending')
          .snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> watchAdminRides() => _firestore
      .collection('requests')
      .where('status', whereIn: const ['open', 'accepted'])
      .snapshots();

  Future<void> cancelAdminRide(String requestId) async {
    final ref = _firestore.collection('requests').doc(requestId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final status = snapshot.data()?['status'];
      if (!snapshot.exists || (status != 'open' && status != 'accepted')) {
        throw StateError('This ride is no longer active.');
      }
      transaction.update(ref, {
        'status': 'cancelled',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> cancelCustomerRide(String requestId) async {
    final uid = _uid;
    final ref = _firestore.collection('requests').doc(requestId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      if (!snapshot.exists ||
          data?['customerId'] != uid ||
          data?['status'] != 'open') {
        throw StateError('This ride can no longer be cancelled here.');
      }
      transaction.update(ref, {
        'status': 'cancelled',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> approveDriver(String driverId) =>
      _firestore.collection('drivers').doc(driverId).update({
        'status': 'approved',
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> saveDriverProfile({
    required String name,
    required String phone,
    required String city,
    required String vehicleType,
    required String vehicleRegistration,
  }) async {
    await _firestore.collection('drivers').doc(_uid).set({
      'uid': _uid,
      'name': name.trim(),
      'phone': phone.trim(),
      'city': city.trim(),
      'vehicleType': vehicleType,
      'vehicleRegistration': vehicleRegistration.trim(),
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> acceptRequest(String requestId) async {
    final uid = _uid;
    final ref = _firestore.collection('requests').doc(requestId);
    final profileRef = _firestore.collection('drivers').doc(uid);
    final contactRef = _firestore.collection('rideContacts').doc(requestId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists || snapshot.data()?['status'] != 'open') {
        throw StateError('This request is no longer available.');
      }
      final profile = await transaction.get(profileRef);
      final driver = profile.data();
      if (!profile.exists || driver?['status'] != 'approved') {
        throw StateError('Your driver profile is not approved.');
      }
      final contact = <String, Object?>{
        'customerId': snapshot.data()?['customerId'],
        'driverId': uid,
        'driverName': driver?['name'] ?? 'CBPAK driver',
        'driverPhone': driver?['phone'] ?? '',
        'vehicleType': driver?['vehicleType'] ?? '',
      };
      transaction.update(ref, {
        'status': 'accepted',
        'driverId': uid,
        'acceptedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(contactRef, contact);
    });
  }

  Future<void> completeDriverRide(String requestId) async {
    final uid = _uid;
    final ref = _firestore.collection('requests').doc(requestId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      if (!snapshot.exists ||
          data?['status'] != 'accepted' ||
          data?['driverId'] != uid) {
        throw StateError('This ride is no longer assigned to you.');
      }
      transaction.update(ref, {
        'status': 'completed',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> declineRequest(String requestId) async {
    final uid = _uid;
    final ref = _firestore.collection('requests').doc(requestId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      if (!snapshot.exists || data?['status'] != 'open') {
        throw StateError('This request is no longer available.');
      }

      final declinedBy = List<String>.from(
        (data?['declinedBy'] as List<dynamic>?) ?? const <dynamic>[],
      );
      if (declinedBy.contains(uid)) {
        throw StateError('You have already declined this request.');
      }

      transaction.update(ref, {
        'declinedBy': [...declinedBy, uid],
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
