import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_mobile/presentation/actions/action.dart';
import 'package:immich_mobile/presentation/widgets/upload_progress_dialog.widget.dart';
import 'package:immich_mobile/providers/backup/asset_upload_progress.provider.dart';
import 'package:immich_mobile/providers/infrastructure/toast.provider.dart';
import 'package:immich_mobile/providers/view_intent/view_intent_upload.provider.dart';
import 'package:immich_mobile/services/foreground_upload.service.dart';
import 'package:immich_mobile/utils/error_handler.dart';

class FileBackedUploadAction extends AssetActionBuilder {
  const FileBackedUploadAction({required super.source});

  @override
  ActionItem? create(BuildContext context, WidgetRef ref) {
    final assets = ref.watch(assetsActionProvider(source)).whereType<FileBackedAsset>().toList(growable: false);
    if (assets.length != 1) {
      return null;
    }
    final asset = assets.single;

    return .new(icon: Icons.backup_outlined, label: context.t.upload, onAction: () => _upload(context, ref, asset));
  }

  Future<void> _upload(BuildContext context, WidgetRef ref, FileBackedAsset asset) async {
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
        builder: (_) => UploadProgressDialog(assetId: asset.id),
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
