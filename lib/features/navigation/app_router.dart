import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
          builder: (context, state) => const ExpenseListScreen(),
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
        return AddExpenseScreen(expenseToEdit: expenseToEdit);
      },
    ),
    GoRoute(
      parentNavigatorKey: _rootNavigatorKey,
      path: '/share-receipt',
      builder: (context, state) {
        final path = state.extra as String?;
        return ShareDocumentReviewScreen(sharedImagePath: path);
      },
    ),
    GoRoute(
      parentNavigatorKey: _rootNavigatorKey,
      path: '/share-sms',
      builder: (context, state) {
        final text = state.extra as String?;
        return ShareSmsReviewScreen(initialSmsText: text);
      },
    ),
    GoRoute(
      parentNavigatorKey: _rootNavigatorKey,
      path: '/paywall',
      builder: (context, state) {
        final feature = state.extra as String?;
        return PaywallScreen(featureName: feature);
      },
    ),
  ],
);
