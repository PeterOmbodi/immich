import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/enums.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_mobile/presentation/actions/action.dart';
import 'package:immich_mobile/presentation/widgets/upload_progress_dialog.widget.dart';
import 'package:immich_mobile/providers/backup/asset_upload_progress.provider.dart';
import 'package:immich_mobile/providers/infrastructure/toast.provider.dart';
import 'package:immich_mobile/services/foreground_upload.service.dart';
import 'package:immich_mobile/utils/error_handler.dart';

final _stateProvider = Provider.family.autoDispose<List<LocalAsset>?, ActionSource>((ref, source) {
  final assets = ref.watch(assetsActionProvider(source));
  final local = assets.backedUp(isBackedUp: false).local().toList(growable: false);
  return local.isEmpty ? null : local;
}, dependencies: [assetsActionProvider]);

class UploadAction extends AssetActionBuilder {
  final bool showProgress;

  const UploadAction({required super.source, this.showProgress = false});

  @override
  ActionItem? create(BuildContext context, WidgetRef ref) {
    final assets = ref.watch(_stateProvider(source));
    if (assets == null) {
      return null;
    }

    return .new(icon: Icons.backup_outlined, label: context.t.upload, onAction: () => _upload(context, ref, assets));
  }

  Future<void> _upload(BuildContext context, WidgetRef ref, List<LocalAsset> assets) async {
    try {
      if (!showProgress) {
        await uploadAssets(context, ref, assets);
        return;
      }

      // The dialog is not awaited: it stays up while the upload runs and is
      // dismissed below, unless the user cancelled it themselves first
      var isDialogOpen = true;
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const UploadProgressDialog(),
        ).whenComplete(() => isDialogOpen = false),
      );

      await uploadAssets(context, ref, assets);

      if (isDialogOpen && context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    } catch (error, stack) {
      handleError(error, stack: stack, description: "Failed to upload the assets");
    }
  }
}

@visibleForTesting
Future<void> uploadAssets(BuildContext context, WidgetRef ref, List<LocalAsset> assets) async {
  final progress = ref.read(assetUploadProgressProvider.notifier);
  final uploads = ref.read(foregroundUploadServiceProvider);
  final toastService = ref.read(toastServiceProvider);
  final errorMessage = context.t.scaffold_body_error_occurred;

  final cancelToken = Completer<void>();
  ref.read(manualUploadCancelTokenProvider.notifier).state = cancelToken;

  final uploaded = <String>{};
  final failed = <String>{};
  for (final asset in assets) {
    progress.setProgress(asset.id, 0.0);
  }

  try {
    await uploads.uploadManual(
      assets,
      cancelToken: cancelToken,
      callbacks: UploadCallbacks(
        onProgress: (id, _, bytes, total) => progress.setProgress(id, total > 0 ? bytes / total : 0.0),
        onSuccess: (id, _) {
          uploaded.add(id);
          progress.remove(id);
        },
        onError: (id, _) {
          failed.add(id);
          progress.setError(id);
        },
      ),
    );
  } finally {
    ref.read(manualUploadCancelTokenProvider.notifier).state = null;
  }

  final uploadedCount = uploaded.difference(failed).length;
  if (!cancelToken.isCompleted && (uploadedCount != assets.length || failed.isNotEmpty)) {
    toastService.error(errorMessage);
  }

  unawaited(Future.delayed(const Duration(seconds: 2), progress.clear));
}
