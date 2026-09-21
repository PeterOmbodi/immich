import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/platform/view_intent_api.g.dart';
import 'package:path/path.dart';

final _trailingDotsPattern = RegExp(r'\.+$');
final _fileExtensionPattern = RegExp(r'^\.(?=[A-Za-z0-9]{1,5}$)(?=.*[A-Za-z])[A-Za-z0-9]+$');

extension ViewIntentPayloadX on ViewIntentPayload {
  String get fileName {
    final resolvedPath = path;
    final resolvedDisplayName = displayName;
    if (resolvedDisplayName != null && resolvedDisplayName.isNotEmpty) {
      final sanitizedName = basename(resolvedDisplayName.replaceAll('\\', '/')).replaceFirst(_trailingDotsPattern, '');
      if (sanitizedName.isNotEmpty) {
        final backingExtension = resolvedPath == null ? '' : extension(resolvedPath);
        if (backingExtension.isEmpty || backingExtension.toLowerCase() == '.tmp') {
          return sanitizedName;
        }

        final ownExtension = extension(sanitizedName);
        final looksLikeExtension = _fileExtensionPattern.hasMatch(ownExtension);
        return looksLikeExtension ? sanitizedName : '$sanitizedName$backingExtension';
      }
    }

    if (resolvedPath != null && resolvedPath.isNotEmpty) {
      return basename(resolvedPath);
    }
    return localAssetId ?? 'view_intent_asset';
  }

  bool get isImage => mimeType.toLowerCase().startsWith('image/');

  bool get isVideo => mimeType.toLowerCase().startsWith('video/');

  AssetPlaybackStyle get playbackStyle {
    if (isVideo) {
      return AssetPlaybackStyle.video;
    }

    final normalizedMimeType = mimeType.toLowerCase();
    if (normalizedMimeType == 'image/gif' || normalizedMimeType == 'image/webp') {
      return AssetPlaybackStyle.imageAnimated;
    }

    final normalizedPath = path?.toLowerCase();
    if (normalizedPath != null && (normalizedPath.endsWith('.gif') || normalizedPath.endsWith('.webp'))) {
      return AssetPlaybackStyle.imageAnimated;
    }

    return AssetPlaybackStyle.image;
  }
}
