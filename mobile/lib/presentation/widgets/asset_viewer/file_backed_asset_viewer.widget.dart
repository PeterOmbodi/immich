import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/datetime_extensions.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_details/drag_handle.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_details/technical_details.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/sheet_tile.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/video_viewer.widget.dart';
import 'package:immich_mobile/providers/backup/asset_upload_progress.provider.dart';
import 'package:immich_mobile/providers/infrastructure/toast.provider.dart';
import 'package:immich_mobile/providers/view_intent/view_intent_upload.provider.dart';
import 'package:immich_mobile/services/foreground_upload.service.dart';
import 'package:immich_mobile/utils/error_handler.dart';
import 'package:immich_mobile/utils/timezone.dart';
import 'package:immich_ui/immich_ui.dart';

class FileBackedAssetViewer extends ConsumerWidget {
  const FileBackedAssetViewer({super.key, required this.asset, this.onUpload});

  final FileBackedAsset asset;
  final Future<void> Function()? onUpload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: _FileBackedTopAppBar(asset: asset, onInfo: () => _showInfo(context)),
      bottomNavigationBar: _FileBackedBottomBar(onUpload: () => (onUpload ?? () => _upload(context, ref))()),
      body: Center(
        child: asset.isVideo ? _FileBackedVideo(asset: asset) : _FileBackedImage(path: asset.path),
      ),
    );
  }

  Future<void> _showInfo(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _FileBackedAssetDetails(asset: asset),
    );
  }

  Future<void> _upload(BuildContext context, WidgetRef ref) async {
    final progress = ref.read(assetUploadProgressProvider.notifier);
    final toastService = ref.read(toastServiceProvider);
    final errorMessage = context.t.scaffold_body_error_occurred;
    final navigator = Navigator.of(context, rootNavigator: true);
    final cancelToken = Completer<void>();
    final cancelTokenNotifier = ref.read(manualUploadCancelTokenProvider.notifier);
    cancelTokenNotifier.state = cancelToken;
    progress.setProgress(asset.id, 0);

    var uploaded = false;
    var failed = false;
    var isDialogOpen = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _FileUploadProgressDialog(assetId: asset.id),
      ).whenComplete(() => isDialogOpen = false),
    );

    try {
      await ref
          .read(viewIntentUploadProvider)
          .upload(
            asset: asset,
            cancelToken: cancelToken,
            callbacks: UploadCallbacks(
              onProgress: (id, _, bytes, total) => progress.setProgress(id, total > 0 ? bytes / total : 0),
              onSuccess: (id, _) {
                uploaded = true;
                progress.remove(id);
              },
              onError: (id, _) {
                failed = true;
                progress.setError(id);
              },
            ),
          );

      if (!cancelToken.isCompleted && (!uploaded || failed)) {
        toastService.error(errorMessage);
      }
    } catch (error, stack) {
      handleError(error, stack: stack, description: 'Failed to upload the view-intent file');
    } finally {
      cancelTokenNotifier.state = null;
      if (isDialogOpen && navigator.mounted) {
        navigator.pop();
      }
      unawaited(Future.delayed(const Duration(seconds: 2), progress.clear));
    }
  }
}

