import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../data/firebase_listings_repository.dart';
import '../domain/listing.dart';
import 'listing_widgets.dart';

class CreateListingScreen extends ConsumerWidget {
  const CreateListingScreen({super.key, this.listingId});
  final String? listingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = listingId;
    if (id == null) return const _ListingEditor();
    final state = ref.watch(listingProvider(id));
    return state.when(
      data: (listing) =>
          listing != null &&
              listing.userId == ref.watch(listingsProvider).value?.userId &&
              listing.status != ListingStatus.deleting
          ? _ListingEditor(key: ValueKey(id), existing: listing)
          : ListingPageState(
              title: AppLocalizations.of(context)!.editListing,
              text: AppLocalizations.of(context)!.listingUnavailable,
            ),
      error: (_, _) => ListingPageState(
        title: AppLocalizations.of(context)!.editListing,
        text: AppLocalizations.of(context)!.loadError,
      ),
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}

class _ListingEditor extends ConsumerStatefulWidget {
  const _ListingEditor({super.key, this.existing});
  final Listing? existing;

  @override
  ConsumerState<_ListingEditor> createState() => _ListingEditorState();
}

enum _Field {
  title,
  description,
  city,
  district,
  neighborhood,
  rent,
  deposit,
  fee,
  occupants,
  desired,
}

class _ListingEditorState extends ConsumerState<_ListingEditor> {
  final _form = GlobalKey<FormState>();
  final _picker = ImagePicker();
  late final Map<_Field, TextEditingController> _fields;
  late ListingType _type;
  late String? _house, _heating;
  late DateTime? _date;
  late bool _furnished, _smoking, _pets, _wifi, _balcony;
  late List<ListingPhoto> _photos;
  int _cover = 0;
  bool _busy = false;
  bool _picking = false;
  double? _progress;
  String? _createId;

