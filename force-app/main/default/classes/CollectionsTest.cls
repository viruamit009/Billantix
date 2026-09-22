// NOTE: Invoice.createable=false on this org, so CollectionsBatch's core
// dunning-escalation logic (which requires querying real Posted invoices)
// can't be exercised here. This covers what's reachable without a real
// Invoice — see PR description for the tracked Invoice-creation defect.
@isTest
public class CollectionsTest {

    @isTest
    static void testCollectionsBatchRunsWithNoInvoices() {
        Test.startTest();
        Database.executeBatch(new CollectionsBatch(), 50);
        Test.stopTest();

        List<Task> tasks = [SELECT Id FROM Task];
        System.assertEquals(0, tasks.size(), 'No invoices exist, so no dunning tasks should be created');
    }

    @isTest
    static void testCollectionsBatchScheduleDaily() {
        Test.startTest();
        CollectionsBatch.scheduleDaily();
        Test.stopTest();

        List<CronTrigger> jobs = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = 'CollectionsBatch - Daily'];
        System.assertEquals(1, jobs.size());
    }
}
