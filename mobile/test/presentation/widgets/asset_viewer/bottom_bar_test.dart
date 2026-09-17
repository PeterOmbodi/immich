import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/enums.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/timeline.model.dart';
import 'package:immich_mobile/domain/services/timeline.service.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_mobile/presentation/actions/action.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/add_action_button.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/bottom_bar.widget.dart';
import 'package:immich_mobile/providers/asset_viewer/asset_viewer.provider.dart';
import 'package:immich_mobile/providers/asset_viewer/video_player_provider.dart';
import 'package:immich_mobile/providers/infrastructure/asset.provider.dart';
import 'package:immich_mobile/providers/infrastructure/readonly_mode.provider.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/providers/routes.provider.dart';
import 'package:immich_mobile/services/gcast.service.dart';
import 'package:immich_mobile/utils/asset_filter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:native_video_player/native_video_player.dart';

import '../../../service.mocks.dart';
import '../../../unit/factories/remote_asset_factory.dart';
import '../../../unit/presentation/presentation_context.dart';
import '../../../widget_tester_extensions.dart';

class MockNativeVideoPlayerController extends Mock implements NativeVideoPlayerController {}

class MockTimelineService extends Mock implements TimelineService {}

class TestReadOnlyModeNotifier extends ReadOnlyModeNotifier {
  @override
  bool build() => true;
}

class TestWritableModeNotifier extends ReadOnlyModeNotifier {
  @override
  bool build() => false;
}

class TestViewerNotifier extends AssetViewerStateNotifier {
  TestViewerNotifier(this.asset);

  final BaseAsset asset;

  @override
  AssetViewerState build() {
    super.build();
    return AssetViewerState(currentAsset: asset);
  }
}

void main() {
  testWidgets('shows trash controls for a trashed deep-link asset', (tester) async {
    final context = await PresentationContext.create();
    addTearDown(context.dispose);
    final asset = RemoteAssetFactory.create(ownerId: context.currentUser.id, deletedAt: DateTime(2026, 8, 4));
    final timeline = TimelineService((
      assetSource: (_, _) async => [asset],
      bucketSource: () => Stream.value(const [Bucket(assetCount: 1)]),
      origin: TimelineOrigin.deepLink,
    ));
    addTearDown(timeline.dispose);
    when(() => context.service.asset.service.watchAsset(any())).thenAnswer((_) => const Stream.empty());

    await tester.pumpTestWidget(
      context,
      const ViewerBottomBar(),
      overrides: [
        timelineServiceProvider.overrideWithValue(timeline),
        assetViewerProvider.overrideWith(() => TestViewerNotifier(asset)),
        readonlyModeProvider.overrideWith(TestWritableModeNotifier.new),
      ],
    );

    expect(find.text(StaticTranslations.instance.restore), findsOneWidget);
    expect(find.text(StaticTranslations.instance.upload), findsNothing);
    expect(find.text(StaticTranslations.instance.edit), findsNothing);
    expect(find.byType(AddActionButton), findsNothing);
  });

  testWidgets('player stays bound after local id arrives', (tester) async {
    final searchCopy = RemoteAssetFactory.create(type: .video);
    final mergedCopy = searchCopy.copyWith(localId: 'local-1', isFavorite: true);
    final assetService = MockAssetService();
    final controller = MockNativeVideoPlayerController();
    final timeline = MockTimelineService();
    final updates = StreamController<BaseAsset?>(sync: true);
    when(() => assetService.watchAsset(searchCopy)).thenAnswer((_) => updates.stream);
    when(controller.play).thenAnswer((_) async {});
    when(controller.pause).thenAnswer((_) async {});
    when(() => timeline.origin).thenReturn(.search);

    late WidgetRef ref;

    await tester.pumpConsumerWidget(
      Consumer(
        builder: (context, widgetRef, _) {
          ref = widgetRef;
          return const ViewerBottomBar();
        },
      ),
      overrides: [
        assetServiceProvider.overrideWithValue(assetService),
        assetsActionProvider(ActionSource.viewer).overrideWithValue(const AssetFilter<BaseAsset>({})),
        gCastServiceProvider.overrideWithValue(MockGCastService()),
        inLockedViewProvider.overrideWithValue(true),
        ownedAssetsActionProvider(ActionSource.viewer).overrideWithValue(const AssetFilter<RemoteAsset>({})),
        readonlyModeProvider.overrideWith(TestReadOnlyModeNotifier.new),
        timelineServiceProvider.overrideWithValue(timeline),
      ],
    );

    final viewer = ref.read(assetViewerProvider.notifier);
    viewer.setAsset(searchCopy);
    await tester.pump();
    ref.read(videoPlayerProvider(searchCopy.id).notifier).attachController(controller);
    updates.add(mergedCopy);
    await tester.pump();
    await tester.tap(find.byType(IconButton));
    await tester.pump();

    verify(controller.play).called(1);
    viewer.setShowingDetails(true);
    await tester.pump();
    verify(controller.pause).called(1);

    await tester.pumpWidget(const SizedBox.shrink());
    unawaited(updates.close());
  });
}
