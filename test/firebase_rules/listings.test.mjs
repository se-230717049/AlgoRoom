import { after, before, test } from 'node:test';
import { readFileSync } from 'node:fs';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { deleteDoc, doc, getDoc, serverTimestamp, setDoc, updateDoc, writeBatch, Timestamp } from 'firebase/firestore';
import { deleteObject, getBytes, ref, uploadBytes } from 'firebase/storage';

let env;
const owner = 'seller';
const buyer = 'buyer';
const listing = (context, id) => doc(context.firestore(), 'listings', id);
const fresh = (id) => ({
  id, userId: owner, ownerName: 'Seller', title: 'Test listing',
  description: 'Test listing description', listingType: 'room',
  city: 'Muğla', district: 'Menteşe', cityKey: 'muğla', districtKey: 'menteşe',
  neighborhood: 'Kötekli', monthlyRent: 8000, deposit: null, buildingFee: null,
  houseType: '2+1', currentOccupants: 1, desiredRoommates: 1,
  availableDate: Timestamp.fromDate(new Date('2027-01-01T00:00:00Z')),
  furnished: true, smokingAllowed: false, petsAllowed: false,
  amenities: { wifi: true, balcony: false, heating: 'gas' },
  imagePaths: [], imageUrls: [], coverImageUrl: null, retiredPaths: [],
  createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  status: 'draft', revision: 0, viewCount: 0,
});
const activate = (target) => updateDoc(target, {
  status: 'active', revision: 1, updatedAt: serverTimestamp(),
});
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-algoroom',
    firestore: { rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8') },
    storage: { rules: readFileSync(new URL('../../storage.rules', import.meta.url), 'utf8') },
  });
});
after(async () => { await env?.cleanup(); });

test('owner creates, edits, pauses, republishes and deletes a listing', async () => {
  const id = 'listingLifecycle';
  const seller = env.authenticatedContext(owner);
  const other = env.authenticatedContext(buyer);
  const guest = env.unauthenticatedContext();
  const target = listing(seller, id);
  await assertFails(setDoc(listing(guest, id), fresh(id)));
  await assertFails(setDoc(listing(other, id), fresh(id)));
  await assertSucceeds(setDoc(target, fresh(id)));
  await assertFails(getDoc(listing(other, id)));
  await assertSucceeds(activate(target));
  await assertSucceeds(getDoc(listing(other, id)));
  await assertFails(getDoc(listing(guest, id)));
  await assertFails(updateDoc(listing(other, id), { title: 'Different', revision: 2, updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(target, { userId: buyer, revision: 2, updatedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(target, { title: 'Edited', revision: 2, updatedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(target, { status: 'inactive', revision: 3, updatedAt: serverTimestamp() }));
  await assertFails(getDoc(listing(other, id)));
  await assertSucceeds(getDoc(target));
  await assertSucceeds(updateDoc(target, { status: 'active', revision: 4, updatedAt: serverTimestamp() }));
  await assertFails(deleteDoc(listing(other, id)));
  await assertSucceeds(updateDoc(target, { status: 'deleting', revision: 5, updatedAt: serverTimestamp() }));
  await assertSucceeds(deleteDoc(target));
});

test('authenticates photo upload, validates MIME and size, and hides inactive photos', async () => {
  const id = 'listingPhotos';
  const seller = env.authenticatedContext(owner);
  const other = env.authenticatedContext(buyer);
  const guest = env.unauthenticatedContext();
  const target = listing(seller, id);
  await assertSucceeds(setDoc(target, fresh(id)));
  const path = `listingPhotos/${owner}/${id}/revision1-0.jpg`;
  const sellerPhoto = ref(seller.storage(), path);
  const otherPhoto = ref(other.storage(), path);
  const metadata = { contentType: 'image/jpeg' };
  const data = new Uint8Array([255, 216, 255, 217]);
  await assertFails(uploadBytes(otherPhoto, data, metadata));
  await assertFails(uploadBytes(sellerPhoto, data, { contentType: 'text/plain' }));
  await assertFails(uploadBytes(sellerPhoto, new Uint8Array(2097153), metadata));
  await assertSucceeds(uploadBytes(sellerPhoto, data, metadata));
  await assertFails(getBytes(otherPhoto, 16));
  const url = `gs://${sellerPhoto.bucket}/${path}`;
  await assertSucceeds(updateDoc(target, {
    status: 'active', revision: 1, updatedAt: serverTimestamp(),
    imagePaths: [path], imageUrls: [url], coverImageUrl: url,
  }));
  await assertSucceeds(getBytes(otherPhoto, 16));
  await assertFails(getBytes(ref(guest.storage(), path), 16));
  await assertFails(deleteObject(otherPhoto));
  await assertSucceeds(updateDoc(target, { status: 'inactive', revision: 2, updatedAt: serverTimestamp() }));
  await assertFails(getBytes(otherPhoto, 16));
  await assertSucceeds(deleteObject(sellerPhoto));
});

test('counts one view per non-owner with an atomic receipt', async () => {
  const id = 'listingViews';
  const seller = env.authenticatedContext(owner);
  const other = env.authenticatedContext(buyer);
  const target = listing(seller, id);
  await assertSucceeds(setDoc(target, fresh(id)));
  await assertSucceeds(activate(target));
  const otherTarget = listing(other, id);
  const receipt = doc(otherTarget, 'views', buyer);
  await assertFails(updateDoc(otherTarget, { viewCount: 1 }));
  const batch = writeBatch(other.firestore());
  batch.set(receipt, { createdAt: serverTimestamp() });
  batch.update(otherTarget, { viewCount: 1 });
  await assertSucceeds(batch.commit());
  const repeated = writeBatch(other.firestore());
  repeated.set(receipt, { createdAt: serverTimestamp() });
  repeated.update(otherTarget, { viewCount: 2 });
  await assertFails(repeated.commit());
});

test('restricts conversations to the buyer and listing owner', async () => {
  const id = 'listingThread';
  const seller = env.authenticatedContext(owner);
  const other = env.authenticatedContext(buyer);
  const stranger = env.authenticatedContext('stranger');
  const target = listing(seller, id);
  await assertSucceeds(setDoc(target, fresh(id)));
  await assertSucceeds(activate(target));
  const thread = doc(other.firestore(), 'listingThreads', `${id}_${buyer}`);
  const message = doc(thread, 'messages', 'message1');
  await assertSucceeds(setDoc(thread, {
    listingId: id, listingTitle: 'Test listing', ownerId: owner, buyerId: buyer,
    participants: [owner, buyer], updatedAt: serverTimestamp(),
  }));
  await assertSucceeds(setDoc(message, { userId: buyer, body: 'Hello', createdAt: serverTimestamp() }));
  await assertFails(getDoc(doc(stranger.firestore(), message.path)));
  await assertSucceeds(getDoc(doc(seller.firestore(), message.path)));
});
