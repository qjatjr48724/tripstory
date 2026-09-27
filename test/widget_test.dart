import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tripstory/app/app.dart';
import 'package:tripstory/features/auth/presentation/pages/login_page.dart';

void main() {
  testWidgets('스플래시 후 로그인 화면으로 이동한다', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: TripStoryApp(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();

    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.text('로그인'), findsOneWidget);
  });
}
