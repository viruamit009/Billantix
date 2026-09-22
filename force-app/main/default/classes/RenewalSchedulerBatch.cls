public class RenewalSchedulerBatch implements Database.Batchable<SObject>, Schedulable {

    // Maximum look-ahead window — subscriptions ending within this many days
    // are eligible for renewal processing. Each Account's RenewalLeadDays__c
    // is checked again in execute() for precise filtering.
    private static final Integer MAX_LOOKAHEAD_DAYS = 90;

    // -------------------------------------------------------------------------
    // Schedulable
    // -------------------------------------------------------------------------

    public void execute(SchedulableContext ctx) {
        Database.executeBatch(new RenewalSchedulerBatch(), 50);
    }

    // -------------------------------------------------------------------------
    // Batchable
    // -------------------------------------------------------------------------

    public Database.QueryLocator start(Database.BatchableContext ctx) {
        Date cutoff = Date.today().addDays(MAX_LOOKAHEAD_DAYS);
        return Database.getQueryLocator([
            SELECT Id, Name, OrderItem__c, Account__c, Product2__c,
                   BillingSchedule__c, StartDate__c, EndDate__c,
                   Status__c, RenewalOrder__c,
                   Account__r.RenewalMode__c,
                   Account__r.RenewalLeadDays__c,
                   Account__r.DefaultBillingFrequency__c,
                   Account__r.OwnerId
            FROM Subscription__c
            WHERE Status__c = 'Active'
            AND RenewalOrder__c = null
            AND EndDate__c != null
            AND EndDate__c <= :cutoff
        ]);
    }

    public void execute(
        Database.BatchableContext ctx,
        List<Subscription__c> subscriptions
    ) {
        BillantixSettings__c settings = BillantixSettings__c.getOrgDefaults();
        Integer defaultLeadDays = (settings != null && settings.DefaultRenewalLeadDays__c != null)
            ? Integer.valueOf(settings.DefaultRenewalLeadDays__c)
            : 30;

        // Filter to only subscriptions that are due for renewal action today
        List<Subscription__c> dueForRenewal = new List<Subscription__c>();
        for (Subscription__c sub : subscriptions) {
            Integer leadDays = (sub.Account__r.RenewalLeadDays__c != null)
                ? Integer.valueOf(sub.Account__r.RenewalLeadDays__c)
                : defaultLeadDays;

            Date triggerDate = sub.EndDate__c.addDays(-leadDays);
            if (triggerDate <= Date.today()) {
                dueForRenewal.add(sub);
            }
        }

        if (!dueForRenewal.isEmpty()) {
            RenewalService.processRenewals(dueForRenewal);
        }
    }

    public void finish(Database.BatchableContext ctx) {
        // Reserved for post-run notifications or logging
    }

    // -------------------------------------------------------------------------
    // Convenience — schedule to run daily at 1 AM
    // -------------------------------------------------------------------------

    public static void scheduleDaily() {
        String cronExp = '0 0 1 * * ?';
        System.schedule('RenewalSchedulerBatch - Daily', cronExp, new RenewalSchedulerBatch());
    }
}
