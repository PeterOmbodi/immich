import 'dart:async';
import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/services/foreground_upload.service.dart';
import 'package:immich_mobile/services/view_intent.service.dart';

final viewIntentUploadProvider = Provider(ViewIntentUpload.new);

class ViewIntentUpload {
  const ViewIntentUpload(this._ref);

  final Ref _ref;

  Future<void> upload({
    required FileBackedAsset asset,
    required Completer<void> cancelToken,
    required UploadCallbacks callbacks,
  }) async {
    final viewIntentService = _ref.read(viewIntentServiceProvider);
    viewIntentService.markUploadActive(asset.path);

    try {
      await _ref
          .read(foregroundUploadServiceProvider)
          .uploadShareIntent(
            [File(asset.path)],
            cancelToken: cancelToken,
            originalFileNames: {asset.path: asset.name},
            fileDates: {asset.path: (createdAt: asset.createdAt, modifiedAt: asset.updatedAt)},
            onProgress: (_, bytes, total) => callbacks.onProgress?.call(asset.id, asset.name, bytes, total),
            onSuccess: (_, remoteId) => callbacks.onSuccess?.call(asset.id, remoteId),
            onError: (_, error) => callbacks.onError?.call(asset.id, error),
          );
    } finally {
      await viewIntentService.markUploadInactive(asset.path);
    }
  }
}
