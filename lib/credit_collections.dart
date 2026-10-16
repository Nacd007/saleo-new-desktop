import 'package:flutter/material.dart';

import 'formatters.dart';
import 'models.dart';

List<CreditPaymentRecord> creditPaymentsForDay(
  List<CreditPaymentRecord> payments,
  DateTime day,
) => payments
    .where(
      (p) =>
          DateUtils.isSameDay(p.createdAt.toLocal(), day.toLocal()) &&
          !p.createdAt.isAfter(day),
    )
    .toList();

int moneyCollectedForDay(
  List<Sale> sales,
  List<CreditPaymentRecord> payments,
  DateTime day,
) =>
    sales
        .where(
          (s) =>
              !s.voided &&
              DateUtils.isSameDay(s.createdAt.toLocal(), day.toLocal()) &&
              !s.createdAt.isAfter(day),
        )
        .fold<int>(0, (sum, s) => sum + s.cashCents + s.mobileMoneyCents) +
    creditPaymentsForDay(
      payments,
      day,
    ).fold<int>(0, (sum, p) => sum + p.amountCents);

class CreditCollectionsPanel extends StatelessWidget {
  const CreditCollectionsPanel({
    super.key,
    required this.sales,
    required this.payments,
  });
  final List<Sale> sales;
  final List<CreditPaymentRecord> payments;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = creditPaymentsForDay(payments, now);
    final credit = today.fold<int>(0, (sum, p) => sum + p.amountCents);
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        leading: const Icon(Icons.payments_outlined),
        title: Text(
          'Credit payments received today • GHS ${money(credit)}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        subtitle: Text(
          'Money collected today: GHS ${money(moneyCollectedForDay(sales, payments, now))} • Includes checkout payments and credit repayments, not unpaid credit.',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Credit repayments are collections against earlier sales, not new sales revenue.',
            ),
          ),
          const SizedBox(height: 8),
          if (today.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('No credit payments received today.'),
            ),
          for (final payment in today)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                payment.companyName.isNotEmpty
                    ? payment.companyName
                    : payment.customerName,
              ),
              subtitle: Text(
                'Credit payment • ${payment.method.replaceAll('_', ' + ')} • Recorded by ${payment.recordedBy.isEmpty ? 'Not recorded' : payment.recordedBy}',
              ),
              trailing: Text('GHS ${money(payment.amountCents)}'),
              onTap: () => _details(context, payment),
            ),
        ],
      ),
    );
  }

  void _details(
    BuildContext context,
    CreditPaymentRecord payment,
  ) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Credit payment details'),
      content: SizedBox(
        width: 430,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Company / customer: ${payment.companyName.isNotEmpty ? payment.companyName : payment.customerName}',
              ),
              Text('Contact name: ${payment.customerName}'),
              Text('Date: ${payment.createdAt.toLocal()}'),
              const Divider(),
              Text(
                'Credit payment received: GHS ${money(payment.amountCents)}',
              ),
              Text('Cash: GHS ${money(payment.cashCents)}'),
              Text('MOMO: GHS ${money(payment.mobileMoneyCents)}'),
              Text(
                'Recorded by: ${payment.recordedBy.isEmpty ? 'Not recorded' : payment.recordedBy}',
              ),
              if (payment.note?.isNotEmpty ?? false)
                Text('Note: ${payment.note}'),
              const SizedBox(height: 10),
              SelectableText('Payment reference: ${payment.id}'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
