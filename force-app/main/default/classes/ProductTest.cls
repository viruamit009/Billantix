@isTest
public class ProductTest {

    @isTest
    static void testProductCreatorControllerCreateAndGet() {
        String productJson = '{"Name":"Created Widget","ProductCode":"CW-1","Description":"desc",'
            + '"Product_Type__c":"Recurring","UOM__c":"Seat","Billing_Frequency__c":"Monthly","IsActive":true}';

        Test.startTest();
        Id productId = ProductCreatorController.createProduct(productJson, 25);
        List<Product2> products = ProductCreatorController.getProducts();
        Test.stopTest();

        System.assertNotEquals(null, productId);
        System.assertEquals(1, products.size());

        List<PricebookEntry> entries = [SELECT UnitPrice FROM PricebookEntry WHERE Product2Id = :productId];
        System.assertEquals(1, entries.size());
        System.assertEquals(25, entries[0].UnitPrice);
    }

    @isTest
    static void testProductSelectorMethods() {
        Product2 prod1 = TestDataFactory.createProduct('Selector Widget 1', 'Recurring', 'Seat', 'Monthly');
        Product2 prod2 = TestDataFactory.createProduct('Selector Widget 2', 'Flat Fee', 'Unit', 'One-Time');
        PricebookEntry pbe1 = TestDataFactory.createStandardPricebookEntry(prod1.Id, 10);

        Test.startTest();
        List<Product2> byIds = ProductSelector.getProductsByIds(new Set<Id>{ prod1.Id, prod2.Id });
        List<Product2> active = ProductSelector.getActiveProducts();
        List<PricebookEntry> byProductAndPricebook = ProductSelector.getPricebookEntriesByProductIds(
            new Set<Id>{ prod1.Id }, Test.getStandardPricebookId()
        );
        List<PricebookEntry> standardEntries = ProductSelector.getStandardPricebookEntries(new Set<Id>{ prod1.Id });
        Test.stopTest();

        System.assertEquals(2, byIds.size());
        System.assertEquals(2, active.size());
        System.assertEquals(1, byProductAndPricebook.size());
        System.assertNotEquals(null, standardEntries);
    }
}
