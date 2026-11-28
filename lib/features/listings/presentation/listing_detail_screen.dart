import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../data/firebase_listings_repository.dart';
import '../data/listing_messages.dart';
import '../domain/listing.dart';
import 'listing_widgets.dart';

class ListingDetailScreen extends ConsumerStatefulWidget {
  const ListingDetailScreen({super.key, required this.listingId});
  final String listingId;

  @override
  ConsumerState<ListingDetailScreen> createState() =>
      _ListingDetailScreenState();
}

class _ListingDetailScreenState extends ConsumerState<ListingDetailScreen> {
  bool _reportedView = false;
  bool _busy = false;
  int _photo = 0;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final listing = ref.watch(listingProvider(widget.listingId));
    return listing.when(
      loading: () => ListingPageState(title: strings.listingDetail),
      error: (_, _) => ListingPageState(
        title: strings.listingDetail,
        text: strings.loadError,
      ),
      data: (value) => value == null
          ? ListingPageState(
              title: strings.listingDetail,
              text: strings.listingUnavailable,
            )
          : _details(context, strings, value),
    );
  }

  Widget _details(
    BuildContext context,
    AppLocalizations strings,
    Listing listing,
  ) {
    final repository = ref.watch(listingsProvider).value;
    final owner = repository?.userId == listing.userId;
    if (!_reportedView &&
        repository != null &&
        !owner &&
        listing.status == ListingStatus.active) {
      _reportedView = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await repository.recordView(listing.id);
        } catch (_) {
          // The count may be retried when this page is reopened.
        }
      });
    }
    final form = listing.form;
    final theme = Theme.of(context);
    final amenities = [
      if (form.houseType case final house?) houseTypeLabel(strings, house),
      if (form.furnished case final furnished?)
        furnished ? strings.listingFurnished : strings.listingUnfurnished,
      if (form.smokingAllowed) strings.listingSmoking,
      if (form.petsAllowed) strings.listingPets,
      if (form.wifi) strings.listingWifi,
      if (form.balcony) strings.listingBalcony,
      if (form.heating case final heating?) heatingLabel(strings, heating),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.listingDetail),
        actions: [if (!owner) ListingFavoriteButton(id: listing.id)],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: AspectRatio(
                    aspectRatio: 16 / 10,
                    child: listing.photos.isEmpty
                        ? const ListingImage()
                        : PageView.builder(
                            itemCount: listing.photos.length,
                            onPageChanged: (index) =>
                                setState(() => _photo = index),
                            itemBuilder: (_, index) =>
                                ListingImage(photo: listing.photos[index]),
                          ),
                  ),
                ),
                if (listing.photos.length > 1)
                  Center(child: Text('${_photo + 1}/${listing.photos.length}')),
                const SizedBox(height: 16),
                Text(listingTypeLabel(strings, form.type)),
                Text(form.title, style: theme.textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  listingPrice(strings, form.monthlyRent),
                  style: theme.textTheme.titleLarge,
                ),
                if (form.deposit case final deposit?)
                  Text(
                    '${strings.listingDeposit} · ${listingPrice(strings, deposit)}',
                  ),
                if (form.buildingFee case final fee?)
                  Text('${strings.listingFee} · ${listingPrice(strings, fee)}'),
                Text(
                  [
                    form.city,
                    form.district,
                    if (form.neighborhood.isNotEmpty) form.neighborhood,
                  ].join(' / '),
                ),
                Text(
                  '${strings.listingDate} · ${shortListingDate(context, form.availableDate)}',
                ),
                if (form.currentOccupants case final count?)
                  Text('${strings.listingOccupants} · $count'),
                Text('${strings.listingDesired} · ${form.desiredRoommates}'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final item in amenities) Chip(label: Text(item)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  strings.listingDescription,
                  style: theme.textTheme.titleMedium,
                ),
                Text(form.description),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.person_outline),
                    ),
                    title: Text(
                      listing.ownerName.isEmpty
                          ? strings.listingOwner
                          : listing.ownerName,
                    ),
                    subtitle: listing.ownerName.isEmpty
                        ? null
                        : Text(strings.listingOwner),
                  ),
                ),
                const SizedBox(height: 12),
                if (owner) ...[
                  Text('${strings.listingViews} · ${listing.viewCount}'),
                  if (listing.status != ListingStatus.deleting)
                    FilledButton(
                      onPressed: () =>
                          context.push('/account/listings/${listing.id}/edit'),
                      child: Text(strings.editListing),
                    ),
                ] else if (repository != null &&
                    listing.status == ListingStatus.active) ...[
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _action(() async {
                            final thread = await repository.openConversation(
                              listing,
                            );
                            if (context.mounted)
                              context.push('/account/listing-messages/$thread');
                          }),
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: Text(strings.listingMessage),
                  ),
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            final reason = await _reportDialog(
                              context,
                              strings,
                            );
                            if (!mounted || reason == null) return;
                            await _action(() async {
                              await repository.report(listing.id, reason);
                              if (mounted) _snack(strings.listingReported);
                            });
                          },
                    icon: const Icon(Icons.flag_outlined),
                    label: Text(strings.listingReport),
                  ),
                ],
                if (_busy) const LinearProgressIndicator(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _action(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) _snack(AppLocalizations.of(context)!.listingActionFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
}

Future<String?> _reportDialog(
  BuildContext context,
  AppLocalizations strings,
) async {
  final form = GlobalKey<FormState>();
  var reason = '';
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(strings.listingReport),
      content: Form(
        key: form,
        child: TextFormField(
          autofocus: true,
          maxLength: 500,
          maxLines: 3,
          decoration: InputDecoration(labelText: strings.listingReportReason),
          onChanged: (value) => reason = value.trim(),
          validator: (_) => reason.length < 5 ? strings.listingRequired : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () {
            if (form.currentState!.validate()) Navigator.pop(context, reason);
          },
          child: Text(strings.listingReport),
        ),
      ],
    ),
  );
}
