import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_mobile/providers/backup/asset_upload_progress.provider.dart';
import 'package:immich_ui/immich_ui.dart';

class UploadProgressDialog extends ConsumerWidget {
  const UploadProgressDialog({super.key, this.assetId});

  final String? assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressMap = ref.watch(assetUploadProgressProvider);
    final assetId = this.assetId;
    final values = assetId == null
        ? progressMap.values.where((value) => value >= 0).toList(growable: false)
        : [progressMap[assetId] ?? 0.0];
    final progress = values.isEmpty ? 0.0 : values.reduce((a, b) => a + b) / values.length;
    final hasError = assetId == null ? progressMap.values.any((value) => value < 0) : (progressMap[assetId] ?? 0.0) < 0;

    return AlertDialog(
      title: Text(context.t.uploading),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasError)
            const Icon(Icons.error_outline, color: Colors.red, size: 48)
          else
            CircularProgressIndicator(value: progress > 0 ? progress : null),
          const SizedBox(height: 16),
          Text(hasError ? context.t.scaffold_body_error_occurred : '${(progress * 100).toInt()}%'),
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
