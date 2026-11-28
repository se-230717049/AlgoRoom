import 'dart:typed_data';

enum ListingType { room, housemate, rentTogether }

enum ListingStatus { draft, active, inactive, deleting }

typedef ListingForm = ({
  String title,
  String description,
  ListingType type,
  String city,
  String district,
  String neighborhood,
  int monthlyRent,
  int? deposit,
  int? buildingFee,
  String? houseType,
  int? currentOccupants,
  int desiredRoommates,
  DateTime availableDate,
  bool? furnished,
  bool smokingAllowed,
  bool petsAllowed,
  bool wifi,
  bool balcony,
  String? heating,
});

class ListingPhoto {
  const ListingPhoto.saved(this.path, this.url) : bytes = null;
  const ListingPhoto.local(this.bytes) : path = null, url = null;

  final String? path;
  final String? url;
  final Uint8List? bytes;
}

class Listing {
  const Listing({
    required this.id,
    required this.userId,
    required this.ownerName,
    required this.form,
    required this.status,
    required this.photos,
    required this.coverUrl,
    required this.viewCount,
    required this.revision,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String userId;
  final String ownerName;
  final ListingForm form;
  final ListingStatus status;
  final List<ListingPhoto> photos;
  final String? coverUrl;
  final int viewCount;
  final int revision;
  final DateTime? createdAt, updatedAt;
}

int? parseListingNumber(
  String input, {
  required int minimum,
  required int maximum,
}) {
  final text = input.trim();
  if (!RegExp(r'^\d+$').hasMatch(text)) return null;
  final number = int.tryParse(text);
  if (number == null || number < minimum || number > maximum) return null;
  return number;
}

enum ListingSort { newest, lowest, highest }

class ListingSearch {
  const ListingSearch({
    this.city = '',
    this.district = '',
    this.minRent,
    this.maxRent,
    this.type,
    this.houseType,
    this.furnished,
    this.availableBy,
    this.sort = ListingSort.newest,
  });

  final String city, district;
  final int? minRent, maxRent;
  final ListingType? type;
  final String? houseType;
  final bool? furnished;
  final DateTime? availableBy;
  final ListingSort sort;

  Object get _key => (
    city,
    district,
    minRent,
    maxRent,
    type,
    houseType,
    furnished,
    availableBy,
    sort,
  );

  @override
  bool operator ==(Object other) =>
      other is ListingSearch && other._key == _key;

  @override
  int get hashCode => _key.hashCode;

  bool matches(Listing listing) {
    final form = listing.form;
    final by = availableBy;
    return (type == null || form.type == type) &&
        (houseType == null || form.houseType == houseType) &&
        (furnished == null || form.furnished == furnished) &&
        (by == null ||
            !form.availableDate.isAfter(
              DateTime.utc(by.year, by.month, by.day),
            ));
  }
}
