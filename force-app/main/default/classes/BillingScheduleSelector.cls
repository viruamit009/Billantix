public with sharing class BillingScheduleSelector {

    public static List<BillingSchedule__c> getActiveSchedulesDueForBilling() {
        return [
            SELECT Id, Name, Account__c, Order__c, Billing_Frequency__c,
                   Start_Date__c, End_Date__c, Next_Billing_Date__c,
                   Status__c, Auto_Renew__c
            FROM BillingSchedule__c
            WHERE Status__c = 'Active'
            AND Next_Billing_Date__c <= TODAY
        ];
    }

    public static BillingSchedule__c getScheduleByOrderId(Id orderId) {
        List<BillingSchedule__c> schedules = [
            SELECT Id, Name, Account__c, Order__c, Billing_Frequency__c,
                   Start_Date__c, End_Date__c, Next_Billing_Date__c,
                   Status__c, Auto_Renew__c
            FROM BillingSchedule__c
            WHERE Order__c = :orderId
            AND Status__c = 'Active'
            LIMIT 1
        ];
        return schedules.isEmpty() ? null : schedules[0];
    }

    public static BillingSchedule__c getScheduleByAccountId(Id accountId) {
        List<BillingSchedule__c> schedules = [
            SELECT Id, Name, Account__c, Order__c, Billing_Frequency__c,
                   Start_Date__c, End_Date__c, Next_Billing_Date__c,
                   Status__c, Auto_Renew__c
            FROM BillingSchedule__c
            WHERE Account__c = :accountId
            AND Order__c = null
            AND Status__c = 'Active'
            LIMIT 1
        ];
        return schedules.isEmpty() ? null : schedules[0];
    }

    public static List<BillingSchedule__c> getSchedulesByAccountId(Id accountId) {
        return [
            SELECT Id, Name, Account__c, Order__c, Billing_Frequency__c,
                   Start_Date__c, End_Date__c, Next_Billing_Date__c,
                   Status__c, Auto_Renew__c
            FROM BillingSchedule__c
            WHERE Account__c = :accountId
            ORDER BY CreatedDate DESC
        ];
    }
}
