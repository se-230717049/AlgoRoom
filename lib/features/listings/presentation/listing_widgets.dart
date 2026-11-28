import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../data/firebase_listings_repository.dart';
import '../domain/listing.dart';

const houseTypes = ['1+1', '2+1', '3+1', '4+1', 'other'];
const heatingTypes = ['gas', 'central', 'electric', 'stove', 'other'];

final listingProvider = StreamProvider.autoDispose.family<Listing?, String>((
  ref,
  id,
) async* {
  final repository = await ref.watch(listingsProvider.future);
  if (repository != null) yield* repository.watchListing(id);
});

final listingFavoritesProvider = StreamProvider.autoDispose<Set<String>>((
  ref,
) async* {
  final repository = await ref.watch(listingsProvider.future);
  if (repository != null) yield* repository.watchFavorites();
});

String listingTypeLabel(AppLocalizations strings, ListingType type) =>
    switch (type) {
      ListingType.room => strings.listingRoom,
      ListingType.housemate => strings.listingHousemate,
      ListingType.rentTogether => strings.listingTogether,
    };

String houseTypeLabel(AppLocalizations strings, String type) =>
    type == 'other' ? strings.listingOther : type;

String heatingLabel(AppLocalizations strings, String type) => switch (type) {
  'gas' => strings.heatingGas,
  'central' => strings.heatingCentral,
  'electric' => strings.heatingElectric,
  'stove' => strings.heatingStove,
  _ => strings.listingOther,
};

String shortListingDate(BuildContext context, DateTime date) =>
    MaterialLocalizations.of(context).formatMediumDate(date);

String listingPrice(AppLocalizations strings, int amount) =>
    NumberFormat.currency(
      locale: strings.localeName,
      name: 'TRY',
      symbol: '₺',
      decimalDigits: 0,
    ).format(amount);

class ListingPageState extends StatelessWidget {
  const ListingPageState({super.key, required this.title, this.text});
  final String title;
  final String? text;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: text == null
            ? const CircularProgressIndicator()
            : Text(text!, textAlign: TextAlign.center),
      ),
    ),
  );
}

final _photoProvider = FutureProvider.autoDispose.family<Uint8List?, String>((
  ref,
  url,
) async {
  final repository = await ref.watch(listingsProvider.future);
  if (repository == null) return null;
  return repository.readPhoto(url);
}, retry: (_, _) => null);

class ListingImage extends ConsumerWidget {
  const ListingImage({super.key, this.photo, this.url});
  final ListingPhoto? photo;
  final String? url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.home_work_outlined, size: 44)),
    );
    final bytes = photo?.bytes;
    if (bytes != null) return Image.memory(bytes, fit: BoxFit.cover);
    final source = photo?.url ?? url;
    if (source == null) return placeholder;
    final remote = ref.watch(_photoProvider(source)).value;
    return remote == null
        ? placeholder
        : Image.memory(
            remote,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => placeholder,
          );
  }
}

class ListingFavoriteButton extends ConsumerStatefulWidget {
  const ListingFavoriteButton({super.key, required this.id});
  final String id;

  @override
  ConsumerState<ListingFavoriteButton> createState() =>
      _ListingFavoriteButtonState();
}

class _ListingFavoriteButtonState extends ConsumerState<ListingFavoriteButton> {
  bool _pending = false;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final favorites = ref.watch(listingFavoritesProvider).value;
    final repository = ref.watch(listingsProvider).value;
    final saved = favorites?.contains(widget.id) ?? false;
    return IconButton(
      tooltip: saved ? strings.unsaveRoom : strings.saveRoom,
      icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
      onPressed: favorites == null || repository == null || _pending
          ? null
          : () async {
              setState(() => _pending = true);
              try {
                await repository.setFavorite(widget.id, !saved);
              } catch (_) {
                if (context.mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(strings.listingActionFailed)),
                  );
              } finally {
                if (mounted) setState(() => _pending = false);
              }
            },
    );
  }
}
