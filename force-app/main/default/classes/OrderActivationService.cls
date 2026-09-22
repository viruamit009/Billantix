public with sharing class OrderActivationService {

    /**
     * Entry point — called from trigger with IDs of newly activated Orders.
     * Bulk-safe: all SOQL in 3 queries regardless of batch size.
     */
    public static void processActivatedOrders(Set<Id> orderIds) {
        if (orderIds == null || orderIds.isEmpty()) return;

        List<Order> orders = OrderSelector.getActiveOrdersWithItems(orderIds);
        if (orders.isEmpty()) return;

        // --- 1. Bulk-fetch Order-level BillingSchedules ---
        Map<Id, BillingSchedule__c> scheduleByOrder = new Map<Id, BillingSchedule__c>();
        Set<Id> accountsNeedingFallback = new Set<Id>();

        for (BillingSchedule__c bs : [
            SELECT Id, Order__c, Account__c, Start_Date__c, End_Date__c,
                   Billing_Frequency__c, Status__c
            FROM BillingSchedule__c
            WHERE Order__c IN :orderIds
            AND Status__c = 'Active'
        ]) {
            scheduleByOrder.put(bs.Order__c, bs);
        }

        for (Order ord : orders) {
            if (!scheduleByOrder.containsKey(ord.Id)) {
                accountsNeedingFallback.add(ord.AccountId);
            }
        }

        // --- 2. Fallback: Account-level BillingSchedules ---
        Map<Id, BillingSchedule__c> scheduleByAccount = new Map<Id, BillingSchedule__c>();
        if (!accountsNeedingFallback.isEmpty()) {
            for (BillingSchedule__c bs : [
                SELECT Id, Account__c, Start_Date__c, End_Date__c,
                       Billing_Frequency__c, Status__c
                FROM BillingSchedule__c
                WHERE Account__c IN :accountsNeedingFallback
                AND Order__c = null
                AND Status__c = 'Active'
            ]) {
                if (!scheduleByAccount.containsKey(bs.Account__c)) {
                    scheduleByAccount.put(bs.Account__c, bs);
                }
            }
        }

        // --- 3. Build Subscription__c and Entitlement__c records ---
        List<Subscription__c> subscriptions = new List<Subscription__c>();
        List<Entitlement__c> entitlements = new List<Entitlement__c>();

        for (Order ord : orders) {
            BillingSchedule__c schedule = scheduleByOrder.containsKey(ord.Id)
                ? scheduleByOrder.get(ord.Id)
                : scheduleByAccount.get(ord.AccountId);

            for (OrderItem item : ord.OrderItems) {
                String productType = item.Product2.Product_Type__c;

                if (productType == 'Recurring' || productType == 'Usage-Based') {
                    subscriptions.add(buildSubscription(item, ord, schedule));
                } else if (productType == 'Flat Fee') {
                    entitlements.add(buildEntitlement(item, ord));
                }
            }
        }

        if (!subscriptions.isEmpty()) insert subscriptions;
        if (!entitlements.isEmpty()) insert entitlements;
    }

    // -------------------------------------------------------------------------

    private static Subscription__c buildSubscription(
        OrderItem item,
        Order ord,
        BillingSchedule__c schedule
    ) {
        Date startDate = (schedule != null && schedule.Start_Date__c != null)
            ? schedule.Start_Date__c
            : ord.EffectiveDate;

        return new Subscription__c(
            OrderItem__c      = item.Id,
            QuoteLineItem__c  = item.QuoteLineItem__c,
            Account__c        = ord.AccountId,
            Product2__c       = item.Product2Id,
            BillingSchedule__c = schedule != null ? schedule.Id : null,
            StartDate__c      = startDate,
            EndDate__c        = schedule != null ? schedule.End_Date__c : null,
            Status__c         = 'Active'
        );
    }

    private static Entitlement__c buildEntitlement(OrderItem item, Order ord) {
        return new Entitlement__c(
            OrderItem__c     = item.Id,
            QuoteLineItem__c = item.QuoteLineItem__c,
            Account__c       = ord.AccountId,
            Product2__c      = item.Product2Id,
            Quantity__c      = item.Quantity,
            StartDate__c     = ord.EffectiveDate,
            Status__c        = 'Active'
        );
    }
}
