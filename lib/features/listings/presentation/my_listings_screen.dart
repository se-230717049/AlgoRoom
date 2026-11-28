import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../data/firebase_listings_repository.dart';
import '../domain/listing.dart';
import 'listing_widgets.dart';

final _myListings = StreamProvider.autoDispose<List<Listing>>((ref) async* {
  final repository = await ref.watch(listingsProvider.future);
  if (repository != null) yield* repository.watchMine();
});

class MyListingsScreen extends ConsumerStatefulWidget {
  const MyListingsScreen({super.key});

  @override
  ConsumerState<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends ConsumerState<MyListingsScreen> {
  final _pending = <String>{};

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final state = ref.watch(_myListings);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(strings.myListings),
          bottom: TabBar(
            tabs: [
              Tab(text: strings.listingActive),
              Tab(text: strings.listingInactive),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          tooltip: strings.createListing,
          onPressed: () => context.push('/account/listings/new'),
          child: const Icon(Icons.add),
        ),
        body: state.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: TextButton(
              onPressed: () => ref.invalidate(_myListings),
              child: Text('${strings.loadError} ${strings.retry}'),
            ),
          ),
          data: (items) => TabBarView(
            children: [
              _rows(
                items
                    .where((item) => item.status == ListingStatus.active)
                    .toList(),
                strings,
              ),
              _rows(
                items
                    .where((item) => item.status != ListingStatus.active)
                    .toList(),
                strings,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rows(List<Listing> items, AppLocalizations strings) {
    if (items.isEmpty) return Center(child: Text(strings.empty));
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 84),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final listing = items[index];
            final pending = _pending.contains(listing.id);
            final status = listing.status;
            return Card(
              child: ListTile(
                enabled: !pending,
                onTap: () => context.push('/account/listings/${listing.id}'),
                title: Text(listing.form.title),
                subtitle: Text(
                  [
                    '${strings.listingViews} · ${listing.viewCount}',
                    if (status == ListingStatus.draft) strings.listingDraft,
                    if (status == ListingStatus.deleting)
                      strings.listingDeleting,
                  ].join(' · '),
                ),
                trailing: pending
                    ? const CircularProgressIndicator()
                    : PopupMenuButton<String>(
                        onSelected: (action) =>
                            _change(listing, action, strings),
                        itemBuilder: (_) => [
                          if (status != ListingStatus.deleting)
                            PopupMenuItem(
                              value: 'edit',
                              child: Text(strings.editListing),
                            ),
                          if (status == ListingStatus.active)
                            PopupMenuItem(
                              value: 'inactive',
                              child: Text(strings.listingDeactivate),
                            ),
                          if (status == ListingStatus.inactive)
                            PopupMenuItem(
                              value: 'active',
                              child: Text(strings.listingReactivate),
                            ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text(strings.listingDelete),
                          ),
                        ],
                      ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _change(
    Listing listing,
    String action,
    AppLocalizations strings,
  ) async {
    if (action == 'edit') {
      context.push('/account/listings/${listing.id}/edit');
      return;
    }
    final repository = ref.read(listingsProvider).value;
    if (repository == null || _pending.contains(listing.id)) return;
    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(strings.listingDelete),
          content: Text(strings.listingDeleteConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(strings.listingDelete),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
    }
    setState(() => _pending.add(listing.id));
    try {
      if (action == 'delete') {
        await repository.delete(listing);
      } else {
        await repository.setActive(listing, action == 'active');
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(strings.listingActionFailed)));
    } finally {
      if (mounted) setState(() => _pending.remove(listing.id));
    }
  }
}
