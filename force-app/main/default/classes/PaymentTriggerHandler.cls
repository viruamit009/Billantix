public with sharing class PaymentTriggerHandler {

    public static void handleAfterInsert(List<Payment__c> newList) {
        PaymentService.recalculateInvoiceBalances(collectInvoiceIds(newList, null));
    }

    public static void handleAfterUpdate(
        List<Payment__c> newList,
        Map<Id, Payment__c> oldMap
    ) {
        // Only recalculate if Amount, Status, or Invoice changed
        Set<Id> affected = new Set<Id>();
        for (Payment__c pay : newList) {
            Payment__c old = oldMap.get(pay.Id);
            if (pay.Amount__c     != old.Amount__c  ||
                pay.Status__c     != old.Status__c   ||
                pay.Invoice__c    != old.Invoice__c) {

                affected.add(pay.Invoice__c);
                if (old.Invoice__c != null) affected.add(old.Invoice__c);
            }
        }
        if (!affected.isEmpty()) PaymentService.recalculateInvoiceBalances(affected);
    }

    public static void handleAfterDelete(List<Payment__c> oldList) {
        PaymentService.recalculateInvoiceBalances(collectInvoiceIds(oldList, null));
    }

    private static Set<Id> collectInvoiceIds(List<Payment__c> payments, Map<Id, Payment__c> oldMap) {
        Set<Id> ids = new Set<Id>();
        for (Payment__c pay : payments) {
            if (pay.Invoice__c != null) ids.add(pay.Invoice__c);
        }
        return ids;
    }
}