class _FileBackedTopAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _FileBackedTopAppBar({required this.asset, required this.onInfo});

  final FileBackedAsset asset;
  final Future<void> Function() onInfo;

  @override
  Widget build(BuildContext context) {
    final originalTheme = context.themeData;

    return Stack(
      children: [
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black45, Colors.black12, Colors.transparent],
                  stops: [0.0, 0.7, 1.0],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: SizedBox(
            height: preferredSize.height,
            child: Theme(
              data: context.themeData.copyWith(iconTheme: const IconThemeData(size: 22, color: Colors.white)),
              child: NavigationToolbar(
                centerMiddle: true,
                leading: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shape: const CircleBorder(),
                    iconSize: 22,
                    iconColor: Colors.white,
                    padding: const EdgeInsets.all(10),
                    elevation: 0,
                  ),
                  onPressed: context.maybePop,
                  child: const Icon(Icons.arrow_back_rounded),
                ),
                middle: _FileBackedAssetInfoTitle(asset: asset),
                trailing: ImmichColorOverride(
                  color: Colors.white,
                  child: _FileBackedKebabMenu(originalTheme: originalTheme, onInfo: onInfo),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(60);
}

class _FileBackedAssetInfoTitle extends StatelessWidget {
  const _FileBackedAssetInfoTitle({required this.asset});

  final FileBackedAsset asset;

  @override
  Widget build(BuildContext context) {
    final alwaysUse24HourFormat = MediaQuery.alwaysUse24HourFormatOf(context);
    final (dateTime, _) = resolveAssetDateTime(asset, null);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(dateTime.formatDate(), style: context.textTheme.labelLarge?.copyWith(color: Colors.white)),
        Text(
          dateTime.formatTime(alwaysUse24HourFormat: alwaysUse24HourFormat),
          style: context.textTheme.labelMedium?.copyWith(color: Colors.white70),
        ),
      ],
    );
  }
}

class _FileBackedKebabMenu extends StatelessWidget {
  const _FileBackedKebabMenu({required this.originalTheme, required this.onInfo});

  final ThemeData originalTheme;
  final Future<void> Function() onInfo;

  @override
  Widget build(BuildContext context) {
    return ImmichMenu(
      consumeOutsideTap: true,
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(context.themeData.scaffoldBackgroundColor),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.grey),
        elevation: const WidgetStatePropertyAll(4),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
      ),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 150),
          child: Theme(
            data: originalTheme,
            child: ImmichMenuItem(icon: Icons.info_outline, label: context.t.info, onPressed: onInfo),
          ),
        ),
      ],
      builder: (context, controller, child) => IconButton(
        icon: const Icon(Icons.more_vert_rounded),
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

class _FileBackedBottomBar extends StatelessWidget {
  const _FileBackedBottomBar({required this.onUpload});

  final Future<void> Function() onUpload;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: context.themeData.copyWith(
        iconTheme: const IconThemeData(size: ImmichIconSize.md, color: Colors.white),
        textTheme: context.themeData.textTheme.copyWith(
          labelLarge: context.themeData.textTheme.labelLarge?.copyWith(color: Colors.white),
        ),
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black45, Colors.black12, Colors.transparent],
                    stops: [0.0, 0.7, 1.0],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: ImmichColorOverride(
                color: Colors.white,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ImmichColumnButton(icon: Icons.backup_outlined, label: context.t.upload, onPressed: onUpload),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FileBackedAssetDetails extends StatelessWidget {
  const _FileBackedAssetDetails({required this.asset});

  final FileBackedAsset asset;

  @override
  Widget build(BuildContext context) {
    final alwaysUse24HourFormat = MediaQuery.alwaysUse24HourFormatOf(context);
    final (dateTime, _) = resolveAssetDateTime(asset, null);
    final date = DateFormat.yMMMEd(resolvedDateTimeLocale()).format(dateTime);
    final time = dateTime.formatTime(alwaysUse24HourFormat: alwaysUse24HourFormat);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DragHandle(),
              SheetTile(title: '$date  •  $time', titleStyle: context.textTheme.labelLarge),
              TechnicalDetails(asset: asset),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileBackedImage extends StatelessWidget {
  const _FileBackedImage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 1,
      maxScale: 5,
      child: Image.file(File(path), fit: BoxFit.contain, errorBuilder: (_, _, _) => const Icon(Icons.broken_image)),
    );
  }
}

class _FileBackedVideo extends StatelessWidget {
  const _FileBackedVideo({required this.asset});

  final FileBackedAsset asset;

  @override
  Widget build(BuildContext context) {
    return NativeVideoViewer(
      asset: asset,
      isCurrent: true,
      image: const Center(child: Icon(Icons.play_circle_outline, color: Colors.white, size: 64)),
    );
  }
}

class _FileUploadProgressDialog extends ConsumerWidget {
  const _FileUploadProgressDialog({required this.assetId});

  final String assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressMap = ref.watch(assetUploadProgressProvider);
    final value = progressMap[assetId] ?? 0;
    final hasError = value < 0;

    return AlertDialog(
      title: Text(context.t.uploading),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasError)
            const Icon(Icons.error_outline, color: Colors.red, size: 48)
          else
            CircularProgressIndicator(value: value > 0 ? value : null),
          const SizedBox(height: 16),
          Text(hasError ? context.t.scaffold_body_error_occurred : '${(value * 100).toInt()}%'),
        ],
      ),
      actions: [
        ImmichTextButton(
          onPressed: () {
            ref.read(manualUploadCancelTokenProvider)?.complete();
            ref.read(manualUploadCancelTokenProvider.notifier).state = null;
            Navigator.of(context, rootNavigator: true).pop();
          },
          labelText: context.t.cancel,
        ),
      ],
    );
  }
}
