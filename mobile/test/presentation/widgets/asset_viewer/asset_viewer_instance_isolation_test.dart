import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/timeline.model.dart';
import 'package:immich_mobile/domain/services/timeline.service.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_viewer.page.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/video_viewer.widget.dart';
import 'package:immich_mobile/providers/asset_viewer/asset_viewer.provider.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/widgets/photo_view/photo_view.dart';

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

final _fileBackedImage = FileBackedAsset(
  path: 'C:/view-intent/image.jpg',
  checksum: 'file-backed-image-checksum',
  name: 'image.jpg',
  type: AssetType.image,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  playbackStyle: AssetPlaybackStyle.image,
);

final _deepLinkImage = LocalAsset(
  id: 'deep-link-image-id',
  name: 'deep-link-image.jpg',
  type: AssetType.image,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  playbackStyle: AssetPlaybackStyle.image,
  isEdited: false,
);

class _FileBackedViewerNotifier extends AssetViewerStateNotifier {
  @override
  AssetViewerState build() => AssetViewerState(currentAsset: _fileBackedVideo);
}

class _FileBackedImageViewerNotifier extends AssetViewerStateNotifier {
  @override
  AssetViewerState build() => AssetViewerState(currentAsset: _fileBackedImage);
}

class _DeepLinkImageViewerNotifier extends AssetViewerStateNotifier {
  @override
  AssetViewerState build() => AssetViewerState(currentAsset: _deepLinkImage);
}

TimelineService _timeline() => TimelineService((
  assetSource: (_, _) async => [_fileBackedVideo],
  bucketSource: () => Stream.value(const [Bucket(assetCount: 1)]),
  origin: TimelineOrigin.deepLink,
));

TimelineService _imageTimeline() => TimelineService((
  assetSource: (_, _) async => [_fileBackedImage],
  bucketSource: () => Stream.value(const [Bucket(assetCount: 1)]),
  origin: TimelineOrigin.deepLink,
));

TimelineService _deepLinkImageTimeline() => TimelineService((
  assetSource: (_, _) async => [_deepLinkImage],
  bucketSource: () => Stream.value(const [Bucket(assetCount: 1)]),
  origin: TimelineOrigin.deepLink,
));

void main() {
  late PresentationContext context;

  setUp(() async {
    context = await PresentationContext.create();
  });

  tearDown(() async {
    await context.dispose();
  });

  testWidgets('separate viewer instances do not share native video keys', (tester) async {
    final firstTimeline = _timeline();
    final secondTimeline = _timeline();
    addTearDown(firstTimeline.dispose);
    addTearDown(secondTimeline.dispose);

    Widget viewer(TimelineService timeline, int heroOffset) => Expanded(
      child: ProviderScope(
        overrides: [
          timelineServiceProvider.overrideWithValue(timeline),
          assetViewerProvider.overrideWith(_FileBackedViewerNotifier.new),
        ],
        child: AssetViewer(initialIndex: 0, heroOffset: heroOffset),
      ),
    );

    await tester.pumpTestWidget(
      context,
      Row(children: [viewer(firstTimeline, 0), viewer(secondTimeline, 1)]),
      expectSettle: false,
    );

    final exceptions = <Object>[];
    Object? exception;
    while ((exception = tester.takeException()) != null) {
      exceptions.add(exception!);
    }

    expect(exceptions.where((error) => error.toString().contains('GlobalKey')), isEmpty);
    expect(find.byType(NativeVideoViewer), findsNWidgets(2));
    expect(find.byIcon(Icons.play_circle_outline), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('a file-backed deep-link image does not create a Hero', (tester) async {
    final timeline = _imageTimeline();
    addTearDown(timeline.dispose);

    await tester.pumpTestWidget(
      context,
      const AssetViewer(initialIndex: 0),
      overrides: [
        timelineServiceProvider.overrideWithValue(timeline),
        assetViewerProvider.overrideWith(_FileBackedImageViewerNotifier.new),
      ],
      expectSettle: false,
    );

    expect(find.byType(Hero), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('explains when a file-backed image cannot be previewed', (tester) async {
    final timeline = _imageTimeline();
    addTearDown(timeline.dispose);

    await tester.pumpTestWidget(
      context,
      const AssetViewer(initialIndex: 0),
      overrides: [
        timelineServiceProvider.overrideWithValue(timeline),
        assetViewerProvider.overrideWith(_FileBackedImageViewerNotifier.new),
      ],
      expectSettle: false,
    );
    final photoViewFinder = find.byType(PhotoView);
    final photoView = tester.widget<PhotoView>(photoViewFinder);
    final errorWidget = photoView.errorBuilder!(
      tester.element(photoViewFinder),
      StateError('unsupported image'),
      StackTrace.empty,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpTestWidget(context, errorWidget, expectSettle: false);

    expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
    expect(find.text('Preview unavailable'), findsOneWidget);
    expect(find.text(_fileBackedImage.name), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('a regular deep-link image keeps its Hero', (tester) async {
    final timeline = _deepLinkImageTimeline();
    addTearDown(timeline.dispose);

    await tester.pumpTestWidget(
      context,
      const AssetViewer(initialIndex: 0),
      overrides: [
        timelineServiceProvider.overrideWithValue(timeline),
        assetViewerProvider.overrideWith(_DeepLinkImageViewerNotifier.new),
      ],
      expectSettle: false,
    );

    expect(find.byType(Hero), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
