import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/infrastructure/repositories/local_asset.repository.dart';
import 'package:immich_mobile/infrastructure/repositories/remote_asset.repository.dart';
import 'package:immich_mobile/infrastructure/repositories/storage.repository.dart';
import 'package:immich_mobile/infrastructure/repositories/trash_sync.repository.dart';
import 'package:immich_mobile/repositories/local_files_manager.repository.dart';
import 'package:immich_mobile/services/app_settings.service.dart';
import 'package:logging/logging.dart';
import 'package:platform/platform.dart';

///
///     When a photo is moved to the trash on the server it should pop up a notification asking the user
///     to review out-of-sync changes. It should then allow you to sync all photo trash events or review
///     which photo trash events to sync by showing the photos in a UI similar to the main timeline where
///     you can select which photos to trash
///
///

class TrashSyncService {
  final AppSettingsService _appSettingsService;
  final RemoteAssetRepository _remoteAssetRepository;
  final DriftLocalAssetRepository _localAssetRepository;
  final LocalFilesManagerRepository _localFilesManager;
  final StorageRepository _storageRepository;
  final DriftTrashSyncRepository _trashSyncRepository;
  final Platform _platform;
  final Logger _logger = Logger('TrashService');

  TrashSyncService({
    required AppSettingsService appSettingsService,
    required RemoteAssetRepository remoteAssetRepository,
    required DriftLocalAssetRepository localAssetRepository,
    required LocalFilesManagerRepository localFilesManager,
    required StorageRepository storageRepository,
    required DriftTrashSyncRepository trashSyncRepository,
  }) : _appSettingsService = appSettingsService,
       _remoteAssetRepository = remoteAssetRepository,
       _localAssetRepository = localAssetRepository,
       _localFilesManager = localFilesManager,
       _storageRepository = storageRepository,
       _trashSyncRepository = trashSyncRepository,
       _platform = const LocalPlatform();

  Future<void> handleRemoteChanges(Iterable<({String checksum, DateTime? deletedAt})> syncItems) async {
    if (!isServiceEnabled) {
      return Future.value();
    }
    final trashedAssetsChecksums = syncItems
        .where((item) => item.deletedAt != null)
        .map((syncItem) => syncItem.checksum);
    if (trashedAssetsChecksums.isNotEmpty) {
      applyRemoteTrash(trashedAssetsChecksums, isAutoSyncMode);
    }
    final modifiedAssetsChecksums = syncItems
        .where((item) => item.deletedAt == null)
        .map((syncItem) => syncItem.checksum);
    if (modifiedAssetsChecksums.isNotEmpty) {
      await applyRemoteRestore(modifiedAssetsChecksums);
    }
  }

  Future<void> applyRemoteTrash(Iterable<String> trashedAssetsChecksums, bool allowToTrash) async {
    final localAssetsToTrash = await _localAssetRepository.getByChecksums(trashedAssetsChecksums);
    if (localAssetsToTrash.isEmpty) {
      return;
    }
    if (allowToTrash) {
      await applyRemoteTrashToLocal(localAssetsToTrash);
    } else {
      await applyRemoteTrashToReview(localAssetsToTrash);
    }
  }

  Future<void> applyRemoteTrashToLocal(List<LocalAsset> localAssetsToTrash) async {
    final mediaUrls = await Future.wait(
      localAssetsToTrash.map(
        (localAsset) => _storageRepository.getAssetEntityForAsset(localAsset).then((e) => e?.getMediaUrl()),
      ),
    );
    _logger.info("Moving to trash ${mediaUrls.join(", ")} assets");
    await _localFilesManager.moveToTrash(mediaUrls.nonNulls.toList());
  }

  Future<void> applyRemoteTrashToReview(List<LocalAsset> localAssetsToTrash) async {
    final itemsToReview = localAssetsToTrash.map((la) => (localAssetId: la.id, checksum: la.checksum ?? ''));
    return _trashSyncRepository.insertIfNotExists(itemsToReview);
  }

  Future<void> applyRemoteRestore(Iterable<String> modifiedAssetsChecksums) async {
    final remoteAssetsToRestore = await _remoteAssetRepository.getByChecksums(modifiedAssetsChecksums, isTrashed: true);
    if (isAutoSyncMode) {
      await applyRemoteRestoreToLocal(remoteAssetsToRestore);
    } else {
      await applyRemoteRestoreToReview(remoteAssetsToRestore);
    }
  }

  Future<void> applyRemoteRestoreToLocal(List<RemoteAsset> remoteAssetsToRestore) async {
    if (remoteAssetsToRestore.isEmpty) {
      return Future.value();
    }
    _logger.info("Restoring from trash ${remoteAssetsToRestore.map((e) => e.name).join(", ")} assets");
    await Future.wait(
      remoteAssetsToRestore.map((asset) => _localFilesManager.restoreFromTrash(asset.name, asset.type.index)),
    );
  }

  Future<void> applyRemoteRestoreToReview(List<RemoteAsset> remoteAssetsToRestore) async {
    ///todo

    return Future.value();
  }

  Future<int> getOutOfSyncCount() async {
    return _trashSyncRepository.getCount();
  }

  Future<void> setMoveToTrashDecision(Iterable<String> checksums, bool isApproved) async {
    await _trashSyncRepository.updateApproves(checksums, isApproved);
    if (isApproved) {
      //todo STOP!!!! 08/08
      // need to update items in timeline
      await applyRemoteTrash(checksums, true);
    }
  }

  Stream<int> watchPendingDecisionCount() => _trashSyncRepository.watchPendingDecisionCount();

  bool get isServiceEnabled => isAutoSyncMode || isReviewMode;

  bool get isAutoSyncMode =>
      _platform.isAndroid && _appSettingsService.getSetting<bool>(AppSettingsEnum.manageLocalMediaAndroid);

  bool get isReviewMode =>
      _platform.isAndroid && _appSettingsService.getSetting<bool>(AppSettingsEnum.reviewOutOfSyncChangesAndroid);
}
