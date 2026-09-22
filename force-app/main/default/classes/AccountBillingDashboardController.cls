public with sharing class AccountBillingDashboardController {

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getOverview(Id accountId) {
        Map<String, Object> result = new Map<String, Object>();

        result.put('activeSubscriptions', [
            SELECT COUNT() FROM Subscription__c
            WHERE Account__c = :accountId AND Status__c = 'Active'
        ]);

        result.put('activeEntitlements', [
            SELECT COUNT() FROM Entitlement__c
            WHERE Account__c = :accountId AND Status__c = 'Active'
        ]);

        AggregateResult[] invAgg = [
            SELECT COUNT(Id) cnt, SUM(BalanceDue__c) totalBalance
            FROM Invoice
            WHERE BillingAccountId = :accountId
            AND CollectionStatus__c NOT IN ('Paid', 'Written Off')
        ];
        result.put('openInvoices',   (Integer) invAgg[0].get('cnt'));
        Decimal bal = (Decimal) invAgg[0].get('totalBalance');
        result.put('totalBalanceDue', bal != null ? bal : 0);

        List<Payment__c> lastPay = [
            SELECT Amount__c, PaymentDate__c
            FROM Payment__c
            WHERE Account__c = :accountId AND Status__c = 'Completed'
            ORDER BY PaymentDate__c DESC LIMIT 1
        ];
        if (!lastPay.isEmpty()) {
            result.put('lastPaymentAmount', lastPay[0].Amount__c);
            result.put('lastPaymentDate',   String.valueOf(lastPay[0].PaymentDate__c));
        }

        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<Order> getOrders(Id accountId) {
        return [
            SELECT Id, OrderNumber, Status, EffectiveDate, TotalAmount, RenewalOf__c
            FROM Order
            WHERE AccountId = :accountId
            ORDER BY EffectiveDate DESC
            LIMIT 50
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Subscription__c> getSubscriptions(Id accountId) {
        return [
            SELECT Id, Name, Product2__r.Name, Status__c, StartDate__c, EndDate__c,
                   BillingSchedule__r.Billing_Frequency__c
            FROM Subscription__c
            WHERE Account__c = :accountId
            ORDER BY StartDate__c DESC
            LIMIT 100
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Entitlement__c> getEntitlements(Id accountId) {
        return [
            SELECT Id, Name, Product2__r.Name, Status__c, StartDate__c, EndDate__c, Quantity__c
            FROM Entitlement__c
            WHERE Account__c = :accountId
            ORDER BY StartDate__c DESC
            LIMIT 100
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Invoice> getInvoices(Id accountId) {
        return [
            SELECT Id, InvoiceNumber, DueDate, TotalAmount, AmountPaid__c, BalanceDue__c,
                   CollectionStatus__c, DaysOverdue__c, Status
            FROM Invoice
            WHERE BillingAccountId = :accountId
            ORDER BY DueDate DESC
            LIMIT 100
        ];
    }
}
