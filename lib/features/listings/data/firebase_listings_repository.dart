import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../authentication/data/firebase_auth_repository.dart';
import '../domain/listing.dart';
import '../domain/listings_repository.dart';

final listingsProvider = FutureProvider<FirebaseListingsRepository?>((
  ref,
) async {
  if (ref.watch(signedInProvider).value != true) return null;
  final auth = await ref.watch(authRepositoryProvider.future);
  if (auth == null) return null;
  final app = Firebase.app();
  final user = FirebaseAuth.instanceFor(app: app).currentUser;
  if (user == null) return null;
  const bucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
  return FirebaseListingsRepository(
    FirebaseFirestore.instanceFor(app: app),
    bucket.trim().isEmpty
        ? null
        : FirebaseStorage.instanceFor(
            app: app,
            bucket: 'gs://${bucket.trim().replaceFirst('gs://', '')}',
          ),
    user,
  );
});

class FirebaseListingsRepository implements ListingsRepository {
  FirebaseListingsRepository(this.db, this._storage, this._user);

  final FirebaseFirestore db;
  final FirebaseStorage? _storage;
  final User _user;
  bool get canUpload => _storage != null;
  String newListingId() => _listings.doc().id;

  Future<Uint8List?> readPhoto(String url) async {
    final storage = _storage;
    if (storage == null || !url.startsWith('gs://')) return null;
    final reference = storage.refFromURL(url);
    if (reference.bucket != storage.ref().bucket) return null;
    const limit = 2 * 1024 * 1024;
    if (!kIsWeb) return reference.getData(limit);

    // The Flutter web getData implementation requests a long-lived download URL.
    final token = await _user.getIdToken();
    if (token == null || token.isEmpty) return null;
    final path = Uri.encodeComponent(reference.fullPath);
    final url = Uri.parse(
      'https://firebasestorage.googleapis.com/v0/b/${reference.bucket}/o/$path?alt=media',
    );
    final response = await http.get(
      url,
      headers: {'Authorization': 'Firebase $token'},
    );
    if (response.statusCode != 200 || response.bodyBytes.length > limit)
      return null;
    return response.bodyBytes;
  }

  @override
  String get userId => _user.uid;

  CollectionReference<Map<String, dynamic>> get _listings =>
      db.collection('listings');
  CollectionReference<Map<String, dynamic>> get _favorites =>
      db.collection('listingUserData').doc(userId).collection('favorites');

  @override
  Stream<List<Listing>> search(ListingSearch filter) {
    Query<Map<String, dynamic>> query = _listings.where(
      'status',
      isEqualTo: 'active',
    );
    if (filter.city.isNotEmpty)
      query = query.where('cityKey', isEqualTo: locationKey(filter.city));
    if (filter.district.isNotEmpty)
      query = query.where(
        'districtKey',
        isEqualTo: locationKey(filter.district),
      );
    final hasRent = filter.minRent != null || filter.maxRent != null;
    if (filter.minRent case final min?)
      query = query.where('monthlyRent', isGreaterThanOrEqualTo: min);
    if (filter.maxRent case final max?)
      query = query.where('monthlyRent', isLessThanOrEqualTo: max);
    if (hasRent || filter.sort != ListingSort.newest) {
      query = query.orderBy(
        'monthlyRent',
        descending: filter.sort == ListingSort.highest,
      );
    }
    query = query.orderBy('createdAt', descending: true);
    return query
        .snapshots(includeMetadataChanges: true)
        .where((snapshot) => !snapshot.metadata.isFromCache)
        .map((snapshot) {
          final items = snapshot.docs.map(_read).where(filter.matches).toList();
          if (hasRent && filter.sort == ListingSort.newest) {
            items.sort(
              (a, b) => (b.createdAt ?? DateTime(1970)).compareTo(
                a.createdAt ?? DateTime(1970),
              ),
            );
          }
          return items;
        });
  }

  @override
  Stream<List<Listing>> watchMine() => _listings
      .where('userId', isEqualTo: userId)
      .snapshots()
      .map(
        (s) => s.docs.map(_read).toList()
          ..sort(
            (a, b) => (b.createdAt ?? DateTime(1970)).compareTo(
              a.createdAt ?? DateTime(1970),
            ),
          ),
      );

  @override
  Stream<Listing?> watchListing(String id) => _listings
      .doc(id)
      .snapshots(includeMetadataChanges: true)
      .where(
        (doc) => !doc.metadata.isFromCache || doc.data()?['userId'] == userId,
      )
      .map((doc) {
        final data = doc.data();
        if (data == null ||
            (data['userId'] != userId && data['status'] != 'active')) {
          return null;
        }
        return _read(doc);
      });

  @override
  Stream<Set<String>> watchFavorites() =>
      _favorites.snapshots().map((s) => s.docs.map((doc) => doc.id).toSet());

  @override
  Future<void> setFavorite(String id, bool favorite) => favorite
      ? _favorites.doc(id).set({'createdAt': FieldValue.serverTimestamp()})
      : _favorites.doc(id).delete();

