public class CollectionsBatch implements Database.Batchable<SObject>, Schedulable {

    // Days overdue thresholds for each dunning level escalation
    private static final Integer LEVEL_1_DAYS = 1;   // first reminder
    private static final Integer LEVEL_2_DAYS = 15;  // warning
    private static final Integer LEVEL_3_DAYS = 30;  // final notice
    private static final Integer COLLECTIONS_DAYS = 60; // escalate to collections

    // -------------------------------------------------------------------------
    // Schedulable
    // -------------------------------------------------------------------------

    public void execute(SchedulableContext ctx) {
        Database.executeBatch(new CollectionsBatch(), 50);
    }

    // -------------------------------------------------------------------------
    // Batchable — query overdue Posted invoices not yet fully paid
    // -------------------------------------------------------------------------

    public Database.QueryLocator start(Database.BatchableContext ctx) {
        return Database.getQueryLocator([
            SELECT Id, InvoiceNumber, BillingAccountId, BillingAccount.Name,
                   BillingAccount.OwnerId,
                   DueDate, TotalAmount, AmountPaid__c, BalanceDue__c,
                   CollectionStatus__c, DunningLevel__c, LastDunningDate__c,
                   DaysOverdue__c
            FROM Invoice
            WHERE Status = 'Posted'
            AND CollectionStatus__c NOT IN ('Paid', 'Written Off')
            AND DueDate < TODAY
        ]);
    }

    public void execute(Database.BatchableContext ctx, List<Invoice> invoices) {
        List<Task>    tasksToInsert    = new List<Task>();
        List<Invoice> invoicesToUpdate = new List<Invoice>();

        for (Invoice inv : invoices) {
            Integer daysOverdue   = inv.DaysOverdue__c != null ? Integer.valueOf(inv.DaysOverdue__c) : 0;
            Integer currentLevel  = inv.DunningLevel__c != null ? Integer.valueOf(inv.DunningLevel__c) : 0;

            // Skip if already dunned today
            if (inv.LastDunningDate__c == Date.today()) continue;

            Integer newLevel = currentLevel;
            String  taskSubject;
            String  taskDescription;
            String  priority = 'Normal';
            String  collectionStatus = inv.CollectionStatus__c;

            if (daysOverdue >= COLLECTIONS_DAYS && currentLevel < 4) {
                newLevel        = 4;
                taskSubject     = 'ESCALATE: Invoice ' + inv.InvoiceNumber + ' — ' + daysOverdue + ' days overdue';
                taskDescription = 'Invoice ' + inv.InvoiceNumber + ' for ' + inv.BillingAccount.Name
                    + ' is ' + daysOverdue + ' days overdue. Balance: $' + inv.BalanceDue__c?.setScale(2)
                    + '. Escalate to collections immediately.';
                priority        = 'High';
                collectionStatus = 'In Collections';

            } else if (daysOverdue >= LEVEL_3_DAYS && currentLevel < 3) {
                newLevel        = 3;
                taskSubject     = 'Final Notice: Invoice ' + inv.InvoiceNumber + ' overdue ' + daysOverdue + ' days';
                taskDescription = 'Final dunning notice for invoice ' + inv.InvoiceNumber + ' ('
                    + inv.BillingAccount.Name + '). Balance due: $' + inv.BalanceDue__c?.setScale(2)
                    + '. Payment must be received immediately to avoid collections.';
                priority        = 'High';

            } else if (daysOverdue >= LEVEL_2_DAYS && currentLevel < 2) {
                newLevel        = 2;
                taskSubject     = 'Warning: Invoice ' + inv.InvoiceNumber + ' overdue ' + daysOverdue + ' days';
                taskDescription = 'Second dunning notice for invoice ' + inv.InvoiceNumber + ' ('
                    + inv.BillingAccount.Name + '). Balance due: $' + inv.BalanceDue__c?.setScale(2)
                    + '. Please follow up with the customer.';
                priority        = 'Normal';

            } else if (daysOverdue >= LEVEL_1_DAYS && currentLevel < 1) {
                newLevel        = 1;
                taskSubject     = 'Reminder: Invoice ' + inv.InvoiceNumber + ' is overdue';
                taskDescription = 'First dunning reminder for invoice ' + inv.InvoiceNumber + ' ('
                    + inv.BillingAccount.Name + '). Balance due: $' + inv.BalanceDue__c?.setScale(2)
                    + '. Please contact the customer to arrange payment.';
                priority        = 'Normal';
            }

            // Only act if level changed
            if (newLevel > currentLevel) {
                tasksToInsert.add(new Task(
                    Subject      = taskSubject,
                    Description  = taskDescription,
                    ActivityDate = Date.today().addDays(3),
                    WhatId       = inv.BillingAccountId,
                    OwnerId      = inv.BillingAccount.OwnerId,
                    Priority     = priority,
                    Status       = 'Not Started'
                ));

                invoicesToUpdate.add(new Invoice(
                    Id                  = inv.Id,
                    DunningLevel__c     = newLevel,
                    LastDunningDate__c  = Date.today(),
                    CollectionStatus__c = collectionStatus
                ));
            }
        }

        if (!tasksToInsert.isEmpty())    insert tasksToInsert;
        if (!invoicesToUpdate.isEmpty()) update invoicesToUpdate;
    }

    public void finish(Database.BatchableContext ctx) {
        // Reserved for post-batch notifications
    }

    // -------------------------------------------------------------------------
    // Convenience — schedule to run daily at 2 AM
    // -------------------------------------------------------------------------

    public static void scheduleDaily() {
        String cronExp = '0 0 2 * * ?';
        System.schedule('CollectionsBatch - Daily', cronExp, new CollectionsBatch());
    }
}
