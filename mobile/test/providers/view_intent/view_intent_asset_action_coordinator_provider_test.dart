import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/enums.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/timeline.model.dart';
import 'package:immich_mobile/domain/services/timeline.service.dart';
import 'package:immich_mobile/platform/view_intent_api.g.dart';
import 'package:immich_mobile/providers/asset_viewer/asset_viewer.provider.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/providers/view_intent/active_view_intent_payload_provider.dart';
import 'package:immich_mobile/providers/view_intent/view_intent_asset_action_coordinator.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:mocktail/mocktail.dart';

import '../../unit/factories/local_asset_factory.dart';
import '../../unit/factories/remote_asset_factory.dart';

class _MockAppRouter extends Mock implements AppRouter {}

class _ViewerNotifier extends AssetViewerStateNotifier {
  _ViewerNotifier(this.asset);

  final BaseAsset asset;

  @override
  AssetViewerState build() {
    super.build();
    return AssetViewerState(currentAsset: asset);
  }
}

typedef _Harness = ({ViewIntentAssetActionCoordinator coordinator, _MockAppRouter router, ProviderContainer container});

void main() {
  Future<_Harness> createHarness({required BaseAsset asset}) async {
    final timeline = TimelineService((
      assetSource: (_, _) async => [asset],
      bucketSource: () => Stream.value(const [Bucket(assetCount: 1)]),
      origin: TimelineOrigin.deepLink,
    ));
    addTearDown(timeline.dispose);

    final router = _MockAppRouter();
    when(() => router.maybePop()).thenAnswer((_) async => true);

    final container = ProviderContainer(
      overrides: [
        timelineServiceProvider.overrideWithValue(timeline),
        assetViewerProvider.overrideWith(() => _ViewerNotifier(asset)),
        appRouterProvider.overrideWithValue(router),
      ],
    );
    addTearDown(container.dispose);

    container
        .read(activeViewIntentPayloadProvider.notifier)
        .setPayload(ViewIntentPayload(path: null, mimeType: 'image/jpeg', localAssetId: asset.localId));

    return (
      coordinator: container.read(viewIntentAssetActionCoordinatorProvider),
      router: router,
      container: container,
    );
  }

  test('keeps the viewer open after a remote asset is moved to trash', () async {
    final asset = RemoteAssetFactory.create();
    final harness = await createHarness(asset: asset);

    await harness.coordinator.afterDelete(source: ActionSource.viewer, remoteAssetIds: [asset.id], movedToTrash: true);

    verifyNever(() => harness.router.maybePop());
  });

  test('closes the viewer after permanently deleting a remote asset', () async {
    final asset = RemoteAssetFactory.create(deletedAt: DateTime(2026, 8, 4));
    final harness = await createHarness(asset: asset);

    await harness.coordinator.afterDelete(source: ActionSource.viewer, remoteAssetIds: [asset.id], movedToTrash: false);

    verify(() => harness.router.maybePop()).called(1);
  });

  test('closes the viewer after deleting a local-only asset', () async {
    final asset = LocalAssetFactory.create();
    final harness = await createHarness(asset: asset);

    await harness.coordinator.afterDelete(source: ActionSource.viewer, remoteAssetIds: const [], movedToTrash: true);

    verify(() => harness.router.maybePop()).called(1);
  });

  test('does not apply a completed action to a newer view intent', () async {
    final asset = RemoteAssetFactory.create();
    final harness = await createHarness(asset: asset);
    harness.container
        .read(activeViewIntentPayloadProvider.notifier)
        .setPayload(ViewIntentPayload(path: null, mimeType: 'image/jpeg', localAssetId: 'newer-local'));

    await harness.coordinator.afterDelete(source: ActionSource.viewer, remoteAssetIds: [asset.id], movedToTrash: false);

    verifyNever(() => harness.router.maybePop());
  });

  test('ignores actions outside the view-intent viewer', () async {
    final asset = RemoteAssetFactory.create();
    final harness = await createHarness(asset: asset);

    await harness.coordinator.afterDelete(
      source: ActionSource.timeline,
      remoteAssetIds: [asset.id],
      movedToTrash: false,
    );

    verifyNever(() => harness.router.maybePop());
  });
}
