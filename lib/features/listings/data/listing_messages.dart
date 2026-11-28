import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/listing.dart';
import 'firebase_listings_repository.dart';

typedef ListingThread = ({String id, String title, DateTime? updatedAt});
typedef ListingMessage = ({String userId, String body});

final listingInboxProvider = StreamProvider.autoDispose<List<ListingThread>>((
  ref,
) async* {
  final repository = await ref.watch(listingsProvider.future);
  if (repository != null) yield* repository.watchThreads();
});

final listingMessagesProvider = StreamProvider.autoDispose
    .family<List<ListingMessage>, String>((ref, id) async* {
      final repository = await ref.watch(listingsProvider.future);
      if (repository != null) yield* repository.watchMessages(id);
    });

extension ListingMessages on FirebaseListingsRepository {
  CollectionReference<Map<String, dynamic>> get _threads =>
      db.collection('listingThreads');

  Future<String> openConversation(Listing listing) async {
    if (listing.userId == userId || listing.status != ListingStatus.active) {
      throw StateError('Listing cannot receive a new conversation');
    }
    final id = '${listing.id}_$userId';
    await _threads.doc(id).set({
      'listingId': listing.id,
      'listingTitle': listing.form.title,
      'ownerId': listing.userId,
      'buyerId': userId,
      'participants': [listing.userId, userId],
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return id;
  }

  Stream<List<ListingThread>> watchThreads() => _threads
      .where('participants', arrayContains: userId)
      .orderBy('updatedAt', descending: true)
      .limit(100)
      .snapshots()
      .map(
        (snapshot) => [
          for (final doc in snapshot.docs)
            (
              id: doc.id,
              title: doc.get('listingTitle') as String,
              updatedAt: (doc.data()['updatedAt'] as Timestamp?)?.toDate(),
            ),
        ],
      );

  Stream<List<ListingMessage>> watchMessages(String id) => _threads
      .doc(id)
      .collection('messages')
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map(
        (snapshot) => [
          for (final doc in snapshot.docs)
            (
              userId: doc.get('userId') as String,
              body: doc.get('body') as String,
            ),
        ],
      );

  Future<void> sendMessage(String id, String body) async {
    final thread = _threads.doc(id);
    final batch = db.batch();
    batch.set(thread.collection('messages').doc(), {
      'userId': userId,
      'body': body,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(thread, {'updatedAt': FieldValue.serverTimestamp()});
    await batch.commit();
  }
}
