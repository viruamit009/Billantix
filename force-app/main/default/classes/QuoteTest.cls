@isTest
public class QuoteTest {

    @TestSetup
    static void setup() {
        // This org's actual Standard Price Book is IsActive=false, and Pricebook2
        // rows aren't visible in test context without SeeAllData=true — activate
        // it within the test transaction so getActivePricebooks() can see it.
        update new Pricebook2(Id = Test.getStandardPricebookId(), IsActive = true);

        Account acc = TestDataFactory.createAccount('Quote Test Account');
        Opportunity opp = TestDataFactory.createOpportunity(acc.Id);
        Product2 prod = TestDataFactory.createProduct('Quote Widget', 'Recurring', 'Seat', 'Monthly');
        TestDataFactory.createStandardPricebookEntry(prod.Id, 40);
    }

    @isTest
    static void testQuoteCreatorControllerFlow() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Opportunity opp = [SELECT Id, Pricebook2Id FROM Opportunity LIMIT 1];

        Test.startTest();
        List<Pricebook2> pbs = QuoteCreatorController.getActivePricebooks();
        Opportunity fetched = QuoteCreatorController.getOpportunity(opp.Id);
        Id quoteId = QuoteCreatorController.createQuote(
            opp.Id, 'My Quote', 'desc', String.valueOf(Date.today()),
            String.valueOf(Date.today().addDays(30)), Test.getStandardPricebookId(),
            '123 Main St', 'City', 'State', '12345', 'US'
        );
        Quote fetchedQuote = QuoteCreatorController.getQuoteGeneralInfo(quoteId);
        QuoteCreatorController.saveQuoteGeneralInfo(quoteId, '{"Description":"updated"}');
        Test.stopTest();

        System.assertNotEquals(null, fetched);
        System.assertNotEquals(0, pbs.size());
        System.assertNotEquals(null, fetchedQuote);

        Quote reloaded = [SELECT Description FROM Quote WHERE Id = :quoteId];
        System.assertEquals('updated', reloaded.Description);
    }

    @isTest
    static void testQuoteLineEditorControllerFlowAndOrderCreation() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Product2 prod = [SELECT Id FROM Product2 LIMIT 1];
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :prod.Id LIMIT 1];

        Quote q = TestDataFactory.createQuote(opp.Id, acc.Id);
        TestDataFactory.createQuoteLineItem(q.Id, prod.Id, pbe.Id, 2, 40);

        Test.startTest();
        Map<String, Object> data = QuoteLineEditorController.getQuoteData(q.Id);
        List<PricebookEntry> entries = QuoteLineEditorController.getEntriesForPricebook(Test.getStandardPricebookId());
        Id orderId = QuoteLineEditorController.createOrderFromQuote(q.Id);
        Test.stopTest();

        System.assertEquals(true, data.containsKey('lines'));
        System.assertNotEquals(0, entries.size());

        List<OrderItem> items = [SELECT Id, QuoteLineItem__c FROM OrderItem WHERE OrderId = :orderId];
        System.assertEquals(1, items.size());
        System.assertNotEquals(null, items[0].QuoteLineItem__c);
    }

    @isTest
    static void testQuoteLineEditorControllerCreateOrderWithNoLinesThrows() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Quote q = TestDataFactory.createQuote(opp.Id, acc.Id);

        Boolean threw = false;
        Test.startTest();
        try {
            QuoteLineEditorController.createOrderFromQuote(q.Id);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw);
    }

    @isTest
    static void testQuoteLineEditorControllerSaveQuoteLines() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Product2 prod = [SELECT Id FROM Product2 LIMIT 1];
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :prod.Id LIMIT 1];

        Quote q = TestDataFactory.createQuote(opp.Id, acc.Id);
        QuoteLineItem existing = TestDataFactory.createQuoteLineItem(q.Id, prod.Id, pbe.Id, 1, 40);

        String linesJson = '[{"Id":"' + existing.Id + '","Quantity":3,"UnitPrice":45,"Discount":10,"Description":"updated line"},'
            + '{"Quantity":1,"UnitPrice":20,"Discount":0,"Description":"new line",'
            + '"PricebookEntryId":"' + pbe.Id + '","Product2Id":"' + prod.Id + '"}]';

        Test.startTest();
        QuoteLineEditorController.saveQuoteLines(
            q.Id,
            '{"Billing_Period__c":"Monthly","Start_Date__c":"' + String.valueOf(Date.today()) + '"}',
            linesJson,
            new List<Id>()
        );
        Test.stopTest();

        List<QuoteLineItem> lines = [SELECT Id, Quantity FROM QuoteLineItem WHERE QuoteId = :q.Id];
        System.assertEquals(2, lines.size());
    }
}
