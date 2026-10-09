import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myexpence/core/utils/currency_formatters.dart';
import 'package:myexpence/features/expenses/presentation/providers/expense_providers.dart';

Future<void> showPendingRecurringExpensesDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final pending = await ref.read(pendingRecurringExpensesProvider.future);
  if (pending.isEmpty || !context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => Consumer(
      builder: (context, ref, _) {
        final expenses =
            ref.watch(pendingRecurringExpensesProvider).valueOrNull ?? pending;
        return AlertDialog(
          title: const Text('Approve recurring expenses'),
          content: SizedBox(
            width: double.maxFinite,
            child: expenses.isEmpty
                ? const Text('All recurring expenses have been reviewed.')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: expenses.length,
                    itemBuilder: (_, index) {
                      final expense = expenses[index];
                      return Card(
                        child: ListTile(
                          title: Text(expense.merchant ??
                              expense.description ??
                              expense.categoryId),
                          subtitle: Text(
                              '${expense.expenseDate} • ${CurrencyFormatters.format(expense.amount)}'),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                tooltip: 'Reject and remove',
                                icon:
                                    const Icon(Icons.close, color: Colors.red),
                                onPressed: () => ref
                                    .read(expenseNotifierProvider.notifier)
                                    .rejectExpense(expense.uuid),
                              ),
                              IconButton(
                                tooltip: 'Approve expense',
                                icon: const Icon(Icons.check,
                                    color: Colors.green),
                                onPressed: () => ref
                                    .read(expenseNotifierProvider.notifier)
                                    .approveExpense(expense.uuid),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            if (expenses.isNotEmpty)
              TextButton(
                onPressed: () async {
                  for (final expense in expenses) {
                    await ref
                        .read(expenseNotifierProvider.notifier)
                        .approveExpense(expense.uuid);
                  }
                },
                child: const Text('Approve all'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        );
      },
    ),
  );
}
