import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/services/asset.service.dart';
import 'package:immich_mobile/domain/services/timeline.service.dart';
import 'package:immich_mobile/infrastructure/repositories/local_asset.repository.dart';
import 'package:immich_mobile/infrastructure/repositories/timeline.repository.dart';
import 'package:immich_mobile/models/view_intent/view_intent_payload.extension.dart';
import 'package:immich_mobile/platform/native_sync_api.g.dart';
import 'package:immich_mobile/platform/view_intent_api.g.dart';
import 'package:immich_mobile/providers/infrastructure/asset.provider.dart';
import 'package:immich_mobile/providers/infrastructure/db.provider.dart';
import 'package:immich_mobile/providers/infrastructure/platform.provider.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:logging/logging.dart';

class ViewIntentResolution {
  final BaseAsset asset;
  final TimelineService timelineService;

  const ViewIntentResolution({required this.asset, required this.timelineService});
}

final viewIntentAssetResolverProvider = Provider<ViewIntentAssetResolver>(
  (ref) => ViewIntentAssetResolver(
    localAssetRepository: ref.read(driftProvider).localAssetRepository,
    assetService: ref.read(assetServiceProvider),
    nativeSyncApi: ref.read(nativeSyncApiProvider),
    timelineFactory: ref.read(timelineFactoryProvider),
    timelineRepository: ref.read(driftProvider).timelineRepository,
    timelineUsers: () => ref.read(timelineUsersProvider.future),
  ),
);

class ViewIntentAssetResolver {
  final LocalAssetRepository _localAssetRepository;
  final AssetService _assetService;
  final NativeSyncApi _nativeSyncApi;
  final TimelineFactory _timelineFactory;
  final TimelineRepository timelineRepository;
  final Future<List<String>> Function() timelineUsers;
  static final Logger _logger = Logger('ViewIntentAssetResolver');

  const ViewIntentAssetResolver({
    required this._localAssetRepository,
    required this._assetService,
    required this._nativeSyncApi,
    required this._timelineFactory,
    required this.timelineRepository,
    required this.timelineUsers,
  });

  Future<ViewIntentResolution> resolve(ViewIntentPayload attachment) async {
    final localAssetId = attachment.localAssetId;
    final path = attachment.path;
    _logger.fine('resolve start, localAssetId=$localAssetId, path=$path, mimeType=${attachment.mimeType}');

    if (localAssetId == null && path == null) {
      throw StateError('ViewIntent resolution requires either a localAssetId or a materialized file path.');
    }

    ({LocalAsset? asset, String? checksum}) resolvedLocal = (asset: null, checksum: attachment.checksum);
    if (localAssetId != null) {
      resolvedLocal = await _resolveLocalAsset(localAssetId);
    }

    final remoteAsset = await _resolveRemoteAsset(
      localAssetId,
      remoteAssetId: resolvedLocal.asset?.remoteId,
      checksum: resolvedLocal.checksum,
    );
    if (remoteAsset != null) {
      return ViewIntentResolution(asset: remoteAsset, timelineService: _timelineFor(remoteAsset));
    }

    final BaseAsset asset;
    if (resolvedLocal.asset case final localAsset?) {
      asset = localAsset;
    } else if (localAssetId != null) {
      asset = _toTransientLocalAsset(attachment, localAssetId, resolvedLocal.checksum);
    } else {
      asset = _toFileBackedAsset(attachment);
    }

    return ViewIntentResolution(asset: asset, timelineService: _timelineFor(asset));
  }

  TimelineService _timelineFor(BaseAsset asset) => _timelineFactory.fromAssets([asset], TimelineOrigin.deepLink);

  Future<({LocalAsset? asset, String? checksum})> _resolveLocalAsset(String localAssetId) async {
    final localAsset = await _localAssetRepository.get(localAssetId);
    final checksum = localAsset?.checksum ?? await _hashLocalAsset(localAssetId);

    if (checksum == null || checksum == localAsset?.checksum) {
      return (asset: localAsset, checksum: checksum);
    }

    if (localAsset != null) {
      await _localAssetRepository.updateHashes({localAssetId: checksum});
      final resolvedAsset = await _localAssetRepository.get(localAssetId);
      return (asset: resolvedAsset ?? localAsset.copyWith(checksum: checksum), checksum: checksum);
    }

    return (asset: null, checksum: checksum);
  }

  Future<String?> _hashLocalAsset(String localAssetId) async {
    try {
      final hashResults = await _nativeSyncApi.hashAssets([localAssetId]);
      if (hashResults.isEmpty) {
        return null;
      }

      final result = hashResults.first;
      if (result.error != null) {
        _logger.warning('Failed to hash view intent local asset $localAssetId: ${result.error}');
        return null;
      }
      return result.hash;
    } catch (error, stackTrace) {
      _logger.warning('Failed to hash view intent local asset $localAssetId', error, stackTrace);
      return null;
    }
  }

  Future<RemoteAsset?> _resolveRemoteAsset(
    String? localAssetId, {
    required String? remoteAssetId,
    required String? checksum,
  }) async {
    RemoteAsset? remoteAsset;
    if (remoteAssetId != null) {
      remoteAsset = await _assetService.getRemoteAsset(remoteAssetId);
      if (remoteAsset != null) {
        _logger.fine('resolve matched remote asset by id: $remoteAssetId, asset=$remoteAsset');
      }
    }

    if (remoteAsset == null && checksum != null) {
      final candidates = await timelineRepository.getViewableRemoteAssetsByChecksum(await timelineUsers(), checksum);
      if (candidates.isNotEmpty) {
        remoteAsset = candidates.first;
        _logger.fine('resolve matched remote asset by checksum: $checksum, asset=$remoteAsset');
      }
    }

    if (remoteAsset == null || remoteAsset.isTrashed) {
      return null;
    }
    return localAssetId == null ? remoteAsset : remoteAsset.copyWith(localId: localAssetId);
  }

  LocalAsset _toTransientLocalAsset(ViewIntentPayload attachment, String localAssetId, String? checksum) {
    final now = DateTime.now();
    return LocalAsset(
      id: localAssetId,
      name: attachment.fileName,
      checksum: checksum,
      type: attachment.isVideo ? AssetType.video : AssetType.image,
      createdAt: now,
      updatedAt: now,
      isEdited: false,
      playbackStyle: attachment.playbackStyle,
    );
  }

  FileBackedAsset _toFileBackedAsset(ViewIntentPayload attachment) {
    final path = attachment.path;
    final checksum = attachment.checksum;
    if (path == null || checksum == null) {
      throw StateError('A materialized view intent requires both a path and checksum.');
    }
    //todo maybe better to use files time property
    final now = DateTime.now();
    return FileBackedAsset(
      path: path,
      name: attachment.fileName,
      checksum: checksum,
      type: attachment.isVideo ? AssetType.video : AssetType.image,
      createdAt: now,
      updatedAt: now,
      playbackStyle: attachment.playbackStyle,
    );
  }
}
