import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myexpence/core/theme/app_theme.dart';
import 'package:myexpence/core/utils/date_formatters.dart';
import 'package:myexpence/features/categories/presentation/providers/category_providers.dart';
import 'package:myexpence/features/expenses/domain/models/expense.dart';
import 'package:myexpence/features/expenses/domain/models/payment_method.dart';
import 'package:myexpence/features/expenses/presentation/providers/expense_providers.dart';
import 'package:myexpence/features/sms_parser/domain/services/sms_parser_service.dart';
import 'package:myexpence/features/sms_parser/presentation/providers/sms_whitelist_provider.dart';
import 'package:uuid/uuid.dart';

Future<bool?> showSmsApprovalDialog(
  BuildContext context,
  WidgetRef ref, {
  required String rawSms,
  String? sender,
}) async {
  final whitelist = ref.read(smsWhitelistProvider);
  final result = SmsParserService.parseSmsText(rawSms, sender: sender, customAllowedSenders: whitelist);

  final categories = ref.read(categoriesListProvider).valueOrNull ?? [];
  final category = categories.firstWhere(
    (c) => c.id == result.suggestedCategoryId,
    orElse: () => categories.isNotEmpty ? categories.first : throw Exception('No categories available'),
  );

  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        title: Row(
          children: [
            const Icon(Icons.sms, color: AppTheme.primaryColor),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'SMS Received',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: result.isKnownSender ? Colors.green.withValues(alpha: 0.15) : Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: result.isKnownSender ? Colors.green : Colors.orange),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(result.isKnownSender ? Icons.verified : Icons.warning, size: 12, color: result.isKnownSender ? Colors.green[800] : Colors.orange[800]),
                  const SizedBox(width: 4),
                  Text(
                    result.sender ?? 'Bank SMS',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: result.isKnownSender ? Colors.green[800] : Colors.orange[900]),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'A transaction SMS was detected from a whitelisted bank sender. Would you like to approve and save this expense to your database?',
              style: TextStyle(fontSize: 12, color: Colors.black87),
            ),
            const SizedBox(height: 14),

            // Parsed Summary Card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Amount:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Rs ${result.amount.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green),
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Merchant / Vendor:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          result.merchant ?? 'General Vendor',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Category:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          category.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Transaction Date:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          DateFormatters.formatDateShort(result.detectedDate),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Approve Button
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final nowStr = DateTime.now().toIso8601String();
                final dateIso = DateFormatters.formatDateIso(result.detectedDate);

                final expense = Expense(
                  uuid: const Uuid().v4(),
                  amount: result.amount > 0 ? result.amount : 0.0,
                  categoryId: category.id,
                  classification: result.classification,
                  expenseDate: dateIso,
                  createdAt: nowStr,
                  updatedAt: nowStr,
                  merchant: result.merchant,
                  paymentMethod: PaymentMethod.bankTransfer,
                  notes: 'Approved Bank SMS (${result.sender ?? "Bank"}): "${result.rawSms}"',
                  status: ExpenseStatus.approved,
                );

                await ref.read(expenseNotifierProvider.notifier).addExpense(expense);
                if (ctx.mounted) {
                  Navigator.pop(ctx, true);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✅ Approved & Saved Rs ${result.amount.toStringAsFixed(2)} expense to Database!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.check_circle, size: 18),
              label: const Text('Approve & Save to Database', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ),
            const SizedBox(height: 8),

            // Discard Button
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red[700],
                side: BorderSide(color: Colors.red[300]!),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final nowStr = DateTime.now().toIso8601String();
                final dateIso = DateFormatters.formatDateIso(result.detectedDate);

                final expense = Expense(
                  uuid: const Uuid().v4(),
                  amount: result.amount > 0 ? result.amount : 0.0,
                  categoryId: category.id,
                  classification: result.classification,
                  expenseDate: dateIso,
                  createdAt: nowStr,
                  updatedAt: nowStr,
                  merchant: result.merchant,
                  paymentMethod: PaymentMethod.bankTransfer,
                  notes: 'Pending Bank SMS (${result.sender ?? "Bank"}): "${result.rawSms}"',
                  status: ExpenseStatus.pending,
                );

                await ref.read(expenseNotifierProvider.notifier).addExpense(expense);
                if (ctx.mounted) {
                  Navigator.pop(ctx, false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Saved Rs ${result.amount.toStringAsFixed(2)} as Pending Approval in DB'),
                      backgroundColor: Colors.orange[800],
                    ),
                  );
                }
              },
              icon: const Icon(Icons.cancel_outlined, size: 16),
              label: const Text('Discard / Save as Pending', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
    },
  );
}
