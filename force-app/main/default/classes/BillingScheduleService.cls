public with sharing class BillingScheduleService {

    public static BillingSchedule__c getEffectiveSchedule(Order ord) {
        BillingSchedule__c schedule = BillingScheduleSelector.getScheduleByOrderId(ord.Id);
        if (schedule == null && ord.AccountId != null) {
            schedule = BillingScheduleSelector.getScheduleByAccountId(ord.AccountId);
        }
        return schedule;
    }

    public static Date calculateNextBillingDate(Date fromDate, String frequency) {
        if (frequency == 'Monthly') {
            return fromDate.addMonths(1);
        }
        if (frequency == 'Quarterly') {
            return fromDate.addMonths(3);
        }
        if (frequency == 'Annual') {
            return fromDate.addMonths(12);
        }
        return null;
    }

    public static void advanceSchedule(BillingSchedule__c schedule) {
        Date nextDate = calculateNextBillingDate(
            schedule.Next_Billing_Date__c,
            schedule.Billing_Frequency__c
        );

        Boolean pastEndDate = nextDate != null
            && schedule.End_Date__c != null
            && nextDate > schedule.End_Date__c;

        if (nextDate == null || pastEndDate) {
            if (schedule.Auto_Renew__c && schedule.End_Date__c != null) {
                schedule.End_Date__c = calculateNextBillingDate(
                    schedule.End_Date__c,
                    schedule.Billing_Frequency__c
                );
                schedule.Next_Billing_Date__c = nextDate;
            } else {
                schedule.Status__c = 'Completed';
                schedule.Next_Billing_Date__c = nextDate;
            }
        } else {
            schedule.Next_Billing_Date__c = nextDate;
        }
    }

    public static BillingSchedule__c createForOrder(
        Id orderId,
        Id accountId,
        String frequency,
        Date startDate,
        Date endDate,
        Boolean autoRenew
    ) {
        BillingSchedule__c schedule = new BillingSchedule__c(
            Order__c = orderId,
            Account__c = accountId,
            Billing_Frequency__c = frequency,
            Start_Date__c = startDate,
            End_Date__c = endDate,
            Next_Billing_Date__c = startDate,
            Status__c = 'Active',
            Auto_Renew__c = autoRenew != null ? autoRenew : false
        );
        insert schedule;
        return schedule;
    }

    public static BillingSchedule__c createForAccount(
        Id accountId,
        String frequency,
        Date startDate,
        Date endDate,
        Boolean autoRenew
    ) {
        BillingSchedule__c schedule = new BillingSchedule__c(
            Account__c = accountId,
            Billing_Frequency__c = frequency,
            Start_Date__c = startDate,
            End_Date__c = endDate,
            Next_Billing_Date__c = startDate,
            Status__c = 'Active',
            Auto_Renew__c = autoRenew != null ? autoRenew : false
        );
        insert schedule;
        return schedule;
    }
}
