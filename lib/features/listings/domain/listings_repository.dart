import 'listing.dart';

abstract interface class ListingsRepository {
  String get userId;
  Stream<List<Listing>> search(ListingSearch filter);
  Stream<List<Listing>> watchMine();
  Stream<Listing?> watchListing(String id);
  Stream<Set<String>> watchFavorites();
  Future<void> setFavorite(String id, bool favorite);
  Future<void> recordView(String id);
  Future<String> save(
    ListingForm form,
    List<ListingPhoto> photos,
    int coverIndex, {
    Listing? existing,
    String? createId,
    required void Function(double) onProgress,
  });
  Future<void> setActive(Listing listing, bool active);
  Future<void> delete(Listing listing);
}
