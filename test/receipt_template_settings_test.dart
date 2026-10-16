import 'package:flutter_test/flutter_test.dart';
import 'package:saleo_app/models.dart';

void main() {
  test('uses the server default until one custom template is created', () {
    final settings = ReceiptTemplateSettings.fromJson({
      'default_template': {
        'shop_name': 'Acme Wholesale',
        'location': '',
        'phone_number': '',
        'show_customer_name': true,
        'show_receipt_id': true,
        'footer_message': 'Thank you for your business.',
      },
      'custom_template': null,
      'active': 'default',
    }, companyName: 'Acme Wholesale');

    expect(settings.active, ReceiptTemplateKind.defaultTemplate);
    expect(settings.customTemplate, isNull);
    expect(settings.activeTemplate.shopName, 'Acme Wholesale');
  });

  test('saving again updates the single custom template', () {
    final original = ReceiptTemplateSettings.forCompany('Acme Wholesale')
        .withCustom(
          const ReceiptTemplate(shopName: 'Acme Shop', location: 'Accra'),
        );
    final updated = original.withCustom(
      const ReceiptTemplate(shopName: 'Acme Shop', location: 'Kumasi'),
    );

    expect(updated.active, ReceiptTemplateKind.custom);
    expect(updated.customTemplate?.location, 'Kumasi');
    expect(updated.activeTemplate.location, 'Kumasi');
  });
}