  @override
  Future<void> recordView(String id) => db.runTransaction((transaction) async {
    final listing = _listings.doc(id);
    final view = listing.collection('views').doc(userId);
    final doc = await transaction.get(listing);
    if (!doc.exists ||
        doc.get('userId') == userId ||
        doc.get('status') != 'active')
      return;
    if ((await transaction.get(view)).exists) return;
    transaction.set(view, {'createdAt': FieldValue.serverTimestamp()});
    transaction.update(listing, {'viewCount': FieldValue.increment(1)});
  });

  @override
  Future<String> save(
    ListingForm form,
    List<ListingPhoto> photos,
    int coverIndex, {
    Listing? existing,
    String? createId,
    required void Function(double) onProgress,
  }) async {
    if (photos.length > 10 ||
        (photos.isNotEmpty &&
            (coverIndex < 0 || coverIndex >= photos.length))) {
      throw ArgumentError('Invalid listing photos');
    }
    final listing = existing == null
        ? _listings.doc(createId)
        : _listings.doc(existing.id);
    final revisionId = _listings.doc().id;
    final newPaths = <String>[];
    final results = <ListingPhoto>[];
    final created = existing == null;
    if (photos.any((photo) => photo.bytes != null) && _storage == null) {
      throw StateError('Listing storage bucket is missing');
    }
    if (created) {
      final prior = await listing.get(const GetOptions(source: Source.server));
      if (prior.exists && prior.get('userId') != userId) {
        throw StateError('Listing already exists');
      }
      if (prior.exists && prior.get('status') == 'active') return listing.id;
      if (prior.exists && prior.get('status') != 'draft') {
        throw StateError('Listing is unavailable');
      }
      if (!prior.exists) {
        await listing.set({
          ..._write(form),
          'id': listing.id,
          'userId': userId,
          'ownerName': String.fromCharCodes(
            (_user.displayName ?? '').trim().runes.take(80),
          ),
          'status': 'draft',
          'revision': 0,
          'viewCount': 0,
          'imageUrls': <String>[],
          'imagePaths': <String>[],
          'retiredPaths': <String>[],
          'coverImageUrl': null,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
    var committed = false;
    try {
      for (var i = 0; i < photos.length; i++) {
        final photo = photos[i];
        final bytes = photo.bytes;
        if (bytes == null) {
          results.add(photo);
        } else {
          final path = 'listingPhotos/$userId/${listing.id}/$revisionId-$i.jpg';
          newPaths.add(path);
          final reference = _storage!.ref(path);
          final task = reference.putData(
            bytes,
            SettableMetadata(contentType: 'image/jpeg'),
          );
          final progress = task.snapshotEvents.listen((event) {
            final fraction = event.totalBytes == 0
                ? 0
                : event.bytesTransferred / event.totalBytes;
            onProgress((i + fraction) / photos.length);
          }, onError: (Object _) {});
          try {
            await task;
          } finally {
            await progress.cancel();
          }
          results.add(
            ListingPhoto.saved(path, 'gs://${reference.bucket}/$path'),
          );
        }
        onProgress((i + 1) / photos.length);
      }
      final paths = results.map((photo) => photo.path!).toList();
      final urls = results.map((photo) => photo.url!).toList();
      await db.runTransaction((transaction) async {
        final current = await transaction.get(listing);
        final data = current.data();
        if (data == null ||
            data['userId'] != userId ||
            data['status'] == 'deleting' ||
            data['revision'] != (existing?.revision ?? 0)) {
          throw StateError('Listing was changed during editing');
        }
        final retired = {
          ...List<String>.from(data['retiredPaths'] as List),
          ...List<String>.from(data['imagePaths'] as List)
              .where((path) => !paths.contains(path)),
        };
        transaction.update(listing, {
          ..._write(form),
          'operationId': revisionId,
          'revision': (data['revision'] as int) + 1,
          'status': created || data['status'] == 'draft'
              ? 'active'
              : data['status'],
          'imagePaths': paths,
          'imageUrls': urls,
          'retiredPaths': retired.toList(),
          'coverImageUrl': urls.isEmpty ? null : urls[coverIndex],
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
      committed = true;
    } catch (_) {
      // Read the server before deleting uploads when a commit acknowledgement was lost.
      try {
        final current = await listing.get(
          const GetOptions(source: Source.server),
        );
        final data = current.data();
        committed = data?['operationId'] == revisionId;
        if (!committed) {
          final linked = List<String>.from(
            data?['imagePaths'] as List? ?? const [],
          );
          await _removeFiles(newPaths.where((path) => !linked.contains(path)));
          if (created && data?['status'] == 'draft') await listing.delete();
        }
      } catch (_) {
        // The draft and its uploads remain recoverable from listing management.
      }
      if (!committed) rethrow;
    }
    try {
      final data = (await listing.get(const GetOptions(source: Source.server)))
          .data();
      final retired = List<String>.from(
        data?['retiredPaths'] as List? ?? const [],
      );
      await _removeFiles(retired);
      if (retired.isNotEmpty) {
        await listing.update({'retiredPaths': FieldValue.arrayRemove(retired)});
      }
    } catch (_) {
      // Retired paths stay on the listing for a later save or deletion.
    }
    return listing.id;
  }

  Future<void> _removeFiles(Iterable<String> paths) async {
    Object? failure;
    for (final path in paths) {
      try {
        await _storage!.ref(path).delete();
      } catch (error) {
        if (error is! FirebaseException || error.code != 'object-not-found') {
          failure ??= error;
        }
      }
    }
    if (failure != null) throw failure;
  }

  @override
  Future<void> setActive(Listing listing, bool active) =>
      db.runTransaction((transaction) async {
        final ref = _listings.doc(listing.id);
        final current = await transaction.get(ref);
        final status = current.get('status');
        if (status != 'active' && status != 'inactive')
          throw StateError('Listing unavailable');
        transaction.update(ref, {
          'status': active ? 'active' : 'inactive',
          'updatedAt': FieldValue.serverTimestamp(),
          'revision': FieldValue.increment(1),
        });
      });

  @override
  Future<void> delete(Listing listing) async {
    final ref = _listings.doc(listing.id);
    final storage = _storage;
    await db.runTransaction((transaction) async {
      final current = await transaction.get(ref);
      final data = current.data();
      if (data == null || data['userId'] != userId) {
        throw StateError('Listing unavailable');
      }
      if (storage == null &&
          ((data['imagePaths'] as List).isNotEmpty ||
              (data['retiredPaths'] as List).isNotEmpty ||
              data['status'] == 'draft')) {
        throw StateError('Listing storage bucket is missing');
      }
      if (data['status'] == 'deleting') return;
      transaction.update(ref, {
        'status': 'deleting',
        'revision': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    if (storage != null) {
      final folder = storage.ref('listingPhotos/$userId/${listing.id}');
      final objects = await folder.listAll();
      await _removeFiles(objects.items.map((item) => item.fullPath));
    }
    await ref.delete();
  }

  Future<void> report(String id, String reason) => _listings
      .doc(id)
      .collection('reports')
      .doc(userId)
      .set({'reason': reason, 'createdAt': FieldValue.serverTimestamp()});
}

String locationKey(String text) =>
    text.trim().replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

Map<String, Object?> _write(ListingForm form) => {
  'title': form.title,
  'description': form.description,
  'listingType': form.type.name,
  'city': form.city,
  'district': form.district,
  'cityKey': locationKey(form.city),
  'districtKey': locationKey(form.district),
  'neighborhood': form.neighborhood,
  'monthlyRent': form.monthlyRent,
  'deposit': form.deposit,
  'buildingFee': form.buildingFee,
  'houseType': form.houseType,
  'currentOccupants': form.currentOccupants,
  'desiredRoommates': form.desiredRoommates,
  'availableDate': Timestamp.fromDate(
    DateTime.utc(
      form.availableDate.year,
      form.availableDate.month,
      form.availableDate.day,
    ),
  ),
  'furnished': form.furnished,
  'smokingAllowed': form.smokingAllowed,
  'petsAllowed': form.petsAllowed,
  'amenities': {
    'wifi': form.wifi,
    'balcony': form.balcony,
    'heating': form.heating,
  },
};

Listing _read(DocumentSnapshot<Map<String, dynamic>> document) {
  final data = document.data()!;
  final amenities = data['amenities'] as Map;
  final urls = List<String>.from(data['imageUrls'] as List);
  final paths = List<String>.from(data['imagePaths'] as List);
  return Listing(
    id: document.id,
    userId: data['userId'] as String,
    ownerName: data['ownerName'] as String,
    status: ListingStatus.values.byName(data['status'] as String),
    revision: data['revision'] as int,
    createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    photos: [
      for (var i = 0; i < urls.length && i < paths.length; i++)
        ListingPhoto.saved(paths[i], urls[i]),
    ],
    coverUrl: data['coverImageUrl'] as String?,
    viewCount: data['viewCount'] as int,
    form: (
      title: data['title'] as String,
      description: data['description'] as String,
      type: ListingType.values.byName(data['listingType'] as String),
      city: data['city'] as String,
      district: data['district'] as String,
      neighborhood: data['neighborhood'] as String,
      monthlyRent: data['monthlyRent'] as int,
      deposit: data['deposit'] as int?,
      buildingFee: data['buildingFee'] as int?,
      houseType: data['houseType'] as String?,
      currentOccupants: data['currentOccupants'] as int?,
      desiredRoommates: data['desiredRoommates'] as int,
      availableDate: (data['availableDate'] as Timestamp).toDate().toUtc(),
      furnished: data['furnished'] as bool?,
      smokingAllowed: data['smokingAllowed'] as bool,
      petsAllowed: data['petsAllowed'] as bool,
      wifi: amenities['wifi'] as bool,
      balcony: amenities['balcony'] as bool,
      heating: amenities['heating'] as String?,
    ),
  );
}
