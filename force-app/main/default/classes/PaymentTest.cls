// NOTE: Invoice.createable=false on this org, so no Payment__c in these
// tests can be linked to a real Invoice (Invoice__c is now optional after
// this discovery — see PR description). These tests exercise the trigger
// and PaymentService's empty/no-invoice code paths; full coverage of the
// balance-recalculation logic needs a working Invoice creation path.
@isTest
public class PaymentTest {

    @TestSetup
    static void setup() {
        TestDataFactory.createAccount('Payment Test Account');
    }

    @isTest
    static void testPaymentInsertFiresTriggerWithoutInvoice() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        Payment__c pay = new Payment__c(
            Account__c = acc.Id,
            Amount__c = 50,
            Status__c = 'Completed',
            PaymentDate__c = Date.today()
        );
        insert pay;
        Test.stopTest();

        System.assertNotEquals(null, pay.Id);
    }

    @isTest
    static void testPaymentUpdateFiresTriggerWithoutInvoice() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Payment__c pay = new Payment__c(
            Account__c = acc.Id,
            Amount__c = 50,
            Status__c = 'Completed',
            PaymentDate__c = Date.today()
        );
        insert pay;

        Test.startTest();
        pay.Amount__c = 75;
        pay.Status__c = 'Refunded';
        update pay;
        Test.stopTest();

        Payment__c reloaded = [SELECT Amount__c, Status__c FROM Payment__c WHERE Id = :pay.Id];
        System.assertEquals(75, reloaded.Amount__c);
        System.assertEquals('Refunded', reloaded.Status__c);
    }

    @isTest
    static void testPaymentDeleteFiresTriggerWithoutInvoice() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Payment__c pay = new Payment__c(
            Account__c = acc.Id,
            Amount__c = 50,
            Status__c = 'Completed',
            PaymentDate__c = Date.today()
        );
        insert pay;

        Test.startTest();
        delete pay;
        Test.stopTest();

        List<Payment__c> remaining = [SELECT Id FROM Payment__c WHERE Id = :pay.Id];
        System.assertEquals(0, remaining.size());
    }

    @isTest
    static void testPaymentServiceNoOpOnEmptyOrNullInput() {
        Test.startTest();
        PaymentService.recalculateInvoiceBalances(new Set<Id>());
        PaymentService.recalculateInvoiceBalances(null);
        Test.stopTest();
        System.assert(true, 'Should not throw on empty/null input');
    }
}
