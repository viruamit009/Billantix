public with sharing class InvoiceGeneratorController {

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getInvoiceData(Id invoiceId) {
        Invoice inv = [
            SELECT Id, InvoiceNumber, BillingAccountId, BillingAccount.Name, Status,
                   InvoiceDate, DueDate, TotalAmount, Description
            FROM Invoice
            WHERE Id = :invoiceId
            LIMIT 1
        ];

        List<InvoiceLine> lines = [
            SELECT Id, Product2Id, Product2.Name, Product2.Product_Type__c,
                   Product2.UOM__c, Quantity, UnitPrice, LineAmount, Description
            FROM InvoiceLine
            WHERE InvoiceId = :invoiceId
            ORDER BY CreatedDate ASC
        ];

        return new Map<String, Object>{
            'invoice' => inv,
            'lines'   => lines
        };
    }

    @AuraEnabled
    public static void postInvoice(Id invoiceId) {
        Invoice inv = [SELECT Id, Status FROM Invoice WHERE Id = :invoiceId LIMIT 1];
        if (inv.Status != 'Draft') {
            throw new AuraHandledException('Only Draft invoices can be posted.');
        }
        inv.Status = 'Posted';
        update inv;
    }

    @AuraEnabled
    public static void cancelInvoice(Id invoiceId) {
        Invoice inv = [SELECT Id, Status FROM Invoice WHERE Id = :invoiceId LIMIT 1];
        if (inv.Status == 'Cancelled') {
            throw new AuraHandledException('Invoice is already cancelled.');
        }
        inv.Status = 'Cancelled';
        update inv;
    }

    @AuraEnabled
    public static String runInvoiceBatch() {
        Id jobId = Database.executeBatch(new InvoiceBatch(), 50);
        return jobId;
    }

    @AuraEnabled
    public static String scheduleInvoiceBatch(String cronExpression, String jobName) {
        String name = String.isNotBlank(jobName) ? jobName : 'InvoiceBatch - ' + System.now().format();
        return System.schedule(name, cronExpression, new InvoiceBatch());
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getScheduledJobs() {
        List<Map<String, Object>> jobs = new List<Map<String, Object>>();
        for (CronTrigger ct : [
            SELECT Id, CronJobDetail.Name, State, NextFireTime, PreviousFireTime, CronExpression
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'InvoiceBatch%'
            AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING')
            ORDER BY NextFireTime ASC
        ]) {
            jobs.add(new Map<String, Object>{
                'id'               => ct.Id,
                'name'             => ct.CronJobDetail.Name,
                'state'            => ct.State,
                'nextFireTime'     => ct.NextFireTime,
                'previousFireTime' => ct.PreviousFireTime,
                'cronExpression'   => ct.CronExpression
            });
        }
        return jobs;
    }
}
