import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../data/firebase_listings_repository.dart';
import '../domain/listing.dart';
import 'listing_widgets.dart';

final _feedProvider = StreamProvider.autoDispose
    .family<List<Listing>, ListingSearch>((ref, filter) async* {
      final repository = await ref.watch(listingsProvider.future);
      if (repository != null) yield* repository.search(filter);
    });

class ListingsFeed extends ConsumerStatefulWidget {
  const ListingsFeed({super.key, this.favoritesOnly = false});
  final bool favoritesOnly;

  @override
  ConsumerState<ListingsFeed> createState() => _ListingsFeedState();
}

class _ListingsFeedState extends ConsumerState<ListingsFeed> {
  ListingSearch _filter = const ListingSearch();

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final state = ref.watch(_feedProvider(_filter));
    final saved = widget.favoritesOnly
        ? ref.watch(listingFavoritesProvider).value
        : null;
    return Column(
      children: [
        if (!widget.favoritesOnly)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              icon: const Icon(Icons.tune),
              label: Text(strings.listingFilters),
              onPressed: () async {
                final filter = await showDialog<ListingSearch>(
                  context: context,
                  builder: (_) => _FilterDialog(initial: _filter),
                );
                if (mounted && filter != null) setState(() => _filter = filter);
              },
            ),
          ),
        Expanded(
          child: state.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(strings.loadError),
                  TextButton(
                    onPressed: () => ref.invalidate(_feedProvider(_filter)),
                    child: Text(strings.retry),
                  ),
                ],
              ),
            ),
            data: (items) {
              final rows = widget.favoritesOnly
                  ? items
                        .where(
                          (listing) => saved?.contains(listing.id) ?? false,
                        )
                        .toList()
                  : items;
              if (rows.isEmpty) return Center(child: Text(strings.empty));
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final listing = rows[index];
                  final form = listing.form;
                  return Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () =>
                          context.push('/account/listings/${listing.id}'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(24),
                            ),
                            child: SizedBox(
                              height: 155,
                              child: ListingImage(url: listing.coverUrl),
                            ),
                          ),
                          ListTile(
                            title: Text(form.title),
                            subtitle: Text(
                              [
                                listingPrice(strings, form.monthlyRent),
                                '${form.city} / ${form.district}',
                                ?(form.houseType == null
                                    ? null
                                    : houseTypeLabel(strings, form.houseType!)),
                                listingTypeLabel(strings, form.type),
                                if (listing.ownerName.isNotEmpty)
                                  listing.ownerName,
                              ].join(' · '),
                            ),
                            trailing: ListingFavoriteButton(id: listing.id),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FilterDialog extends StatefulWidget {
  const _FilterDialog({required this.initial});
  final ListingSearch initial;

  @override
  State<_FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<_FilterDialog> {
  late final TextEditingController _city, _district, _min, _max;
  late ListingType? _type;
  late String? _house;
  late bool? _furnished;
  late DateTime? _date;
  late ListingSort _sort;
  final _form = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final filter = widget.initial;
    _city = TextEditingController(text: filter.city);
    _district = TextEditingController(text: filter.district);
    _min = TextEditingController(text: filter.minRent?.toString());
    _max = TextEditingController(text: filter.maxRent?.toString());
    _type = filter.type;
    _house = filter.houseType;
    _furnished = filter.furnished;
    _date = filter.availableBy;
    _sort = filter.sort;
  }

  @override
  void dispose() {
    for (final control in [_city, _district, _min, _max]) {
      control.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final all = strings.listingAll;
    Widget price(TextEditingController controller, String label) =>
        TextFormField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: label),
          validator: (value) {
            final text = value?.trim() ?? '';
            if (text.isEmpty) return null;
            if (parseListingNumber(text, minimum: 0, maximum: 10000000) == null)
              return strings.listingInvalidNumber;
            final min = int.tryParse(_min.text.trim());
            final max = int.tryParse(_max.text.trim());
            return min != null && max != null && min > max
                ? strings.listingInvalidRange
                : null;
          },
        );
    return AlertDialog(
      title: Text(strings.listingFilters),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _city,
                decoration: InputDecoration(labelText: strings.listingCity),
              ),
              TextFormField(
                controller: _district,
                decoration: InputDecoration(labelText: strings.listingDistrict),
              ),
              price(_min, strings.listingMinRent),
              price(_max, strings.listingMaxRent),
              DropdownButtonFormField<String>(
                initialValue: _type?.name ?? '',
                decoration: InputDecoration(
                  labelText: strings.listingTypeLabel,
                ),
                isExpanded: true,
                items: [
                  DropdownMenuItem(value: '', child: Text(all)),
                  for (final type in ListingType.values)
                    DropdownMenuItem(
                      value: type.name,
                      child: Text(listingTypeLabel(strings, type)),
                    ),
                ],
                onChanged: (value) => setState(
                  () => _type = value == ''
                      ? null
                      : ListingType.values.byName(value!),
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: _house ?? '',
                decoration: InputDecoration(
                  labelText: strings.listingHouseType,
                ),
                items: [
                  DropdownMenuItem(value: '', child: Text(all)),
                  for (final type in houseTypes)
                    DropdownMenuItem(
                      value: type,
                      child: Text(houseTypeLabel(strings, type)),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _house = value == '' ? null : value),
              ),
              DropdownButtonFormField<String>(
                initialValue: _furnished?.toString() ?? '',
                decoration: InputDecoration(
                  labelText: strings.listingFurnishing,
                ),
                items: [
                  DropdownMenuItem(value: '', child: Text(all)),
                  DropdownMenuItem(
                    value: 'true',
                    child: Text(strings.listingFurnished),
                  ),
                  DropdownMenuItem(
                    value: 'false',
                    child: Text(strings.listingUnfurnished),
                  ),
                ],
                onChanged: (value) => setState(
                  () => _furnished = value == '' ? null : value == 'true',
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.date_range),
                label: Text(
                  _date == null
                      ? strings.listingAvailableBy
                      : shortListingDate(context, _date!),
                ),
                onPressed: () async {
                  final now = DateUtils.dateOnly(DateTime.now());
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _date ?? now,
                    firstDate: now,
                    lastDate: DateTime(now.year + 3, now.month, now.day),
                  );
                  if (mounted && date != null) setState(() => _date = date);
                },
              ),
              DropdownButtonFormField<ListingSort>(
                initialValue: _sort,
                decoration: InputDecoration(
                  labelText: strings.listingSortLabel,
                ),
                items: [
                  DropdownMenuItem(
                    value: ListingSort.newest,
                    child: Text(strings.listingNewest),
                  ),
                  DropdownMenuItem(
                    value: ListingSort.lowest,
                    child: Text(strings.listingLowest),
                  ),
                  DropdownMenuItem(
                    value: ListingSort.highest,
                    child: Text(strings.listingHighest),
                  ),
                ],
                onChanged: (value) => setState(() => _sort = value!),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, const ListingSearch()),
          child: Text(strings.listingReset),
        ),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(
              context,
              ListingSearch(
                city: _city.text.trim(),
                district: _district.text.trim(),
                minRent: int.tryParse(_min.text.trim()),
                maxRent: int.tryParse(_max.text.trim()),
                type: _type,
                houseType: _house,
                furnished: _furnished,
                availableBy: _date,
                sort: _sort,
              ),
            );
          },
          child: Text(strings.listingApply),
        ),
      ],
    );
  }
}
