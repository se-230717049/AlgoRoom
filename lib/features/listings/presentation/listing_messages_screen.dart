import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../data/firebase_listings_repository.dart';
import '../data/listing_messages.dart';

class ListingInboxScreen extends ConsumerWidget {
  const ListingInboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(strings.listingInbox)),
      body: ref
          .watch(listingInboxProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(
              child: TextButton(
                onPressed: () => ref.invalidate(listingInboxProvider),
                child: Text('${strings.loadError} ${strings.retry}'),
              ),
            ),
            data: (threads) => threads.isEmpty
                ? Center(child: Text(strings.empty))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: threads.length,
                    itemBuilder: (context, index) {
                      final thread = threads[index];
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.chat_bubble_outline),
                          title: Text(thread.title),
                          onTap: () => context.push(
                            '/account/listing-messages/${thread.id}',
                          ),
                        ),
                      );
                    },
                  ),
          ),
    );
  }
}

class ListingMessagesScreen extends ConsumerStatefulWidget {
  const ListingMessagesScreen({super.key, required this.threadId});
  final String threadId;

  @override
  ConsumerState<ListingMessagesScreen> createState() =>
      _ListingMessagesScreenState();
}

class _ListingMessagesScreenState extends ConsumerState<ListingMessagesScreen> {
  final _draft = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _send(
    FirebaseListingsRepository repository,
    AppLocalizations strings,
  ) async {
    final body = _draft.text.trim();
    if (body.isEmpty || body.length > 1000 || _busy) return;
    setState(() => _busy = true);
    try {
      await repository.sendMessage(widget.threadId, body);
      if (mounted) _draft.clear();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(strings.listingActionFailed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final repository = ref.watch(listingsProvider).value;
    final state = ref.watch(listingMessagesProvider(widget.threadId));
    final palette = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(strings.listingInbox)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                Expanded(
                  child: state.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, _) => Center(child: Text(strings.loadError)),
                    data: (messages) => messages.isEmpty
                        ? Center(child: Text(strings.empty))
                        : ListView.builder(
                            reverse: true,
                            padding: const EdgeInsets.all(12),
                            itemCount: messages.length,
                            itemBuilder: (context, index) {
                              final item = messages[index];
                              final own = item.userId == repository?.userId;
                              return Align(
                                alignment: own
                                    ? AlignmentDirectional.centerEnd
                                    : AlignmentDirectional.centerStart,
                                child: Card(
                                  color: own
                                      ? palette.primaryContainer
                                      : palette.surfaceContainerHighest,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(
                                      item.body,
                                      style: TextStyle(
                                        color: own
                                            ? palette.onPrimaryContainer
                                            : palette.onSurface,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
                if (repository != null && state.hasValue)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _draft,
                            enabled: !_busy,
                            maxLength: 1000,
                            decoration: InputDecoration(
                              labelText: strings.listingMessageText,
                              counterText: '',
                            ),
                            onSubmitted: (_) => _send(repository, strings),
                          ),
                        ),
                        IconButton(
                          tooltip: strings.listingSend,
                          icon: const Icon(Icons.send),
                          onPressed: _busy
                              ? null
                              : () => _send(repository, strings),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
