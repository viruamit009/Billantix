@isTest
public class RenewalTest {

    @TestSetup
    static void setup() {
        Account autoAcc = TestDataFactory.createAccount('Auto Renewal Account');
        autoAcc.RenewalMode__c = 'Auto';
        autoAcc.RenewalLeadDays__c = 30;
        update autoAcc;

        Account manualAcc = TestDataFactory.createAccount('Manual Renewal Account');
        manualAcc.RenewalMode__c = 'Manual';
        manualAcc.RenewalLeadDays__c = 30;
        update manualAcc;

        Product2 prod = TestDataFactory.createProduct('Renewal Widget', 'Recurring', 'Seat', 'Monthly');
        PricebookEntry pbe = TestDataFactory.createStandardPricebookEntry(prod.Id, 60);

        Order autoOrder = TestDataFactory.createOrder(autoAcc.Id, 'Draft');
        OrderItem autoItem = TestDataFactory.createOrderItem(autoOrder.Id, prod.Id, pbe.Id, 1, 60);
        TestDataFactory.activateOrder(autoOrder.Id);
        TestDataFactory.createBillingScheduleForOrder(
            autoOrder.Id, autoAcc.Id, 'Monthly', Date.today().addMonths(-1), Date.today().addDays(10), true
        );
        Subscription__c autoSub = TestDataFactory.createSubscription(autoItem.Id, autoAcc.Id, prod.Id, 'Active');
        autoSub.EndDate__c = Date.today().addDays(10);
        update autoSub;

        Order manualOrder = TestDataFactory.createOrder(manualAcc.Id, 'Draft');
        OrderItem manualItem = TestDataFactory.createOrderItem(manualOrder.Id, prod.Id, pbe.Id, 1, 60);
        TestDataFactory.activateOrder(manualOrder.Id);
        Subscription__c manualSub = TestDataFactory.createSubscription(manualItem.Id, manualAcc.Id, prod.Id, 'Active');
        manualSub.EndDate__c = Date.today().addDays(10);
        update manualSub;
    }

    @isTest
    static void testRenewalSchedulerBatchProcessesAutoAndManual() {
        Test.startTest();
        Database.executeBatch(new RenewalSchedulerBatch(), 50);
        Test.stopTest();

        List<Order> renewalOrders = [SELECT Id FROM Order WHERE RenewalOf__c != null];
        System.assertEquals(1, renewalOrders.size(), 'Auto renewal account should get a cloned Order');

        List<Subscription__c> pendingSubs = [SELECT Status__c, RenewalOrder__c FROM Subscription__c WHERE Status__c = 'Pending Renewal'];
        System.assertEquals(1, pendingSubs.size());
        System.assertNotEquals(null, pendingSubs[0].RenewalOrder__c);

        List<Task> tasks = [SELECT Id FROM Task];
        System.assertEquals(1, tasks.size(), 'Manual renewal account should get a Task instead');
    }

    @isTest
    static void testRenewalSchedulerBatchScheduleDaily() {
        Test.startTest();
        RenewalSchedulerBatch.scheduleDaily();
        Test.stopTest();

        List<CronTrigger> jobs = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = 'RenewalSchedulerBatch - Daily'];
        System.assertEquals(1, jobs.size());
    }

    @isTest
    static void testRenewalServiceNoOpOnEmptyList() {
        Test.startTest();
        RenewalService.processRenewals(new List<Subscription__c>());
        RenewalService.processRenewals(null);
        Test.stopTest();
        System.assert(true, 'Should not throw on empty/null input');
    }

    @isTest
    static void testAutoRenewalWithoutExistingScheduleUsesAccountDefaultFrequency() {
        Account acc = TestDataFactory.createAccount('No Schedule Auto Account');
        acc.RenewalMode__c = 'Auto';
        acc.DefaultBillingFrequency__c = 'Quarterly';
        update acc;

        Product2 prod = [SELECT Id FROM Product2 LIMIT 1];
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :prod.Id LIMIT 1];
        Order ord = TestDataFactory.createOrder(acc.Id, 'Draft');
        OrderItem item = TestDataFactory.createOrderItem(ord.Id, prod.Id, pbe.Id, 1, 60);
        TestDataFactory.activateOrder(ord.Id);
        Subscription__c sub = TestDataFactory.createSubscription(item.Id, acc.Id, prod.Id, 'Active');
        sub.EndDate__c = Date.today().addDays(5);
        update sub;

        Test.startTest();
        Database.executeBatch(new RenewalSchedulerBatch(), 50);
        Test.stopTest();

        List<BillingSchedule__c> newSchedules = [
            SELECT Billing_Frequency__c FROM BillingSchedule__c
            WHERE Account__c = :acc.Id AND Order__c != :ord.Id
        ];
        System.assertEquals(1, newSchedules.size());
        System.assertEquals('Quarterly', newSchedules[0].Billing_Frequency__c);
    }
}
