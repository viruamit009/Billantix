@isTest
public class BillingTest {

    @TestSetup
    static void setup() {
        Account acc = TestDataFactory.createAccount('Billing Test Account');
        Product2 prod = TestDataFactory.createProduct('Billing Widget', 'Usage-Based', 'API Call', 'Monthly');
        PricebookEntry pbe = TestDataFactory.createStandardPricebookEntry(prod.Id, 2);
        Order ord = TestDataFactory.createOrder(acc.Id, 'Draft');
        TestDataFactory.createOrderItem(ord.Id, prod.Id, pbe.Id, 1, 2);
        TestDataFactory.activateOrder(ord.Id);
        TestDataFactory.createBillingScheduleForOrder(
            ord.Id, acc.Id, 'Monthly', Date.today(), Date.today().addMonths(6), true
        );
    }

    @isTest
    static void testBillingScheduleSelectorMethods() {
        Order ord = [SELECT Id, AccountId FROM Order LIMIT 1];

        Test.startTest();
        BillingSchedule__c byOrder = BillingScheduleSelector.getScheduleByOrderId(ord.Id);
        BillingSchedule__c byAccount = BillingScheduleSelector.getScheduleByAccountId(ord.AccountId);
        List<BillingSchedule__c> byAccountList = BillingScheduleSelector.getSchedulesByAccountId(ord.AccountId);
        List<BillingSchedule__c> due = BillingScheduleSelector.getActiveSchedulesDueForBilling();
        Test.stopTest();

        System.assertNotEquals(null, byOrder);
        System.assertEquals(null, byAccount, 'Order-level schedule exists so account-level fallback should be null');
        System.assertEquals(1, byAccountList.size());
        System.assertNotEquals(null, due);
    }

    @isTest
    static void testBillingScheduleServiceEffectiveScheduleAndAdvance() {
        Order ord = [SELECT Id, AccountId FROM Order LIMIT 1];
        BillingSchedule__c sched = [SELECT Id, Next_Billing_Date__c, End_Date__c, Billing_Frequency__c, Auto_Renew__c, Status__c FROM BillingSchedule__c LIMIT 1];

        Test.startTest();
        BillingSchedule__c effective = BillingScheduleService.getEffectiveSchedule(ord);
        Date next = BillingScheduleService.calculateNextBillingDate(Date.today(), 'Quarterly');
        Date nextAnnual = BillingScheduleService.calculateNextBillingDate(Date.today(), 'Annual');
        Date nextUnknown = BillingScheduleService.calculateNextBillingDate(Date.today(), 'Weekly');
        BillingScheduleService.advanceSchedule(sched);
        Test.stopTest();

        System.assertNotEquals(null, effective);
        System.assertEquals(Date.today().addMonths(3), next);
        System.assertEquals(Date.today().addMonths(12), nextAnnual);
        System.assertEquals(null, nextUnknown);
    }

    @isTest
    static void testBillingScheduleServiceAdvancePastEndDateWithoutAutoRenewCompletes() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Order ord = TestDataFactory.createOrder(acc.Id, 'Draft');
        BillingSchedule__c sched = TestDataFactory.createBillingScheduleForOrder(
            ord.Id, acc.Id, 'Monthly', Date.today(), Date.today().addDays(5), false
        );

        Test.startTest();
        BillingScheduleService.advanceSchedule(sched);
        Test.stopTest();

        System.assertEquals('Completed', sched.Status__c);
    }

    @isTest
    static void testBillingScheduleServiceCreateForOrderAndAccount() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Order ord = TestDataFactory.createOrder(acc.Id, 'Draft');

        Test.startTest();
        BillingSchedule__c orderSched = BillingScheduleService.createForOrder(
            ord.Id, acc.Id, 'Annual', Date.today(), Date.today().addYears(1), true
        );
        BillingSchedule__c acctSched = BillingScheduleService.createForAccount(
            acc.Id, 'Quarterly', Date.today(), null, false
        );
        Test.stopTest();

        System.assertNotEquals(null, orderSched.Id);
        System.assertNotEquals(null, acctSched.Id);
    }

    @isTest
    static void testPricingServiceCalculations() {
        OrderItem item = [SELECT Id, Product2Id, Product2.Product_Type__c, UnitPrice, Quantity FROM OrderItem LIMIT 1];

        Test.startTest();
        Decimal usageAmount = PricingService.calculateLineAmount(item, 10);
        Decimal freqFactor = PricingService.applyBillingFrequencyFactor(100, 'Quarterly');
        Decimal freqFactorUnknown = PricingService.applyBillingFrequencyFactor(100, 'Weekly');
        Decimal total = PricingService.calculateOrderTotal(
            new List<OrderItem>{ item },
            new Map<Id, Decimal>{ item.Id => 10 }
        );
        Test.stopTest();

        System.assertEquals(item.UnitPrice * 10, usageAmount);
        System.assertEquals(300, freqFactor);
        System.assertEquals(100, freqFactorUnknown);
        System.assertEquals(item.UnitPrice * 10, total);
    }

    @isTest
    static void testPricingServiceFlatFeeAndRecurring() {
        Product2 flat = TestDataFactory.createProduct('Flat', 'Flat Fee', 'Unit', 'One-Time');
        Product2 recurring = TestDataFactory.createProduct('Recurring', 'Recurring', 'Seat', 'Monthly');
        PricebookEntry flatPbe = TestDataFactory.createStandardPricebookEntry(flat.Id, 500);
        PricebookEntry recPbe = TestDataFactory.createStandardPricebookEntry(recurring.Id, 10);

        Account acc = [SELECT Id FROM Account LIMIT 1];
        Order ord = TestDataFactory.createOrder(acc.Id, 'Draft');
        OrderItem flatItem = TestDataFactory.createOrderItem(ord.Id, flat.Id, flatPbe.Id, 1, 500);
        OrderItem recItem = TestDataFactory.createOrderItem(ord.Id, recurring.Id, recPbe.Id, 5, 10);

        flatItem = [SELECT Id, Product2Id, Product2.Product_Type__c, UnitPrice, Quantity FROM OrderItem WHERE Id = :flatItem.Id];
        recItem = [SELECT Id, Product2Id, Product2.Product_Type__c, UnitPrice, Quantity FROM OrderItem WHERE Id = :recItem.Id];

        Test.startTest();
        Decimal flatAmount = PricingService.calculateLineAmount(flatItem, null);
        Decimal recAmount = PricingService.calculateLineAmount(recItem, null);
        Test.stopTest();

        System.assertEquals(500, flatAmount);
        System.assertEquals(50, recAmount);
    }

    @isTest
    static void testUsageSelectorMethods() {
        OrderItem item = [SELECT Id, OrderId, Product2Id FROM OrderItem LIMIT 1];
        Account acc = [SELECT Id FROM Account LIMIT 1];
        TestDataFactory.createUsage(item.OrderId, item.Id, acc.Id, item.Product2Id, 5, 'Pending');
        TestDataFactory.createUsage(item.OrderId, item.Id, acc.Id, item.Product2Id, 3, 'Pending');

        Test.startTest();
        List<Usage__c> pending = UsageSelector.getPendingUsageByOrderItemIds(new Set<Id>{ item.Id });
        List<Usage__c> byOrder = UsageSelector.getUsageByOrderId(item.OrderId);
        Map<Id, Decimal> totals = UsageSelector.getTotalPendingQuantityByOrderItem(new Set<Id>{ item.Id });
        Test.stopTest();

        System.assertEquals(2, pending.size());
        System.assertEquals(2, byOrder.size());
        System.assertEquals(8, totals.get(item.Id));
    }
}
