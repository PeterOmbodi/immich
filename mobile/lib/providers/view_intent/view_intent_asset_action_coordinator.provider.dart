import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/enums.dart';
import 'package:immich_mobile/domain/services/timeline.service.dart';
import 'package:immich_mobile/platform/view_intent_api.g.dart';
import 'package:immich_mobile/providers/asset_viewer/asset_viewer.provider.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/providers/view_intent/active_view_intent_payload_provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:logging/logging.dart';

final viewIntentAssetActionCoordinatorProvider = Provider(
  (ref) => ViewIntentAssetActionCoordinator(ref, viewIntent: ref.watch(activeViewIntentPayloadProvider)),
  dependencies: [assetViewerProvider, timelineServiceProvider, activeViewIntentPayloadProvider],
);

class ViewIntentAssetActionCoordinator {
  const ViewIntentAssetActionCoordinator(this._ref, {required this._viewIntent});

  final Ref _ref;
  final ViewIntentPayload? _viewIntent;
  static final Logger _logger = Logger('ViewIntentAssetActionCoordinator');

  Future<void> afterDelete({
    required ActionSource source,
    required List<String> remoteAssetIds,
    required bool movedToTrash,
  }) => _runBestEffort('post-delete view intent transition', () async {
    if (!_isActiveViewIntent(source) || remoteAssetIds.length > 1) {
      return;
    }

    if (remoteAssetIds case [_]) {
      if (!movedToTrash) {
        await _ref.read(appRouterProvider).maybePop();
      }
      return;
    }

    final asset = _ref.read(assetViewerProvider).currentAsset;
    if (asset != null && !asset.hasRemote) {
      await _ref.read(appRouterProvider).maybePop();
    }
  });

  bool _isActiveViewIntent(ActionSource source) {
    if (source != ActionSource.viewer || _viewIntent == null) {
      return false;
    }

    if (!identical(_ref.read(activeViewIntentPayloadProvider), _viewIntent)) {
      return false;
    }

    if (_ref.read(timelineServiceProvider).origin != TimelineOrigin.deepLink) {
      return false;
    }

    return true;
  }

  Future<void> _runBestEffort(String operation, Future<void> Function() transition) async {
    try {
      await transition();
    } catch (error, stackTrace) {
      _logger.warning('Failed to complete $operation', error, stackTrace);
    }
  }
}
