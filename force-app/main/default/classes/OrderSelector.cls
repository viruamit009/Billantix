public with sharing class OrderSelector {

    public static List<Order> getActiveOrdersWithItems(Set<Id> orderIds) {
        return [
            SELECT Id, AccountId, Pricebook2Id, Status, OrderNumber, EffectiveDate,
                   (
                       SELECT Id, Product2Id, Quantity, UnitPrice, TotalPrice,
                              QuoteLineItem__c,
                              Product2.Name, Product2.Product_Type__c,
                              Product2.UOM__c, Product2.Billing_Frequency__c
                       FROM OrderItems
                   )
            FROM Order
            WHERE Id IN :orderIds
            AND Status = 'Activated'
        ];
    }

    public static Order getOrderWithItems(Id orderId) {
        List<Order> orders = [
            SELECT Id, AccountId, Pricebook2Id, Status, OrderNumber, EffectiveDate,
                   (
                       SELECT Id, Product2Id, Quantity, UnitPrice, TotalPrice,
                              QuoteLineItem__c,
                              Product2.Name, Product2.Product_Type__c,
                              Product2.UOM__c, Product2.Billing_Frequency__c
                       FROM OrderItems
                   )
            FROM Order
            WHERE Id = :orderId
            LIMIT 1
        ];
        return orders.isEmpty() ? null : orders[0];
    }

    public static List<Order> getActivatedOrdersByAccountId(Id accountId) {
        return [
            SELECT Id, AccountId, Pricebook2Id, Status, OrderNumber
            FROM Order
            WHERE AccountId = :accountId
            AND Status = 'Activated'
            ORDER BY CreatedDate DESC
        ];
    }
}
