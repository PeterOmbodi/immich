part of 'base_asset.model.dart';

/// A readable file that has no [LocalAsset] representation.
class FileBackedAsset extends BaseAsset {
  final String path;
  final String _checksum;
  @override
  final AssetPlaybackStyle playbackStyle;

  const FileBackedAsset({
    required this.path,
    required String checksum,
    required super.name,
    required super.type,
    required super.createdAt,
    required super.updatedAt,
    super.width,
    super.height,
    super.durationMs,
    this.playbackStyle = AssetPlaybackStyle.unknown,
  }) : _checksum = checksum,
       super(checksum: checksum, isEdited: false);

  @override
  String get checksum => _checksum;

  @override
  String get id => checksum;

  @override
  String? get localId => null;

  @override
  String? get remoteId => null;

  @override
  AssetState get storage => AssetState.fileBacked;

  @override
  String get heroTag => 'file_$checksum';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileBackedAsset &&
          super == other &&
          path == other.path &&
          checksum == other.checksum &&
          playbackStyle == other.playbackStyle;

  @override
  int get hashCode => Object.hash(super.hashCode, path, checksum, playbackStyle);
}
