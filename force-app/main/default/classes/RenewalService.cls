public with sharing class RenewalService {

    /**
     * Entry point from batch execute().
     * Splits subscriptions by Account renewal mode and dispatches.
     */
    public static void processRenewals(List<Subscription__c> subscriptions) {
        if (subscriptions == null || subscriptions.isEmpty()) return;

        List<Subscription__c> autoSubs   = new List<Subscription__c>();
        List<Subscription__c> manualSubs = new List<Subscription__c>();

        for (Subscription__c sub : subscriptions) {
            if (sub.Account__r.RenewalMode__c == 'Auto') {
                autoSubs.add(sub);
            } else {
                manualSubs.add(sub);
            }
        }

        if (!autoSubs.isEmpty())   processAutoRenewals(autoSubs);
        if (!manualSubs.isEmpty()) processManualRenewals(manualSubs);
    }

    // =========================================================================
    // AUTO RENEWAL — clone Order + OrderItems, create BillingSchedule
    // =========================================================================

    private static void processAutoRenewals(List<Subscription__c> subscriptions) {

        // --- Collect original OrderItem IDs ---
        Set<Id> orderItemIds = new Set<Id>();
        for (Subscription__c sub : subscriptions) {
            orderItemIds.add(sub.OrderItem__c);
        }

        // --- Query original OrderItems with Order data (1 SOQL) ---
        Map<Id, OrderItem> orderItemMap = new Map<Id, OrderItem>([
            SELECT Id, OrderId, Product2Id, PricebookEntryId, Quantity, UnitPrice,
                   QuoteLineItem__c,
                   Order.Id, Order.AccountId, Order.Pricebook2Id, Order.EffectiveDate
            FROM OrderItem
            WHERE Id IN :orderItemIds
        ]);

        // --- Group subscriptions by original Order ID ---
        Map<Id, List<Subscription__c>> subsByOriginalOrder = new Map<Id, List<Subscription__c>>();
        for (Subscription__c sub : subscriptions) {
            OrderItem oi = orderItemMap.get(sub.OrderItem__c);
            if (oi == null) continue;
            if (!subsByOriginalOrder.containsKey(oi.OrderId)) {
                subsByOriginalOrder.put(oi.OrderId, new List<Subscription__c>());
            }
            subsByOriginalOrder.get(oi.OrderId).add(sub);
        }

        Set<Id> originalOrderIds = subsByOriginalOrder.keySet();

        // --- Fetch BillingSchedules for original Orders (1 SOQL) ---
        Map<Id, BillingSchedule__c> scheduleByOriginalOrder = new Map<Id, BillingSchedule__c>();
        for (BillingSchedule__c bs : [
            SELECT Id, Order__c, Account__c, Billing_Frequency__c,
                   Start_Date__c, End_Date__c, Auto_Renew__c
            FROM BillingSchedule__c
            WHERE Order__c IN :originalOrderIds
            AND Status__c = 'Active'
        ]) {
            scheduleByOriginalOrder.put(bs.Order__c, bs);
        }

        // --- Build new Orders (one per original Order) ---
        List<Id> orderedKeys   = new List<Id>(originalOrderIds);
        List<Order> newOrders  = new List<Order>();

        for (Id originalOrderId : orderedKeys) {
            List<Subscription__c> subs = subsByOriginalOrder.get(originalOrderId);
            OrderItem sample = orderItemMap.get(subs[0].OrderItem__c);

            Date newStart = subs[0].EndDate__c != null ? subs[0].EndDate__c : Date.today();

            newOrders.add(new Order(
                AccountId    = sample.Order.AccountId,
                Pricebook2Id = sample.Order.Pricebook2Id,
                EffectiveDate = newStart,
                Status       = 'Draft',
                RenewalOf__c = originalOrderId
            ));
        }

        insert newOrders;

        // --- Build OrderItems, BillingSchedules, Subscription updates ---
        List<OrderItem>          newItems      = new List<OrderItem>();
        List<BillingSchedule__c> newSchedules  = new List<BillingSchedule__c>();
        List<Subscription__c>    subsToUpdate  = new List<Subscription__c>();

        BillantixSettings__c settings = BillantixSettings__c.getOrgDefaults();

        for (Integer i = 0; i < orderedKeys.size(); i++) {
            Id originalOrderId          = orderedKeys[i];
            Order newOrder              = newOrders[i];
            List<Subscription__c> subs  = subsByOriginalOrder.get(originalOrderId);
            BillingSchedule__c oldSched = scheduleByOriginalOrder.get(originalOrderId);

            Date newStart = newOrder.EffectiveDate;
            String freq   = deriveFrequency(subs[0], oldSched);
            Date newEnd   = BillingScheduleService.calculateNextBillingDate(newStart, freq);
            if (newEnd != null) {
                newEnd = newEnd.addDays(-1);
            }

            // Clone OrderItems
            for (Subscription__c sub : subs) {
                OrderItem origItem = orderItemMap.get(sub.OrderItem__c);
                if (origItem == null) continue;
                newItems.add(new OrderItem(
                    OrderId         = newOrder.Id,
                    Product2Id      = origItem.Product2Id,
                    PricebookEntryId = origItem.PricebookEntryId,
                    Quantity        = origItem.Quantity,
                    UnitPrice       = origItem.UnitPrice
                ));
            }

            // New BillingSchedule
            newSchedules.add(new BillingSchedule__c(
                Order__c            = newOrder.Id,
                Account__c          = subs[0].Account__c,
                Billing_Frequency__c = freq,
                Start_Date__c       = newStart,
                End_Date__c         = newEnd,
                Next_Billing_Date__c = newStart,
                Status__c           = 'Active',
                Auto_Renew__c       = oldSched != null ? oldSched.Auto_Renew__c : false
            ));

            // Mark subscriptions Pending Renewal
            for (Subscription__c sub : subs) {
                subsToUpdate.add(new Subscription__c(
                    Id             = sub.Id,
                    Status__c      = 'Pending Renewal',
                    RenewalOrder__c = newOrder.Id
                ));
            }
        }

        if (!newItems.isEmpty())     insert newItems;
        if (!newSchedules.isEmpty()) insert newSchedules;
        if (!subsToUpdate.isEmpty()) update subsToUpdate;

        // Auto-activate renewal Orders if setting is enabled
        if (settings != null && settings.AutoActivateRenewalOrder__c) {
            for (Order ord : newOrders) {
                ord.Status = 'Activated';
            }
            update newOrders;
        }
    }

    // =========================================================================
    // MANUAL RENEWAL — create Task for Account owner
    // =========================================================================

    private static void processManualRenewals(List<Subscription__c> subscriptions) {
        List<Task> tasks = new List<Task>();

        for (Subscription__c sub : subscriptions) {
            Date dueDate = sub.EndDate__c != null
                ? sub.EndDate__c.addDays(-7)
                : Date.today();

            tasks.add(new Task(
                Subject      = 'Review renewal — subscription ending ' + sub.EndDate__c?.format(),
                ActivityDate = dueDate,
                WhatId       = sub.Account__c,
                OwnerId      = sub.Account__r.OwnerId,
                Priority     = 'High',
                Status       = 'Not Started',
                Description  = 'Subscription ' + sub.Name + ' ends on ' + sub.EndDate__c?.format()
                    + '. Please review and create a renewal order manually.'
            ));
        }

        if (!tasks.isEmpty()) insert tasks;
    }

    // =========================================================================
    // HELPERS
    // =========================================================================

    private static String deriveFrequency(
        Subscription__c sub,
        BillingSchedule__c oldSchedule
    ) {
        if (oldSchedule != null && String.isNotBlank(oldSchedule.Billing_Frequency__c)) {
            return oldSchedule.Billing_Frequency__c;
        }
        if (String.isNotBlank(sub.Account__r.DefaultBillingFrequency__c)) {
            return sub.Account__r.DefaultBillingFrequency__c;
        }
        BillantixSettings__c settings = BillantixSettings__c.getOrgDefaults();
        if (settings != null && String.isNotBlank(settings.DefaultBillingFrequency__c)) {
            return settings.DefaultBillingFrequency__c;
        }
        return 'Monthly';
    }
}
