import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myexpence/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('MyExpense app initializes without error', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MyExpenseApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Welcome to My Expence Book'), findsOneWidget);
  });
}
