import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:myexpence/core/providers/core_providers.dart';
import 'package:myexpence/core/utils/category_icon_helper.dart';
import 'package:myexpence/core/theme/app_theme.dart';
import 'package:myexpence/features/ads/presentation/providers/ad_providers.dart';
import 'package:myexpence/core/utils/currency_formatters.dart';
import 'package:myexpence/core/utils/date_formatters.dart';
import 'package:myexpence/features/expenses/presentation/widgets/voice_note_player_bottom_sheet.dart';
import 'package:myexpence/features/auth/domain/models/auth_user.dart';
import 'package:myexpence/features/auth/presentation/providers/auth_providers.dart';
import 'package:myexpence/features/categories/domain/models/category.dart';
import 'package:myexpence/features/categories/presentation/providers/category_providers.dart';
import 'package:myexpence/features/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:myexpence/features/expenses/domain/models/expense.dart';
import 'package:myexpence/features/expenses/domain/models/expense_classification.dart';
import 'package:myexpence/features/expenses/presentation/providers/expense_providers.dart';
import 'package:myexpence/features/people/domain/models/person.dart';
import 'package:myexpence/features/people/presentation/providers/people_providers.dart';
import 'package:myexpence/features/settings/presentation/providers/settings_providers.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _touchedPieIndex = -1;
  bool _showSubcategoriesInChart = false;
  int _currentPage = 0;
  static const int _pageSize = 5;

  /// Drill-down bucket selected inside the current timeframe:
  /// a specific day (Week), week (Month), or month (Year). Null = all.
  DateTime? _selectedBucket;
  DateTime? _selectedBucketEnd;
  String? _selectedBucketLabel;

  @override
  Widget build(BuildContext context) {
    ref.watch(currencyNotifierProvider);
    final dashboardAsync = ref.watch(dashboardDataProvider);
    final peopleAsync = ref.watch(peopleListProvider);
    final categoriesList = ref.watch(categoriesListProvider).valueOrNull ?? [];
    final categoryMap = {for (var c in categoriesList) c.id: c};
    final timeframe = ref.watch(dashboardTimeframeProvider);

    // Reset pagination to first page whenever timeframe filter changes
    ref.listen<DashboardTimeframe>(dashboardTimeframeProvider, (previous, next) {
      if (previous != next) {
        setState(() {
          _currentPage = 0;
          _selectedBucket = null;
          _selectedBucketEnd = null;
          _selectedBucketLabel = null;
        });
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Dashboard Analytics', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(
              _getTimeframeLabel(timeframe),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(dashboardDataProvider);
              ref.invalidate(recentExpensesProvider);
              ref.invalidate(allExpensesProvider);
            },
            tooltip: 'Refresh Data',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dashboardDataProvider);
          ref.invalidate(recentExpensesProvider);
          ref.invalidate(allExpensesProvider);
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          physics: const AlwaysScrollableScrollPhysics(),
          child: dashboardAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(48.0),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (err, stack) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text('Error loading dashboard: $err'),
              ),
            ),
            data: (data) {
              final authUser = ref.watch(authProvider);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 0. User Profile Banner
                  if (authUser.isLoggedIn) ...[
                    _buildUserProfileBanner(context, authUser),
                    const SizedBox(height: 16),
                  ],

                  // 1. Timeframe Filter Selector (Day / Week / Month / Year)
                  _buildTimeframeSelector(context, ref, timeframe),
                  const SizedBox(height: 16),

                  // 2. Summary KPI Cards Grid
                  _buildKPIOverviewGrid(context, data),
                  const SizedBox(height: 20),

                  // 3. Chart 1: Spending Trend Line / Area Chart
                  _buildSpendingTrendCard(context, data),
                  const SizedBox(height: 20),

                  // 4. Chart 2: Category Spending Donut Chart & Legend
                  _buildCategoryBreakdownCard(context, data, categoryMap),
                  const SizedBox(height: 20),

                  // 5. Chart 3: Classification Bar Chart (Required vs Needs vs Optional)
                  _buildClassificationBarChartCard(context, data),
                  const SizedBox(height: 20),

                  // 6. Zero Spend Banner
                  _buildZeroSpendBanner(context, ref, data),
                  const SizedBox(height: 20),

                  // 7. Family / People Breakdown
                  if (data.personBreakdown.isNotEmpty) ...[
                    _buildFamilySection(context, ref, data, peopleAsync),
                    const SizedBox(height: 24),
                  ],

                  // 8. Timeframe-filtered Expenses Section (All for Day, Paginated for Week/Month/Year)
                  _buildExpensesSection(context, data, timeframe, categoryMap),
                  const SizedBox(height: 32),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  String _getTimeframeLabel(DashboardTimeframe tf) {
    switch (tf) {
      case DashboardTimeframe.day:
        return 'Today vs Yesterday';
      case DashboardTimeframe.week:
        return 'This Week';
      case DashboardTimeframe.month:
        return DateFormat('MMMM yyyy').format(DateTime.now());
      case DashboardTimeframe.year:
        return 'Year ${DateTime.now().year}';
    }
  }

  // --- 0. User Banner ---
  Widget _buildUserProfileBanner(BuildContext context, AuthUser user) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: Text(
              (user.displayName?.isNotEmpty ?? false)
                  ? user.displayName![0].toUpperCase()
                  : 'U',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back, ${user.displayName ?? "User"}!',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                Text(
                  user.email ?? 'Synced Account',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Online',
              style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // --- 1. Timeframe Filter Selector ---
  Widget _buildTimeframeSelector(
      BuildContext context, WidgetRef ref, DashboardTimeframe current) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: DashboardTimeframe.values.map((tf) {
          final isSelected = current == tf;
          final label = tf.name.toUpperCase();

          return Expanded(
            child: GestureDetector(
              onTap: () {
                ref.read(dashboardTimeframeProvider.notifier).state = tf;
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          )
                        ]
                      : [],
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isSelected
                        ? Colors.white
                        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // --- 2. KPI Overview Cards Grid ---
  Widget _buildKPIOverviewGrid(BuildContext context, DashboardData data) {
    final diff = data.periodTotal - data.previousPeriodTotal;
    final percentDiff = data.previousPeriodTotal > 0
        ? (diff / data.previousPeriodTotal) * 100
        : 0.0;
    final isIncrease = diff > 0;

    return Column(
      children: [
        // Main Spending Summary Banner Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'TOTAL EXPENSE (${data.selectedTimeframe.name.toUpperCase()})',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                  if (data.previousPeriodTotal > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isIncrease ? Colors.red.shade400 : Colors.green.shade400,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isIncrease ? Icons.trending_up : Icons.trending_down,
                            size: 14,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${percentDiff.abs().toStringAsFixed(1)}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                CurrencyFormatters.format(data.periodTotal),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildSubKpiText('Daily Avg', CurrencyFormatters.format(data.averagePerDay)),
                  _buildSubKpiText('Top Cat', data.topCategoryName),
                  _buildSubKpiText('Today', CurrencyFormatters.format(data.todayTotal)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSubKpiText(String title, String val) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.white60, fontSize: 11)),
        const SizedBox(height: 2),
        Text(
          val,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  // --- 3. Chart 1: Spending Trend Line Chart ---
  Widget _buildSpendingTrendCard(BuildContext context, DashboardData data) {
    if (data.trendPoints.isEmpty) return const SizedBox.shrink();

    final spots = data.trendPoints.map((tp) => FlSpot(tp.x, tp.amount)).toList();
    final maxY = data.trendPoints.fold<double>(
            0.0, (max, tp) => tp.amount > max ? tp.amount : max) *
        1.2;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Spending Trend',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Icon(Icons.show_chart, color: Theme.of(context).colorScheme.primary),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (val) => FlLine(
                      color: Colors.grey.shade200,
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (val, meta) {
                          if (val == 0 || val == meta.max) return const SizedBox.shrink();
                          return Text(
                            val >= 1000 ? '${(val / 1000).toStringAsFixed(0)}k' : '${val.toInt()}',
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: (data.trendPoints.length / 6).clamp(1.0, 10.0),
                        getTitlesWidget: (val, meta) {
                          final idx = val.toInt();
                          if (idx >= 0 && idx < data.trendPoints.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                data.trendPoints[idx].label,
                                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minX: 0,
                  maxX: (data.trendPoints.length - 1).toDouble(),
                  minY: 0,
                  maxY: maxY > 0 ? maxY : 100,
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: Theme.of(context).colorScheme.primary,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- 4. Chart 2: Category & Subcategory Breakdown Donut Chart ---
  Widget _buildCategoryBreakdownCard(
      BuildContext context, DashboardData data, Map<String, Category> categoryMap) {
    final List<MapEntry<String, double>> entries;
    if (_showSubcategoriesInChart) {
      final subNameMap = <String, String>{};
      for (final cat in categoryMap.values) {
        for (final sub in cat.subcategories) {
          subNameMap[sub.id] = sub.name;
          if (sub.uuid != null) subNameMap[sub.uuid!] = sub.name;
        }
      }

      final subcategoryTotals = <String, double>{};
      for (final exp in data.periodExpenses) {
        if (exp.isDeleted || exp.status == ExpenseStatus.cancelled) continue;
        final subId = exp.subcategoryId;
        String displayName;
        if (subId != null && subNameMap.containsKey(subId)) {
          displayName = subNameMap[subId]!;
        } else if (subId != null && subId.trim().isNotEmpty) {
          displayName = subId;
        } else {
          final catName = categoryMap[exp.categoryId]?.name ?? exp.categoryId;
          displayName = '$catName (General)';
        }
        subcategoryTotals[displayName] =
            (subcategoryTotals[displayName] ?? 0.0) + exp.amount;
      }
      entries = subcategoryTotals.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
    } else {
      entries = data.categoryBreakdown.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
    }

    final total = data.periodTotal > 0 ? data.periodTotal : 1.0;

    final colors = [
      const Color(0xFF6C5CE7),
      const Color(0xFF00B894),
      const Color(0xFFFF7675),
      const Color(0xFF00CEC9),
      const Color(0xFFFDCB6E),
      const Color(0xFFE17055),
      const Color(0xFFA29BFE),
      const Color(0xFFE84393),
      const Color(0xFF0984E3),
      const Color(0xFF2D3436),
    ];

    Widget buildHeader() {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              _showSubcategoriesInChart
                  ? 'Subcategory Breakdown'
                  : 'Category Breakdown',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('Category', style: TextStyle(fontSize: 11)),
              ),
              ButtonSegment(
                value: true,
                label: Text('Subcategory', style: TextStyle(fontSize: 11)),
              ),
            ],
            selected: {_showSubcategoriesInChart},
            onSelectionChanged: (val) {
              setState(() {
                _showSubcategoriesInChart = val.first;
                _touchedPieIndex = -1;
              });
            },
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      );
    }

    if (entries.isEmpty) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildHeader(),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  _showSubcategoriesInChart
                      ? 'No subcategory spending data for this period.'
                      : 'No category spending data for this period.',
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final sections = List.generate(entries.length, (i) {
      final isTouched = i == _touchedPieIndex;
      final fontSize = isTouched ? 16.0 : 12.0;
      final radius = isTouched ? 36.0 : 30.0;
      final pct = (entries[i].value / total) * 100;

      return PieChartSectionData(
        color: colors[i % colors.length],
        value: entries[i].value,
        title: pct > 5 ? '${pct.toStringAsFixed(0)}%' : '',
        radius: radius,
        titleStyle: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    });

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildHeader(),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 5,
                  child: SizedBox(
                    height: 160,
                    child: PieChart(
                      PieChartData(
                        pieTouchData: PieTouchData(
                          touchCallback:
                              (FlTouchEvent event, pieTouchResponse) {
                            setState(() {
                              if (!event.isInterestedForInteractions ||
                                  pieTouchResponse == null ||
                                  pieTouchResponse.touchedSection == null) {
                                _touchedPieIndex = -1;
                                return;
                              }
                              _touchedPieIndex = pieTouchResponse
                                  .touchedSection!.touchedSectionIndex;
                            });
                          },
                        ),
                        borderData: FlBorderData(show: false),
                        sectionsSpace: 3,
                        centerSpaceRadius: 38,
                        sections: sections,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 6,
                  child: Column(
                    children: List.generate(
                      entries.length > 5 ? 5 : entries.length,
                      (i) {
                        final displayName = _showSubcategoriesInChart
                            ? entries[i].key
                            : (categoryMap[entries[i].key]?.name ??
                                entries[i].key);
                        final amt = entries[i].value;
                        final color = colors[i % colors.length];

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  displayName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500),
                                ),
                              ),
                              Text(
                                CurrencyFormatters.format(amt),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- 5. Chart 3: Classification Bar Chart ---
  Widget _buildClassificationBarChartCard(BuildContext context, DashboardData data) {
    final requiredAmt = data.classificationBreakdown[ExpenseClassification.required] ?? 0.0;
    final urgentAmt = data.classificationBreakdown[ExpenseClassification.urgent] ?? 0.0;
    final optionalAmt = data.classificationBreakdown[ExpenseClassification.optional] ?? 0.0;
    final lostAmt = data.classificationBreakdown[ExpenseClassification.lost] ?? 0.0;

    final maxVal = [requiredAmt, urgentAmt, optionalAmt, lostAmt]
            .fold<double>(0, (m, v) => v > m ? v : m) *
        1.2;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Classification Breakdown',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 160,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxVal > 0 ? maxVal : 100,
                  barTouchData: BarTouchData(enabled: true),
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (val, meta) {
                          switch (val.toInt()) {
                            case 0:
                              return const Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: Text('Required', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              );
                            case 1:
                              return const Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: Text('Urgent', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              );
                            case 2:
                              return const Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: Text('Optional', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              );
                            case 3:
                              return const Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: Text('Lost', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              );
                            default:
                              return const SizedBox.shrink();
                          }
                        },
                      ),
                    ),
                  ),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  barGroups: [
                    BarChartGroupData(
                      x: 0,
                      barRods: [
                        BarChartRodData(
                          toY: requiredAmt,
                          color: const Color(0xFF00B894),
                          width: 22,
                          borderRadius: BorderRadius.circular(8),
                        )
                      ],
                    ),
                    BarChartGroupData(
                      x: 1,
                      barRods: [
                        BarChartRodData(
                          toY: urgentAmt,
                          color: const Color(0xFFFF7675),
                          width: 22,
                          borderRadius: BorderRadius.circular(8),
                        )
                      ],
                    ),
                    BarChartGroupData(
                      x: 2,
                      barRods: [
                        BarChartRodData(
                          toY: optionalAmt,
                          color: const Color(0xFFFDCB6E),
                          width: 22,
                          borderRadius: BorderRadius.circular(8),
                        )
                      ],
                    ),
                    BarChartGroupData(
                      x: 3,
                      barRods: [
                        BarChartRodData(
                          toY: lostAmt,
                          color: const Color(0xFF8E44AD),
                          width: 22,
                          borderRadius: BorderRadius.circular(8),
                        )
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- 6. Zero Spend Banner ---
  Widget _buildZeroSpendBanner(
      BuildContext context, WidgetRef ref, DashboardData data) {
    if (data.todayTotal > 0) return const SizedBox.shrink();

    return Card(
      color: data.isZeroSpendConfirmedToday
          ? Colors.green.shade50
          : Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(
              data.isZeroSpendConfirmedToday
                  ? Icons.check_circle
                  : Icons.star_outline,
              color: data.isZeroSpendConfirmedToday ? Colors.green : Colors.amber.shade800,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                data.isZeroSpendConfirmedToday
                    ? 'Awesome! Zero-spend day confirmed for today.'
                    : 'No expenses logged today. Confirm zero spend?',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
            if (!data.isZeroSpendConfirmedToday)
              ElevatedButton(
                onPressed: () async {
                  final repo = ref.read(expenseRepositoryProvider);
                  await repo.confirmZeroSpendDay(DateFormatters.todayIso());
                  ref.invalidate(dashboardDataProvider);
                },
                child: const Text('Confirm'),
              ),
          ],
        ),
      ),
    );
  }

  // --- 7. Family Section ---
  Widget _buildFamilySection(
      BuildContext context, WidgetRef ref, DashboardData data, AsyncValue peopleAsync) {
    final peopleList = (peopleAsync.valueOrNull as List<Person>?) ?? [];
    final personMap = {for (var p in peopleList) p.uuid: p.name};
    final authUser = ref.watch(authProvider);
    final defaultUserName = (authUser.displayName?.isNotEmpty == true) ? authUser.displayName! : 'Self';

    final categoriesList = ref.watch(categoriesListProvider).valueOrNull ?? [];
    final categoryMap = {for (var c in categoriesList) c.id: c};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Family / Person Breakdown',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              _getTimeframeLabel(data.selectedTimeframe),
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: data.personBreakdown.entries.map((e) {
                final key = e.key;
                final String displayName = personMap[key] ??
                    (key.isEmpty || key == 'household' || key == 'self' || key == authUser.uid
                        ? defaultUserName
                        : key);

                return InkWell(
                  onTap: () {
                    _showPersonExpensesFilterModal(
                      context: context,
                      ref: ref,
                      displayName: displayName,
                      personKey: key,
                      data: data,
                      categoryMap: categoryMap,
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 8.0),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                          child: Text(
                            displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Tap to filter & view day/date transactions',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          CurrencyFormatters.format(e.value),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade500),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  void _showPersonExpensesFilterModal({
    required BuildContext context,
    required WidgetRef ref,
    required String displayName,
    required String personKey,
    required DashboardData data,
    required Map<String, Category> categoryMap,
  }) {
    // Filter expenses matching this person
    final personExpenses = data.periodExpenses.where((exp) {
      if (personKey.isEmpty || personKey == 'household' || personKey == 'self') {
        return exp.personId == null || exp.personId!.isEmpty || exp.personId == 'household' || exp.personId == 'self';
      }
      return exp.personId == personKey || exp.allocations.any((a) => a.personId == personKey);
    }).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          builder: (_, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        child: Text(
                          displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$displayName Details',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Timeframe Filter: ${_getTimeframeLabel(data.selectedTimeframe)}',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total Spend (${personExpenses.length} transactions)',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        Text(
                          CurrencyFormatters.format(
                            personExpenses.fold<double>(0.0, (sum, exp) => sum + exp.amount),
                          ),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Transactions by Day & Date',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: personExpenses.isEmpty
                        ? Center(
                            child: Text(
                              'No transactions recorded for $displayName in this timeframe.',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            itemCount: personExpenses.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (ctx, idx) {
                              final exp = personExpenses[idx];
                              final category = categoryMap[exp.categoryId];
                              final catName = category?.name ?? 'General';
                              final iconData = CategoryIconHelper.getIconData(category?.icon);
                              final formattedDayDate = DateFormatters.formatDateDisplay(
                                DateFormatters.parseDateIso(exp.expenseDate),
                              );

                              return ListTile(
                                onTap: () {
                                  Navigator.pop(ctx);
                                  ref.read(adNotifierProvider.notifier).recordNavigation(context);
                                  context.push('/add', extra: exp);
                                },
                                leading: CircleAvatar(
                                  backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                                  child: Icon(iconData, size: 20),
                                ),
                                title: Text(
                                  exp.merchant ?? exp.description ?? 'Expense',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  '$formattedDayDate • $catName',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                ),
                                trailing: Text(
                                  CurrencyFormatters.format(exp.amount),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.redAccent,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // --- 8. Timeframe Expenses Section (All Day vs Paginated Week/Month/Year) ---
  Widget _buildExpensesSection(
    BuildContext context,
    DashboardData data,
    DashboardTimeframe timeframe,
    Map<String, Category> categoryMap,
  ) {
    final isDay = timeframe == DashboardTimeframe.day;
    final isYear = timeframe == DashboardTimeframe.year;
    final isMonth = timeframe == DashboardTimeframe.month;

    // Apply drill-down filter (selected day for Week, week for Month, month for Year)
    final bucket = _selectedBucket;
    final bucketEnd = _selectedBucketEnd;
    final expenses = (isDay || bucket == null)
        ? data.periodExpenses
        : data.periodExpenses
            .where((e) => _isInBucket(e.expenseDate, bucket, bucketEnd, isYear, isMonth))
            .toList();
    final totalExpenses = expenses.length;
    final totalPages = (totalExpenses / _pageSize).ceil();

    // Ensure _currentPage is in valid bounds
    if (_currentPage >= totalPages && totalPages > 0) {
      _currentPage = totalPages - 1;
    }

    final displayedExpenses = isDay
        ? expenses
        : _getPaginatedExpenses(expenses);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  bucket != null && !isDay
                      ? (isYear
                          ? "${DateFormat('MMMM').format(bucket)}'s Expenses"
                          : (isMonth
                              ? "${_selectedBucketLabel ?? 'Week'}'s Expenses"
                              : DateFormat('EEE, MMM d').format(bucket)))
                      : _getExpensesSectionTitle(timeframe),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$totalExpenses',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: () => context.go('/expenses'),
              child: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Drill-down selector: Week -> 7 days, Month -> every day, Year -> 12 months
        if (!isDay) ...[
          _buildBucketSelector(context, data, isYear),
          const SizedBox(height: 10),
        ],

        if (expenses.isEmpty)
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      isDay && data.isZeroSpendConfirmedToday
                          ? Icons.celebration_outlined
                          : Icons.receipt_long_outlined,
                      size: 40,
                      color: isDay && data.isZeroSpendConfirmedToday
                          ? Colors.green
                          : Colors.grey.shade400,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isDay
                          ? (data.isZeroSpendConfirmedToday
                              ? 'Zero-Spend Day Confirmed 🎉\nNo money spent today!'
                              : 'No transactions recorded for today.')
                          : (bucket != null
                              ? 'No transactions recorded for this ${isYear ? 'month' : (isMonth ? 'week' : 'day')}.'
                              : 'No transactions recorded for this period.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ),
          )
        else ...[
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.4),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: displayedExpenses.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final expense = displayedExpenses[index];
                final category = categoryMap[expense.categoryId];
                final catName = category?.name ?? 'General';
                final iconName = category?.icon;
                final title = expense.merchant?.isNotEmpty == true
                    ? expense.merchant!
                    : (expense.description?.isNotEmpty == true
                        ? expense.description!
                        : 'Expense');

                return ListTile(
                  leading: CategoryIconHelper.buildCategoryAvatar(
                    iconName: iconName,
                    categoryId: expense.categoryId,
                  ),
                  title: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${DateFormatters.formatDateDisplay(DateFormatters.parseDateIso(expense.expenseDate))} • $catName',
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (expense.hasVoiceNote) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.mic, size: 14, color: AppTheme.primaryColor),
                      ],
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (expense.hasVoiceNote)
                        IconButton(
                          icon: const Icon(Icons.volume_up_outlined,
                              size: 20, color: AppTheme.primaryColor),
                          tooltip: 'Listen to Voice Note',
                          onPressed: () =>
                              showVoiceNoteBottomSheet(context, ref, expense),
                        ),
                      Text(
                        CurrencyFormatters.format(expense.amount),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                  onTap: () {
                    ref.read(adNotifierProvider.notifier).recordNavigation(context);
                    context.push('/add', extra: expense);
                  },
                );
              },
            ),
          ),

          // For week/month/year: Show pagination controls
          if (!isDay && totalExpenses > 0)
            _buildPaginationControls(context, totalExpenses, totalPages),
        ],
      ],
    );
  }

  bool _isInBucket(String expenseDateIso, DateTime bucket, DateTime? bucketEnd, bool isYear, bool isMonth) {
    final d = DateTime.tryParse(expenseDateIso);
    if (d == null) return false;
    if (isYear) return d.year == bucket.year && d.month == bucket.month;
    if (isMonth && bucketEnd != null) {
      return d.year == bucket.year &&
          d.month == bucket.month &&
          d.day >= bucket.day &&
          d.day <= bucketEnd.day;
    }
    return d.year == bucket.year && d.month == bucket.month && d.day == bucket.day;
  }

  bool _isBucketSelected(DateTime date, bool isYear) {
    final b = _selectedBucket;
    if (b == null) return false;
    if (isYear) return b.year == date.year && b.month == date.month;
    return b.year == date.year && b.month == date.month && b.day == date.day;
  }

  /// Horizontal, tappable strip of days (Week), weeks (Month), or months (Year) with totals.
  /// Tap a chip to see only that period's expenses; tap again (or "All") to clear.
  Widget _buildBucketSelector(BuildContext context, DashboardData data, bool isYear) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final isMonth = data.selectedTimeframe == DashboardTimeframe.month;

    Widget chip({
      required String top,
      required String bottom,
      required String amount,
      required bool selected,
      required bool highlight,
      required VoidCallback onTap,
    }) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: isMonth ? 74 : 64,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: selected
                  ? scheme.primary
                  : scheme.surfaceContainerHighest.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: highlight && !selected
                    ? scheme.primary
                    : scheme.outlineVariant.withValues(alpha: 0.4),
                width: highlight && !selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  top,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? Colors.white70
                        : scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  bottom,
                  style: TextStyle(
                    fontSize: isMonth ? 13 : 16,
                    fontWeight: FontWeight.bold,
                    color: selected ? Colors.white : scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    amount,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : Colors.redAccent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final chips = <Widget>[
      chip(
        top: 'All',
        bottom: isYear ? 'Year' : (data.selectedTimeframe == DashboardTimeframe.week ? 'Week' : 'Month'),
        amount: CurrencyFormatters.format(data.periodTotal),
        selected: _selectedBucket == null,
        highlight: false,
        onTap: () => setState(() {
          _selectedBucket = null;
          _selectedBucketEnd = null;
          _selectedBucketLabel = null;
          _currentPage = 0;
        }),
      ),
      for (final p in data.trendPoints)
        chip(
          top: isYear
              ? '${p.date.year}'
              : (isMonth
                  ? '${p.date.day}-${p.endDate?.day ?? p.date.day}'
                  : DateFormat('EEE').format(p.date)),
          bottom: isYear
              ? DateFormat('MMM').format(p.date)
              : (isMonth ? p.label : '${p.date.day}'),
          amount: p.amount > 0 ? CurrencyFormatters.format(p.amount) : '-',
          selected: _isBucketSelected(p.date, isYear),
          highlight: isYear
              ? p.date.year == now.year && p.date.month == now.month
              : (isMonth
                  ? p.date.year == now.year &&
                      p.date.month == now.month &&
                      now.day >= p.date.day &&
                      now.day <= (p.endDate?.day ?? p.date.day)
                  : p.date.year == now.year &&
                      p.date.month == now.month &&
                      p.date.day == now.day),
          onTap: () => setState(() {
            final isSel = _isBucketSelected(p.date, isYear);
            _selectedBucket = isSel ? null : p.date;
            _selectedBucketEnd = isSel ? null : p.endDate;
            _selectedBucketLabel = isSel ? null : p.label;
            _currentPage = 0;
          }),
        ),
    ];

    return SizedBox(
      height: 78,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: chips,
      ),
    );
  }

  String _getExpensesSectionTitle(DashboardTimeframe tf) {
    switch (tf) {
      case DashboardTimeframe.day:
        return "Today's Expenses";
      case DashboardTimeframe.week:
        return "This Week's Expenses";
      case DashboardTimeframe.month:
        return "This Month's Expenses";
      case DashboardTimeframe.year:
        return "This Year's Expenses";
    }
  }

  List<Expense> _getPaginatedExpenses(List<Expense> expenses) {
    final totalExpenses = expenses.length;
    if (totalExpenses == 0) return [];
    final startIndex = _currentPage * _pageSize;
    final endIndex = (startIndex + _pageSize > totalExpenses)
        ? totalExpenses
        : startIndex + _pageSize;
    return expenses.sublist(startIndex, endIndex);
  }

  Widget _buildPaginationControls(
    BuildContext context,
    int totalCount,
    int totalPages,
  ) {
    if (totalPages <= 1) {
      return Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: Center(
          child: Text(
            'Showing all $totalCount transactions',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.6),
            ),
          ),
        ),
      );
    }

    final startIndex = _currentPage * _pageSize + 1;
    final endIndex = (_currentPage * _pageSize + _pageSize > totalCount)
        ? totalCount
        : (_currentPage * _pageSize + _pageSize);

    final isFirstPage = _currentPage == 0;
    final isLastPage = _currentPage >= totalPages - 1;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Showing $startIndex–$endIndex of $totalCount',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.7),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                iconSize: 20,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: 'Previous page',
                onPressed: isFirstPage
                    ? null
                    : () {
                        setState(() {
                          _currentPage--;
                        });
                      },
              ),
              if (totalPages <= 5)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(totalPages, (index) {
                    final isCurrent = index == _currentPage;
                    return InkWell(
                      onTap: () => setState(() => _currentPage = index),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isCurrent
                                ? Colors.white
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    );
                  }),
                )
              else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_currentPage + 1} / $totalPages',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                iconSize: 20,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: 'Next page',
                onPressed: isLastPage
                    ? null
                    : () {
                        setState(() {
                          _currentPage++;
                        });
                      },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
