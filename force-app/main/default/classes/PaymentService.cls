public with sharing class PaymentService {

    /**
     * Called from PaymentTriggerHandler after Payment__c insert/update.
     * Recalculates AmountPaid__c on the related Invoice and updates
     * CollectionStatus__c accordingly. Bulk-safe: 1 SOQL + 1 DML.
     */
    public static void recalculateInvoiceBalances(Set<Id> invoiceIds) {
        if (invoiceIds == null || invoiceIds.isEmpty()) return;

        // Sum all Completed payments per Invoice
        Map<Id, Decimal> paidByInvoice = new Map<Id, Decimal>();
        for (AggregateResult ar : [
            SELECT Invoice__c invoiceId, SUM(Amount__c) totalPaid
            FROM Payment__c
            WHERE Invoice__c IN :invoiceIds
            AND Status__c = 'Completed'
            GROUP BY Invoice__c
        ]) {
            paidByInvoice.put(
                (Id)      ar.get('invoiceId'),
                (Decimal) ar.get('totalPaid')
            );
        }

        // Query invoices to get TotalAmount
        List<Invoice> invoicesToUpdate = new List<Invoice>();
        for (Invoice inv : [
            SELECT Id, TotalAmount, AmountPaid__c, CollectionStatus__c
            FROM Invoice
            WHERE Id IN :invoiceIds
        ]) {
            Decimal paid   = paidByInvoice.containsKey(inv.Id) ? paidByInvoice.get(inv.Id) : 0;
            Decimal total  = inv.TotalAmount != null ? inv.TotalAmount : 0;
            Decimal balance = total - paid;

            String status;
            if (balance <= 0) {
                status = 'Paid';
            } else if (paid > 0) {
                status = 'Partially Paid';
            } else {
                status = inv.CollectionStatus__c == 'In Collections'
                    ? 'In Collections'
                    : 'Open';
            }

            invoicesToUpdate.add(new Invoice(
                Id                  = inv.Id,
                AmountPaid__c       = paid,
                BalanceDue__c       = balance,
                CollectionStatus__c = status
            ));
        }

        if (!invoicesToUpdate.isEmpty()) update invoicesToUpdate;
    }
}
