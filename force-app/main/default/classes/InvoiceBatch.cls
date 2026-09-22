public class InvoiceBatch implements Database.Batchable<SObject>, Schedulable {

    // Entry point for Schedulable — run nightly or monthly
    public void execute(SchedulableContext ctx) {
        Database.executeBatch(new InvoiceBatch(), 50);
    }

    // Query all active schedules due today or overdue
    public Database.QueryLocator start(Database.BatchableContext ctx) {
        return Database.getQueryLocator([
            SELECT Id, Name, Account__c, Order__c, Billing_Frequency__c,
                   Start_Date__c, End_Date__c, Next_Billing_Date__c,
                   Status__c, Auto_Renew__c
            FROM BillingSchedule__c
            WHERE Status__c = 'Active'
            AND Next_Billing_Date__c <= TODAY
        ]);
    }

    public void execute(Database.BatchableContext ctx, List<BillingSchedule__c> schedules) {

        // Collect Order IDs from schedules that have an Order reference
        Set<Id> orderIds = new Set<Id>();
        for (BillingSchedule__c schedule : schedules) {
            if (schedule.Order__c != null) {
                orderIds.add(schedule.Order__c);
            }
        }

        // Load orders with their line items
        Map<Id, Order> orderMap = new Map<Id, Order>(
            OrderSelector.getActiveOrdersWithItems(orderIds)
        );

        // Collect OrderItem IDs for usage-based products only
        Set<Id> usageOrderItemIds = new Set<Id>();
        for (Order ord : orderMap.values()) {
            for (OrderItem item : ord.OrderItems) {
                if (item.Product2.Product_Type__c == 'Usage-Based') {
                    usageOrderItemIds.add(item.Id);
                }
            }
        }

        // Load pending usage records grouped by OrderItem
        Map<Id, List<Usage__c>> usageByOrderItem = new Map<Id, List<Usage__c>>();
        if (!usageOrderItemIds.isEmpty()) {
            for (Usage__c usage : UsageSelector.getPendingUsageByOrderItemIds(usageOrderItemIds)) {
                if (!usageByOrderItem.containsKey(usage.Order_Item__c)) {
                    usageByOrderItem.put(usage.Order_Item__c, new List<Usage__c>());
                }
                usageByOrderItem.get(usage.Order_Item__c).add(usage);
            }
        }

        List<Invoice> invoicesToInsert = new List<Invoice>();
        List<InvoiceLine> invoiceLinesToInsert = new List<InvoiceLine>();
        List<Id> lineOrderItemIds = new List<Id>(); // parallel to invoiceLinesToInsert
        List<BillingSchedule__c> schedulesToUpdate = new List<BillingSchedule__c>();
        List<Usage__c> usagesToMarkInvoiced = new List<Usage__c>();

        // Map index → schedule so we can link invoice lines after insert
        Map<Integer, BillingSchedule__c> indexToSchedule = new Map<Integer, BillingSchedule__c>();

        for (BillingSchedule__c schedule : schedules) {
            if (schedule.Order__c == null) continue;
            Order ord = orderMap.get(schedule.Order__c);
            if (ord == null || ord.OrderItems == null || ord.OrderItems.isEmpty()) continue;

            Invoice inv = new Invoice(
                BillingAccountId = ord.AccountId,
                InvoiceDate = schedule.Next_Billing_Date__c,
                DueDate = schedule.Next_Billing_Date__c.addDays(30),
                Status = 'Draft',
                Description = 'Invoice — Order ' + ord.OrderNumber
                    + ' (' + schedule.Billing_Frequency__c + ')'
            );

            indexToSchedule.put(invoicesToInsert.size(), schedule);
            invoicesToInsert.add(inv);
        }

        if (invoicesToInsert.isEmpty()) return;

        insert invoicesToInsert;

        // Build invoice lines after we have Invoice IDs
        for (Integer i = 0; i < invoicesToInsert.size(); i++) {
            Invoice inv = invoicesToInsert[i];
            BillingSchedule__c schedule = indexToSchedule.get(i);
            Order ord = orderMap.get(schedule.Order__c);

            for (OrderItem item : ord.OrderItems) {
                Decimal usageQty = 0;

                if (item.Product2.Product_Type__c == 'Usage-Based') {
                    List<Usage__c> usages = usageByOrderItem.get(item.Id);
                    if (usages != null) {
                        for (Usage__c u : usages) {
                            usageQty += u.Quantity__c;
                            u.Status__c = 'Invoiced';
                            usagesToMarkInvoiced.add(u);
                        }
                    }
                    if (usageQty == 0) continue; // no usage to bill
                }

                Decimal lineAmount = PricingService.calculateLineAmount(item, usageQty);

                InvoiceLine line = new InvoiceLine(
                    InvoiceId = inv.Id,
                    Product2Id = item.Product2Id,
                    Quantity = item.Product2.Product_Type__c == 'Usage-Based'
                        ? usageQty
                        : item.Quantity,
                    UnitPrice = item.UnitPrice,
                    Description = item.Product2.Name
                );
                invoiceLinesToInsert.add(line);
                lineOrderItemIds.add(item.Id);
            }

            // Advance Next_Billing_Date or mark Completed
            BillingScheduleService.advanceSchedule(schedule);
            schedulesToUpdate.add(schedule);
        }

        if (!invoiceLinesToInsert.isEmpty()) {
            insert invoiceLinesToInsert;
            backfillInvoiceLineItem(invoiceLinesToInsert, lineOrderItemIds);
        }
        if (!schedulesToUpdate.isEmpty()) update schedulesToUpdate;
        if (!usagesToMarkInvoiced.isEmpty()) update usagesToMarkInvoiced;
    }

    public void finish(Database.BatchableContext ctx) {
        // Reserved for post-batch notifications or logging
    }

    // -------------------------------------------------------------------------
    // After InvoiceLines are inserted, stamp InvoiceLineItem__c on
    // Subscription__c and Entitlement__c records tied to the same OrderItem.
    // -------------------------------------------------------------------------

    private static void backfillInvoiceLineItem(
        List<InvoiceLine> lines,
        List<Id> orderItemIds
    ) {
        // Build OrderItem → InvoiceLine Id map (last line wins if duplicates)
        Map<Id, Id> orderItemToLineId = new Map<Id, Id>();
        for (Integer i = 0; i < lines.size(); i++) {
            orderItemToLineId.put(orderItemIds[i], lines[i].Id);
        }

        Set<Id> trackedOrderItemIds = orderItemToLineId.keySet();

        // Update Subscription__c (only those not yet stamped)
        List<Subscription__c> subsToUpdate = new List<Subscription__c>();
        for (Subscription__c sub : [
            SELECT Id, OrderItem__c
            FROM Subscription__c
            WHERE OrderItem__c IN :trackedOrderItemIds
            AND InvoiceLineItem__c = null
        ]) {
            subsToUpdate.add(new Subscription__c(
                Id                 = sub.Id,
                InvoiceLineItem__c = orderItemToLineId.get(sub.OrderItem__c)
            ));
        }

        // Update Entitlement__c (only those not yet stamped)
        List<Entitlement__c> entsToUpdate = new List<Entitlement__c>();
        for (Entitlement__c ent : [
            SELECT Id, OrderItem__c
            FROM Entitlement__c
            WHERE OrderItem__c IN :trackedOrderItemIds
            AND InvoiceLineItem__c = null
        ]) {
            entsToUpdate.add(new Entitlement__c(
                Id                 = ent.Id,
                InvoiceLineItem__c = orderItemToLineId.get(ent.OrderItem__c)
            ));
        }

        if (!subsToUpdate.isEmpty()) update subsToUpdate;
        if (!entsToUpdate.isEmpty()) update entsToUpdate;
    }

    // Convenience method: schedule to run daily at midnight
    public static void scheduleDaily() {
        String cronExp = '0 0 0 * * ?';
        System.schedule('InvoiceBatch - Daily', cronExp, new InvoiceBatch());
    }
}
