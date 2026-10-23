import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myexpence/features/ads/presentation/widgets/ad_page_wrapper.dart';
import 'package:myexpence/core/utils/date_formatters.dart';
import 'package:myexpence/features/analytics/presentation/screens/analytics_screen.dart';
import 'package:myexpence/features/auth/presentation/screens/google_login_screen.dart';
import 'package:myexpence/features/budgets/presentation/screens/budget_screen.dart';
import 'package:myexpence/features/calendar/presentation/screens/calendar_screen.dart';
import 'package:myexpence/features/categories/presentation/screens/category_screen.dart';
import 'package:myexpence/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:myexpence/features/document_scanner/presentation/screens/share_document_review_screen.dart';
import 'package:myexpence/features/expenses/domain/models/expense.dart';
import 'package:myexpence/features/expenses/presentation/screens/add_expense_screen.dart';
import 'package:myexpence/features/expenses/presentation/screens/expense_list_screen.dart';
import 'package:myexpence/features/navigation/main_shell_screen.dart';
import 'package:myexpence/features/people/presentation/screens/people_screen.dart';
import 'package:myexpence/features/settings/presentation/screens/more_screen.dart';
import 'package:myexpence/features/sms_parser/presentation/screens/share_sms_review_screen.dart';
import 'package:myexpence/features/subscription/presentation/screens/paywall_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final GlobalKey<NavigatorState> _shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

final GoRouter appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/login',
  routes: [
    GoRoute(
      parentNavigatorKey: _rootNavigatorKey,
      path: '/login',
      builder: (context, state) => const GoogleLoginScreen(),
    ),
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) {
        return MainShellScreen(child: child);
      },
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (context, state) => const DashboardScreen(),
        ),
        GoRoute(
          path: '/expenses',
          builder: (context, state) {
            String? date;
            if (state.uri.queryParameters.containsKey('date')) {
              date = state.uri.queryParameters['date'];
            } else if (state.extra is String) {
              date = state.extra as String;
            } else if (state.extra is DateTime) {
              date = DateFormatters.formatDateIso(state.extra as DateTime);
            } else if (state.extra is Map &&
                (state.extra as Map).containsKey('date')) {
              date = (state.extra as Map)['date']?.toString();
            }
            return ExpenseListScreen(initialDate: date);
          },
        ),
        GoRoute(
          path: '/analytics',
          builder: (context, state) => const AnalyticsScreen(),
        ),
        GoRoute(
          path: '/more',
          builder: (context, state) => const MoreScreen(),
        ),
        GoRoute(
          path: '/people',
          builder: (context, state) => const PeopleScreen(),
        ),
        GoRoute(
          path: '/categories',
          builder: (context, state) => const CategoryScreen(),
        ),
        GoRoute(
          path: '/calendar',
          builder: (context, state) => const CalendarScreen(),
        ),
        GoRoute(
          path: '/budgets',
          builder: (context, state) => const BudgetScreen(),
        ),
      ],
    ),
    GoRoute(
      parentNavigatorKey: _rootNavigatorKey,
      path: '/add',
      builder: (context, state) {
        final expenseToEdit = state.extra as Expense?;
        return AdPageWrapper(child: AddExpenseScreen(expenseToEdit: expenseToEdit));
      },
    ),
    GoRoute(
      parentNavigatorKey: _rootNavigatorKey,
      path: '/share-receipt',
      builder: (context, state) {
        final path = state.extra as String?;
        return AdPageWrapper(child: ShareDocumentReviewScreen(sharedImagePath: path));
      },
    ),
    GoRoute(
      parentNavigatorKey: _rootNavigatorKey,
      path: '/share-sms',
      builder: (context, state) {
        final text = state.extra as String?;
        return AdPageWrapper(child: ShareSmsReviewScreen(initialSmsText: text));
      },
    ),
    GoRoute(
      parentNavigatorKey: _rootNavigatorKey,
      path: '/paywall',
      builder: (context, state) {
        final feature = state.extra as String?;
        return AdPageWrapper(child: PaywallScreen(featureName: feature));
      },
    ),
    GoRoute(
      parentNavigatorKey: _rootNavigatorKey,
      path: '/expenses/:id',
      builder: (context, state) {
        final expenseToEdit = state.extra as Expense?;
        return AdPageWrapper(child: AddExpenseScreen(expenseToEdit: expenseToEdit));
      },
    ),
  ],
  errorBuilder: (context, state) {
    return Scaffold(
      appBar: AppBar(title: const Text('MyExpense')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.receipt_long_rounded, size: 56, color: Colors.blue),
              const SizedBox(height: 16),
              const Text(
                'Page Not Found',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Could not locate: ${state.uri}',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.home_rounded),
                label: const Text('Back to Dashboard'),
                onPressed: () => context.go('/dashboard'),
              ),
            ],
          ),
        ),
      ),
    );
  },
);
