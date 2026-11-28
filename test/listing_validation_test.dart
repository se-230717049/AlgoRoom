import 'package:algoroom/features/listings/domain/listing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rejects negative, fractional, malformed and out-of-range rent', () {
    int? price(String value) =>
        parseListingNumber(value, minimum: 1, maximum: 10000000);
    expect(price(' 12500 '), 12500);
    for (final input in ['', '0', '-1', '15.50', '12a', '10000001']) {
      expect(price(input), isNull, reason: input);
    }
  });

  test(
    'matches move-in cutoff and distinguishes unfurnished from unspecified',
    () {
      final listing = Listing(
        id: 'test',
        userId: 'owner',
        ownerName: 'Owner',
        status: ListingStatus.active,
        photos: const [],
        coverUrl: null,
        viewCount: 0,
        revision: 1,
        createdAt: null,
        form: (
          title: 'Room',
          description: 'Description',
          type: ListingType.room,
          city: 'Muğla',
          district: 'Menteşe',
          neighborhood: 'Kötekli',
          monthlyRent: 12000,
          deposit: null,
          buildingFee: null,
          houseType: '2+1',
          currentOccupants: 1,
          desiredRoommates: 1,
          availableDate: DateTime.utc(2027, 2, 10),
          furnished: false,
          smokingAllowed: false,
          petsAllowed: false,
          wifi: false,
          balcony: false,
          heating: null,
        ),
      );
      expect(
        ListingSearch(
          furnished: false,
          availableBy: DateTime(2027, 2, 10),
        ).matches(listing),
        isTrue,
      );
      expect(
        ListingSearch(availableBy: DateTime(2027, 2, 9)).matches(listing),
        isFalse,
      );
      expect(const ListingSearch(furnished: true).matches(listing), isFalse);
      expect(
        const ListingSearch(type: ListingType.rentTogether).matches(listing),
        isFalse,
      );
    },
  );
}
