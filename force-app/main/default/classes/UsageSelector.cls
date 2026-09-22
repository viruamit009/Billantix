public with sharing class UsageSelector {

    public static List<Usage__c> getPendingUsageByOrderItemIds(Set<Id> orderItemIds) {
        return [
            SELECT Id, Order_Item__c, Order__c, Account__c, Product__c,
                   Usage_Date__c, Quantity__c, UOM__c, Status__c
            FROM Usage__c
            WHERE Order_Item__c IN :orderItemIds
            AND Status__c = 'Pending'
        ];
    }

    public static List<Usage__c> getUsageByOrderId(Id orderId) {
        return [
            SELECT Id, Order_Item__c, Order__c, Account__c, Product__c,
                   Usage_Date__c, Quantity__c, UOM__c, Status__c
            FROM Usage__c
            WHERE Order__c = :orderId
            ORDER BY Usage_Date__c ASC
        ];
    }

    public static Map<Id, Decimal> getTotalPendingQuantityByOrderItem(Set<Id> orderItemIds) {
        Map<Id, Decimal> totalByItem = new Map<Id, Decimal>();
        for (AggregateResult ar : [
            SELECT Order_Item__c, SUM(Quantity__c) total
            FROM Usage__c
            WHERE Order_Item__c IN :orderItemIds
            AND Status__c = 'Pending'
            GROUP BY Order_Item__c
        ]) {
            totalByItem.put((Id) ar.get('Order_Item__c'), (Decimal) ar.get('total'));
        }
        return totalByItem;
    }
}
