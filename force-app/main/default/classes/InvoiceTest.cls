// NOTE: Invoice.createable=false on this org — confirmed via `sf sobject
// describe` and a clean isolated insert probe (fails identically regardless
// of Status value). Apex DML can never insert an Invoice record here. This
// blocks full coverage of InvoiceBatch's invoice-creation path and of
// InvoiceGeneratorController methods that require an existing Invoice
// (getInvoiceData/postInvoice/cancelInvoice). Tracked as a separate defect —
// see PR description. These tests intentionally avoid creating any
// BillingSchedule__c due today, since InvoiceBatch running for real (batch
// and scheduled jobs execute synchronously at Test.stopTest()) would hit
// that same insert failure.
@isTest
public class InvoiceTest {

    @isTest
    static void testInvoiceBatchScheduleDaily() {
        Test.startTest();
        InvoiceBatch.scheduleDaily();
        Test.stopTest();

        List<CronTrigger> jobs = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = 'InvoiceBatch - Daily'];
        System.assertEquals(1, jobs.size());
    }

    @isTest
    static void testInvoiceGeneratorControllerRunBatchAndScheduledJobs() {
        Test.startTest();
        String jobId = InvoiceGeneratorController.runInvoiceBatch();
        List<Map<String, Object>> scheduled = InvoiceGeneratorController.getScheduledJobs();
        Test.stopTest();

        System.assertNotEquals(null, jobId);
        System.assertNotEquals(null, scheduled);
    }

    @isTest
    static void testInvoiceGeneratorControllerScheduleInvoiceBatch() {
        Test.startTest();
        String jobId = InvoiceGeneratorController.scheduleInvoiceBatch('0 0 3 * * ?', 'Custom Invoice Job');
        Test.stopTest();

        System.assertNotEquals(null, jobId);
        List<CronTrigger> jobs = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = 'Custom Invoice Job'];
        System.assertEquals(1, jobs.size());
    }

    @isTest
    static void testInvoiceGeneratorControllerScheduleInvoiceBatchDefaultName() {
        Test.startTest();
        String jobId = InvoiceGeneratorController.scheduleInvoiceBatch('0 0 4 * * ?', null);
        Test.stopTest();

        System.assertNotEquals(null, jobId);
    }

    // Exercises InvoiceBatch's real query/grouping/line-building logic (everything
    // up to the point it tries to insert an Invoice) by setting up genuinely due
    // billing data. The insert itself fails with the known Invoice restriction —
    // this documents that failure rather than hiding it, while still covering
    // all the reachable logic before it.
    @isTest
    static void testInvoiceBatchBuildsLinesThenHitsKnownInvoiceRestriction() {
        Account acc = TestDataFactory.createAccount('Invoice Batch Due Account');

        Product2 recurringProd = TestDataFactory.createProduct('Due Recurring', 'Recurring', 'Seat', 'Monthly');
        Product2 usageProd = TestDataFactory.createProduct('Due Usage', 'Usage-Based', 'API Call', 'Monthly');
        PricebookEntry recurringPbe = TestDataFactory.createStandardPricebookEntry(recurringProd.Id, 30);
        PricebookEntry usagePbe = TestDataFactory.createStandardPricebookEntry(usageProd.Id, 2);

        Order ord = TestDataFactory.createOrder(acc.Id, 'Draft');
        OrderItem recurringItem = TestDataFactory.createOrderItem(ord.Id, recurringProd.Id, recurringPbe.Id, 2, 30);
        OrderItem usageItem = TestDataFactory.createOrderItem(ord.Id, usageProd.Id, usagePbe.Id, 1, 2);
        TestDataFactory.activateOrder(ord.Id);

        TestDataFactory.createUsage(ord.Id, usageItem.Id, acc.Id, usageProd.Id, 15, 'Pending');
        TestDataFactory.createBillingScheduleForOrder(
            ord.Id, acc.Id, 'Monthly', Date.today(), Date.today().addMonths(6), false
        );

        // The batch's execute() runs synchronously at Test.stopTest(), so the
        // Invoice-creation restriction surfaces as a DmlException there. The
        // exact message varies by validation layer (INVALID_STATUS vs
        // FIELD_INTEGRITY_EXCEPTION) depending on the Status value used, but
        // Invoice can never be inserted via Apex on this org either way.
        Boolean threwExpectedDmlFailure = false;
        Test.startTest();
        Database.executeBatch(new InvoiceBatch(), 50);
        try {
            Test.stopTest();
        } catch (DmlException e) {
            threwExpectedDmlFailure = e.getMessage().contains('Invoice');
        }

        System.assertEquals(true, threwExpectedDmlFailure,
            'Expected the known Invoice-creation restriction to fail this batch');
    }
}