  @override
  void initState() {
    super.initState();
    final listing = widget.existing;
    final current = listing?.form;
    final values = {
      _Field.title: current?.title,
      _Field.description: current?.description,
      _Field.city: current?.city,
      _Field.district: current?.district,
      _Field.neighborhood: current?.neighborhood,
      _Field.rent: current?.monthlyRent,
      _Field.deposit: current?.deposit,
      _Field.fee: current?.buildingFee,
      _Field.occupants: current?.currentOccupants,
      _Field.desired: current?.desiredRoommates ?? 1,
    };
    _fields = {
      for (final field in _Field.values)
        field: TextEditingController(text: values[field]?.toString() ?? ''),
    };
    _type = current?.type ?? ListingType.room;
    _house = current?.houseType;
    _heating = current?.heating;
    _date = current?.availableDate;
    _furnished = current?.furnished ?? false;
    _smoking = current?.smokingAllowed ?? false;
    _pets = current?.petsAllowed ?? false;
    _wifi = current?.wifi ?? false;
    _balcony = current?.balcony ?? false;
    _photos = [...?listing?.photos];
    _cover = math.max(
      0,
      _photos.indexWhere((photo) => photo.url == listing?.coverUrl),
    );
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _pick(bool camera) async {
    if (_picking || _busy || _photos.length >= 10) return;
    final strings = AppLocalizations.of(context)!;
    setState(() => _picking = true);
    try {
      final files = <XFile>[];
      if (camera) {
        final picked = await _picker.pickImage(source: ImageSource.camera);
        if (picked != null) files.add(picked);
      } else {
        files.addAll(await _picker.pickMultiImage(limit: 10 - _photos.length));
      }
      var rejected = files.length > 10 - _photos.length;
      for (final file in files.take(10 - _photos.length)) {
        final bytes = await file.length() <= 15 * 1024 * 1024
            ? await compute(_compress, await file.readAsBytes())
            : null;
        if (!mounted) return;
        if (bytes == null) {
          rejected = true;
        } else {
          setState(() => _photos.add(ListingPhoto.local(bytes)));
        }
      }
      if (rejected && mounted) _message(strings.photoInvalid);
    } catch (_) {
      if (mounted) _message(strings.photoInvalid);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  String _text(_Field field) => _fields[field]!.text.trim();
  int? _number(_Field field) => int.tryParse(_text(field));

  Future<void> _save(FirebaseListingsRepository repository) async {
    if (_busy || _picking || !_form.currentState!.validate()) return;
    final strings = AppLocalizations.of(context)!;
    final date = _date;
    if (date == null) {
      _message(strings.listingRequired);
      return;
    }
    final hasHome = _type != ListingType.rentTogether;
    setState(() {
      _busy = true;
      _progress = null;
    });
    try {
      final id = await repository.save(
        (
          title: _text(_Field.title),
          description: _text(_Field.description),
          type: _type,
          city: _text(_Field.city),
          district: _text(_Field.district),
          neighborhood: hasHome ? _text(_Field.neighborhood) : '',
          monthlyRent: _number(_Field.rent)!,
          deposit: hasHome ? _number(_Field.deposit) : null,
          buildingFee: hasHome ? _number(_Field.fee) : null,
          houseType: hasHome ? _house : null,
          currentOccupants: hasHome ? _number(_Field.occupants) : null,
          desiredRoommates: _number(_Field.desired)!,
          availableDate: date,
          furnished: hasHome ? _furnished : null,
          smokingAllowed: _smoking,
          petsAllowed: _pets,
          wifi: hasHome && _wifi,
          balcony: hasHome && _balcony,
          heating: hasHome ? _heating : null,
        ),
        List.unmodifiable(_photos),
        _cover,
        existing: widget.existing,
        createId: widget.existing == null
            ? (_createId ??= repository.newListingId())
            : null,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      if (!mounted) return;
      _message(strings.listingSaved);
      context.go('/account/listings/$id');
    } catch (_) {
      if (mounted) _message(strings.listingSaveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final backend = ref.watch(listingsProvider);
    final repository = backend.value;
    final title = widget.existing == null
        ? strings.createListing
        : strings.editListing;
    if (repository == null) {
      return ListingPageState(
        title: title,
        text: backend.isLoading ? null : strings.listingUnavailable,
      );
    }
    final hasHome = _type != ListingType.rentTogether;
    final busy = _busy || _picking;
    final controls = <Widget>[
      DropdownButtonFormField<ListingType>(
        initialValue: _type,
        decoration: InputDecoration(labelText: strings.listingTypeLabel),
        items: [
          for (final type in ListingType.values)
            DropdownMenuItem(
              value: type,
              child: Text(listingTypeLabel(strings, type)),
            ),
        ],
        isExpanded: true,
        onChanged: busy ? null : (value) => setState(() => _type = value!),
      ),
      _field(_Field.title, strings.listingTitle, required: true, max: 100),
      _field(
        _Field.description,
        strings.listingDescription,
        required: true,
        max: 2000,
        lines: 4,
      ),
      _field(_Field.city, strings.listingCity, required: true, max: 70),
      _field(_Field.district, strings.listingDistrict, required: true, max: 70),
      if (hasHome)
        _field(
          _Field.neighborhood,
          strings.listingNeighborhood,
          required: true,
          max: 90,
        ),
      _field(
        _Field.rent,
        hasHome ? strings.listingRent : strings.listingBudget,
        minimum: 1,
        required: true,
      ),
      if (hasHome) ...[
        _field(_Field.deposit, strings.listingDeposit, minimum: 0),
        _field(_Field.fee, strings.listingFee, minimum: 0),
        DropdownButtonFormField<String>(
          initialValue: _house,
          decoration: InputDecoration(labelText: strings.listingHouseType),
          items: [
            for (final value in houseTypes)
              DropdownMenuItem(
                value: value,
                child: Text(houseTypeLabel(strings, value)),
              ),
          ],
          onChanged: busy ? null : (value) => setState(() => _house = value),
          validator: (value) => value == null ? strings.listingRequired : null,
        ),
        _field(
          _Field.occupants,
          strings.listingOccupants,
          minimum: 0,
          limit: 50,
          required: true,
        ),
      ],
      _field(
        _Field.desired,
        strings.listingDesired,
        minimum: 1,
        limit: 50,
        required: true,
      ),
      OutlinedButton.icon(
        icon: const Icon(Icons.calendar_today_outlined),
        label: Text(
          _date == null
              ? strings.listingDate
              : shortListingDate(context, _date!),
        ),
        onPressed: busy
            ? null
            : () async {
                final now = DateUtils.dateOnly(DateTime.now());
                final selected = await showDatePicker(
                  context: context,
                  firstDate: _date != null && _date!.isBefore(now)
                      ? _date!
                      : now,
                  lastDate: DateTime(now.year + 3, now.month, now.day),
                  initialDate: _date ?? now,
                );
                if (mounted && selected != null)
                  setState(() => _date = selected);
              },
      ),
      if (hasHome)
        _toggle(
          strings.listingFurnished,
          _furnished,
          (value) => _furnished = value,
        ),
      _toggle(strings.listingSmoking, _smoking, (value) => _smoking = value),
      _toggle(strings.listingPets, _pets, (value) => _pets = value),
      if (hasHome) ...[
        _toggle(strings.listingWifi, _wifi, (value) => _wifi = value),
        _toggle(strings.listingBalcony, _balcony, (value) => _balcony = value),
        DropdownButtonFormField<String>(
          initialValue: _heating,
          decoration: InputDecoration(labelText: strings.listingHeating),
          items: [
            for (final value in heatingTypes)
              DropdownMenuItem(
                value: value,
                child: Text(heatingLabel(strings, value)),
              ),
          ],
          onChanged: busy ? null : (value) => setState(() => _heating = value),
        ),
      ],
      Text(
        strings.listingPhotos,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      Text(
        repository.canUpload
            ? '${_photos.length}/10'
            : strings.storageUnavailable,
      ),
      if (_photos.isNotEmpty)
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _photos.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) => SizedBox(
              width: 116,
              child: Column(
                children: [
                  Expanded(
                    child: SizedBox.expand(
                      child: ListingImage(photo: _photos[index]),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        tooltip: strings.listingCover,
                        icon: Icon(
                          _cover == index ? Icons.star : Icons.star_border,
                        ),
                        onPressed: busy
                            ? null
                            : () => setState(() => _cover = index),
                      ),
                      IconButton(
                        tooltip: strings.removePhoto,
                        icon: const Icon(Icons.close),
                        onPressed: busy
                            ? null
                            : () => setState(() {
                                _photos.removeAt(index);
                                if (index == _cover) _cover = 0;
                                if (index < _cover) _cover--;
                              }),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: busy || !repository.canUpload || _photos.length >= 10
                ? null
                : () => _pick(false),
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(strings.listingGallery),
          ),
          OutlinedButton.icon(
            onPressed: busy || !repository.canUpload || _photos.length >= 10
                ? null
                : () => _pick(true),
            icon: const Icon(Icons.photo_camera_outlined),
            label: Text(strings.listingCamera),
          ),
        ],
      ),
      if (busy) LinearProgressIndicator(value: _progress),
      FilledButton(
        onPressed: busy ? null : () => _save(repository),
        child: Text(
          widget.existing == null
              ? strings.publishListing
              : strings.saveListing,
        ),
      ),
    ];
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    for (final control in controls)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: control,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    _Field key,
    String label, {
    bool required = false,
    int? minimum,
    int limit = 10000000,
    int? max,
    int lines = 1,
  }) {
    final strings = AppLocalizations.of(context)!;
    return TextFormField(
      key: ValueKey(key),
      controller: _fields[key],
      enabled: !_busy && !_picking,
      maxLines: lines,
      maxLength: max,
      keyboardType: minimum == null
          ? (lines > 1 ? TextInputType.multiline : TextInputType.text)
          : TextInputType.number,
      inputFormatters: minimum == null
          ? null
          : [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(8),
            ],
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        final text = value?.trim() ?? '';
        if (text.isEmpty) return required ? strings.listingRequired : null;
        if (minimum != null &&
            parseListingNumber(text, minimum: minimum, maximum: limit) ==
                null) {
          return strings.listingInvalidNumber;
        }
        return null;
      },
    );
  }

  Widget _toggle(String label, bool value, void Function(bool) update) =>
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: value,
        onChanged: _busy || _picking
            ? null
            : (value) => setState(() => update(value)),
      );
}

Uint8List? _compress(Uint8List bytes) {
  final decoder = image.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (decoder == null || info == null || info.width * info.height > 20000000) {
    return null;
  }
  final decoded = decoder.decodeFrame(0);
  if (decoded == null) return null;
  final upright = image.bakeOrientation(decoded);
  final resized = math.max(upright.width, upright.height) <= 1600
      ? upright
      : image.copyResize(
          upright,
          width: upright.width >= upright.height ? 1600 : null,
          height: upright.height > upright.width ? 1600 : null,
        );
  // Recreate from pixels to avoid publishing camera metadata or GPS coordinates.
  final pixels = resized.convert(format: image.Format.uint8, numChannels: 3);
  final rgb = pixels.getBytes(order: image.ChannelOrder.rgb);
  final clean = image.Image.fromBytes(
    width: pixels.width,
    height: pixels.height,
    bytes: rgb.buffer,
    bytesOffset: rgb.offsetInBytes,
    numChannels: 3,
  );
  final jpeg = image.encodeJpg(clean, quality: 78);
  return jpeg.length <= 2 * 1024 * 1024 ? jpeg : null;
}
