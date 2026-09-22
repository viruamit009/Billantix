public with sharing class ProductSelector {

    public static List<Product2> getProductsByIds(Set<Id> productIds) {
        return [
            SELECT Id, Name, Product_Type__c, UOM__c, Billing_Frequency__c, IsActive,
                   Description, ProductCode
            FROM Product2
            WHERE Id IN :productIds
        ];
    }

    public static List<Product2> getActiveProducts() {
        return [
            SELECT Id, Name, Product_Type__c, UOM__c, Billing_Frequency__c, IsActive,
                   Description, ProductCode
            FROM Product2
            WHERE IsActive = true
            ORDER BY Name ASC
        ];
    }

    public static List<PricebookEntry> getPricebookEntriesByProductIds(Set<Id> productIds, Id pricebookId) {
        return [
            SELECT Id, Product2Id, UnitPrice, Pricebook2Id, IsActive
            FROM PricebookEntry
            WHERE Product2Id IN :productIds
            AND Pricebook2Id = :pricebookId
            AND IsActive = true
        ];
    }

    public static List<PricebookEntry> getStandardPricebookEntries(Set<Id> productIds) {
        return [
            SELECT Id, Product2Id, UnitPrice, Pricebook2Id, IsActive
            FROM PricebookEntry
            WHERE Product2Id IN :productIds
            AND Pricebook2.IsStandard = true
            AND IsActive = true
        ];
    }
}
