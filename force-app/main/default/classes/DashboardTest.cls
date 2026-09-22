// NOTE: Invoice.createable=false on this org, so Invoice-dependent
// assertions (openInvoices, getInvoices) use empty-result expectations
// here instead of real data — see PR description for the tracked defect.
@isTest
public class DashboardTest {

    @TestSetup
    static void setup() {
        Account acc = TestDataFactory.createAccount('Dashboard Test Account');
        Product2 prod = TestDataFactory.createProduct('Dashboard Widget', 'Recurring', 'Seat', 'Monthly');
        PricebookEntry pbe = TestDataFactory.createStandardPricebookEntry(prod.Id, 45);

        Order ord = TestDataFactory.createOrder(acc.Id, 'Draft');
        OrderItem item = TestDataFactory.createOrderItem(ord.Id, prod.Id, pbe.Id, 1, 45);
        // Activating a Recurring-product OrderItem auto-creates a Subscription__c
        // via OrderTriggerHandler -> OrderActivationService — don't create one manually.
        TestDataFactory.activateOrder(ord.Id);

        TestDataFactory.createEntitlement(item.Id, acc.Id, prod.Id, 'Active');

        TestDataFactory.createPayment(acc.Id, null, 20, 'Completed');
    }

    @isTest
    static void testGetOverview() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        Map<String, Object> overview = AccountBillingDashboardController.getOverview(acc.Id);
        Test.stopTest();

        System.assertEquals(1, overview.get('activeSubscriptions'));
        System.assertEquals(1, overview.get('activeEntitlements'));
        System.assertEquals(0, overview.get('openInvoices'));
        System.assertNotEquals(null, overview.get('lastPaymentAmount'));
    }

    @isTest
    static void testGetOrdersSubscriptionsEntitlementsInvoices() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        List<Order> orders = AccountBillingDashboardController.getOrders(acc.Id);
        List<Subscription__c> subs = AccountBillingDashboardController.getSubscriptions(acc.Id);
        List<Entitlement__c> ents = AccountBillingDashboardController.getEntitlements(acc.Id);
        List<Invoice> invoices = AccountBillingDashboardController.getInvoices(acc.Id);
        Test.stopTest();

        System.assertEquals(1, orders.size());
        System.assertEquals(1, subs.size());
        System.assertEquals(1, ents.size());
        System.assertEquals(0, invoices.size());
    }

    @isTest
    static void testGetOverviewWithNoPayments() {
        Account acc = TestDataFactory.createAccount('No Payment Account');

        Test.startTest();
        Map<String, Object> overview = AccountBillingDashboardController.getOverview(acc.Id);
        Test.stopTest();

        System.assertEquals(0, overview.get('activeSubscriptions'));
        System.assertEquals(0, overview.get('totalBalanceDue'));
        System.assertEquals(false, overview.containsKey('lastPaymentAmount'));
    }
}
