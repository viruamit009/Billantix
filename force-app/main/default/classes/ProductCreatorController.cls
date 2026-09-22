public with sharing class ProductCreatorController {

    @AuraEnabled
    public static Id createProduct(String productData, Decimal unitPrice) {
        try {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(productData);

            Product2 product = new Product2(
                Name                 = (String)  data.get('Name'),
                ProductCode          = (String)  data.get('ProductCode'),
                Description          = (String)  data.get('Description'),
                Product_Type__c      = (String)  data.get('Product_Type__c'),
                UOM__c               = (String)  data.get('UOM__c'),
                Billing_Frequency__c = (String)  data.get('Billing_Frequency__c'),
                IsActive             = data.get('IsActive') != null ? (Boolean) data.get('IsActive') : true
            );
            insert product;

            Id standardPricebookId = Test.isRunningTest()
                ? Test.getStandardPricebookId()
                : [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;

            insert new PricebookEntry(
                Product2Id   = product.Id,
                Pricebook2Id = standardPricebookId,
                UnitPrice    = unitPrice,
                IsActive     = true
            );

            return product.Id;

        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Product2> getProducts() {
        return ProductSelector.getActiveProducts();
    }
}
