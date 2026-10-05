import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/services/timeline.service.dart';
import 'package:immich_mobile/presentation/actions/action.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/bottom_bar.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/ocr_toggle_button.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/viewer_kebab_menu.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/viewer_top_app_bar.widget.dart';
import 'package:immich_mobile/providers/asset_viewer/asset_viewer.provider.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/widgets/asset_viewer/video_controls.dart';
import 'package:immich_ui/immich_ui.dart';
import 'package:mocktail/mocktail.dart';

import '../../../unit/presentation/presentation_context.dart';

final _fileBackedVideo = FileBackedAsset(
  path: 'C:/view-intent/video.mp4',
  checksum: 'file-backed-video-checksum',
  name: 'video.mp4',
  type: AssetType.video,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  playbackStyle: AssetPlaybackStyle.video,
);

class _FileBackedViewerNotifier extends AssetViewerStateNotifier {
  @override
  AssetViewerState build() => AssetViewerState(currentAsset: _fileBackedVideo);
}

class _MockTimelineService extends Mock implements TimelineService {}

void main() {
  late PresentationContext context;
  late _MockTimelineService timeline;

  setUp(() async {
    context = await PresentationContext.create();
    timeline = _MockTimelineService();
    when(() => timeline.origin).thenReturn(TimelineOrigin.deepLink);
    when(() => context.service.asset.service.watchExif(_fileBackedVideo)).thenAnswer((_) => Stream.value(null));
  });

  tearDown(() async {
    await context.dispose();
  });

  testWidgets('uses standard viewer chrome without identity-dependent actions', (tester) async {
    await tester.pumpTestWidget(
      context,
      const Column(
        children: [
          SizedBox(height: 60, child: ViewerTopAppBar()),
          Spacer(),
          ViewerBottomBar(),
        ],
      ),
      overrides: [
        assetViewerProvider.overrideWith(_FileBackedViewerNotifier.new),
        timelineServiceProvider.overrideWithValue(timeline),
      ],
      expectSettle: false,
    );

    expect(find.byType(ViewerTopAppBar), findsOneWidget);
    expect(find.byType(ViewerBottomBar), findsOneWidget);
    expect(find.byType(VideoControls), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.byIcon(Icons.backup_outlined), findsOneWidget);

    expect(find.byType(ActionIconButton), findsNothing);
    expect(find.byType(ViewerKebabMenu), findsNothing);
    expect(find.byType(ImmichColumnButton), findsOneWidget);
    expect(find.byType(OcrToggleButton), findsNothing);
  });
}
