import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_golden_animation/flutter_golden_animation.dart';
import 'package:neo_fade_ui/neo_fade_ui.dart';

/// Wraps a widget in NeoFadeTheme + MaterialApp + RepaintBoundary for testing.
Widget wrapWithTheme(Widget child) {
  return NeoFadeTheme(
    data: NeoFadeThemeData.dark(
      primary: const Color(0xFF6366F1),
      secondary: const Color(0xFF8B5CF6),
      tertiary: const Color(0xFFEC4899),
    ),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(400, 800)),
        child: RepaintBoundary(child: child),
      ),
    ),
  );
}

void main() {
  setupGoldenAnimationCompare();

  testWidgets('NeoCircularProgressIndicator spinning animation',
      (tester) async {
    await tester.pumpWidget(
      wrapWithTheme(
        const Center(
          child: SizedBox(
            width: 80,
            height: 80,
            child: Center(
              child: NeoCircularProgressIndicator(
                size: 60,
                strokeWidth: 5,
                showGlow: true,
              ),
            ),
          ),
        ),
      ),
    );

    final recorder = AnimationRecorder(tester);

    // Record one full rotation cycle (1500ms)
    await recorder.record(
      duration: const Duration(milliseconds: 1500),
      frameRate: 15,
    );

    await recorder.compareWithGolden(
      'goldens/neo_circular_progress_spinner.apng',
    );
  });

  testWidgets('NeoBottomNavCTA idle floating animation', (tester) async {
    await tester.pumpWidget(
      wrapWithTheme(
        Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: 400,
            height: 120,
            child: NeoBottomNavCTA(
              selectedIndex: 0,
              onIndexChanged: (_) {},
              items: const [
                NeoBottomNavItem(
                  label: 'Home',
                  icon: IconData(0xe88a, fontFamily: 'MaterialIcons'),
                ),
                NeoBottomNavItem(
                  label: 'Search',
                  icon: IconData(0xe8b6, fontFamily: 'MaterialIcons'),
                ),
                NeoBottomNavItem(
                  label: 'Profile',
                  icon: IconData(0xe7fd, fontFamily: 'MaterialIcons'),
                ),
              ],
              centerIcon:
                  const IconData(0xe3b0, fontFamily: 'MaterialIcons'),
              onCenterPressed: () {},
              animated: true,
            ),
          ),
        ),
      ),
    );

    final recorder = AnimationRecorder(tester);

    // Record one full float cycle (2 seconds up + 2 seconds down)
    await recorder.record(
      duration: const Duration(milliseconds: 4000),
      frameRate: 10,
    );

    await recorder.compareWithGolden(
      'goldens/neo_bottom_nav_cta_float.apng',
    );
  });

  testWidgets('NeoSnackbar slide-in animation', (tester) async {
    late OverlayEntry entry;

    // Build a scaffold with an Overlay so NeoSnackbar.show() can insert into it
    await tester.pumpWidget(
      wrapWithTheme(
        SizedBox(
          width: 400,
          height: 200,
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: Builder(
              builder: (context) {
                // Schedule the snackbar show after the first frame
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  entry = NeoSnackbar.show(
                    context: context,
                    message: 'Item saved successfully!',
                    type: NeoSnackbarType.success,
                    duration: const Duration(seconds: 10),
                  );
                });
                return const Scaffold(
                  body: SizedBox.expand(),
                );
              },
            ),
          ),
        ),
      ),
    );

    final recorder = AnimationRecorder(tester);

    // The postFrameCallback fires on the first pump, triggering the snackbar
    await recorder.record(
      duration: const Duration(milliseconds: 500),
      frameRate: 15,
    );

    await recorder.compareWithGolden(
      'goldens/neo_snackbar_slide_in.apng',
    );

    // Clean up: remove the overlay entry and advance past the pending timer
    entry.remove();
    await tester.pump(const Duration(seconds: 11));
  });
}
