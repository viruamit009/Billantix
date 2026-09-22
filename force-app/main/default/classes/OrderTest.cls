@isTest
public class OrderTest {

    @TestSetup
    static void setup() {
        Account acc = TestDataFactory.createAccount('Order Test Account');

        Product2 recurringProd = TestDataFactory.createProduct('Recurring Widget', 'Recurring', 'Seat', 'Monthly');
        Product2 flatFeeProd = TestDataFactory.createProduct('Setup Fee', 'Flat Fee', 'Unit', 'One-Time');
        PricebookEntry recurringPbe = TestDataFactory.createStandardPricebookEntry(recurringProd.Id, 50);
        PricebookEntry flatFeePbe = TestDataFactory.createStandardPricebookEntry(flatFeeProd.Id, 200);

        Order ord = TestDataFactory.createOrder(acc.Id, 'Draft');
        TestDataFactory.createOrderItem(ord.Id, recurringProd.Id, recurringPbe.Id, 3, 50);
        TestDataFactory.createOrderItem(ord.Id, flatFeeProd.Id, flatFeePbe.Id, 1, 200);

        TestDataFactory.createBillingScheduleForOrder(
            ord.Id, acc.Id, 'Monthly', Date.today(), Date.today().addMonths(12), false
        );
    }

    @isTest
    static void testOrderActivationCreatesSubscriptionsAndEntitlements() {
        Order ord = [SELECT Id, Status FROM Order LIMIT 1];

        Test.startTest();
        ord.Status = 'Activated';
        update ord;
        Test.stopTest();

        List<Subscription__c> subs = [SELECT Id FROM Subscription__c];
        List<Entitlement__c> ents = [SELECT Id FROM Entitlement__c];
        System.assertEquals(1, subs.size(), 'Recurring line should create a Subscription');
        System.assertEquals(1, ents.size(), 'Flat fee line should create an Entitlement');
    }

    @isTest
    static void testOrderActivationIsIdempotentOnNonStatusChange() {
        Order ord = [SELECT Id, Status, Description FROM Order LIMIT 1];
        ord.Status = 'Activated';
        update ord;

        Test.startTest();
        ord.Description = 'no-op update';
        update ord;
        Test.stopTest();

        List<Subscription__c> subs = [SELECT Id FROM Subscription__c];
        System.assertEquals(1, subs.size(), 'Re-updating an already activated order should not duplicate Subscriptions');
    }

    @isTest
    static void testOrderSelectorMethods() {
        Order ord = [SELECT Id, AccountId, Status FROM Order LIMIT 1];
        ord.Status = 'Activated';
        update ord;

        Test.startTest();
        List<Order> activeOrders = OrderSelector.getActiveOrdersWithItems(new Set<Id>{ ord.Id });
        Order single = OrderSelector.getOrderWithItems(ord.Id);
        List<Order> byAccount = OrderSelector.getActivatedOrdersByAccountId(ord.AccountId);
        Test.stopTest();

        System.assertEquals(1, activeOrders.size());
        System.assertNotEquals(null, single);
        System.assertEquals(1, byAccount.size());
    }

    @isTest
    static void testOrderControllerCreateAndUpdate() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Opportunity opp = TestDataFactory.createOpportunity(acc.Id);
        Quote q = TestDataFactory.createQuote(opp.Id, acc.Id);
        Product2 prod = [SELECT Id FROM Product2 LIMIT 1];
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :prod.Id LIMIT 1];
        TestDataFactory.createQuoteLineItem(q.Id, prod.Id, pbe.Id, 2, 75);

        Test.startTest();
        Id orderId = OrderController.createOrder(q.Id, '{"Status":"Draft"}', true);
        OrderController.saveOrderGeneralInfo(orderId, '{"Description":"Updated via test"}');
        Order fetched = OrderController.getOrderGeneralInfo(orderId);
        Quote fetchedQuote = OrderController.getQuoteForOrder(q.Id);
        Map<String, Object> data = OrderController.getOrderData(orderId);
        Test.stopTest();

        System.assertEquals('Updated via test', fetched.Description);
        System.assertNotEquals(null, fetchedQuote);
        System.assertEquals(true, data.containsKey('lines'));

        List<OrderItem> items = [SELECT Id FROM OrderItem WHERE OrderId = :orderId];
        System.assertEquals(1, items.size(), 'copyLines=true should copy the quote line onto the order');
    }

    @isTest
    static void testOrderControllerSaveOrderLines() {
        Order ord = [SELECT Id FROM Order LIMIT 1];
        Product2 newProd = TestDataFactory.createProduct('Extra Widget', 'Flat Fee', 'Unit', 'One-Time');
        PricebookEntry newPbe = TestDataFactory.createStandardPricebookEntry(newProd.Id, 99);

        String linesJson = '[{"Quantity":1,"UnitPrice":99,"Description":"New line",'
            + '"PricebookEntryId":"' + newPbe.Id + '","Product2Id":"' + newProd.Id + '"}]';

        Test.startTest();
        OrderController.saveOrderLines(ord.Id, '{"Description":"header update"}', linesJson, new List<Id>());
        Test.stopTest();

        List<OrderItem> items = [SELECT Id, UnitPrice FROM OrderItem WHERE OrderId = :ord.Id AND Product2Id = :newProd.Id];
        System.assertEquals(1, items.size());
    }

    @isTest
    static void testOrderLineEditorControllerFlow() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Opportunity opp = TestDataFactory.createOpportunity(acc.Id);
        Quote q = TestDataFactory.createQuote(opp.Id, acc.Id);

        Test.startTest();
        Id orderId = OrderLineEditorController.createOrderFromQuote(q.Id);
        Map<String, Object> data = OrderLineEditorController.getOrderData(orderId);
        Test.stopTest();

        System.assertNotEquals(null, orderId);
        System.assertEquals(true, data.containsKey('pricebookEntries'));
    }

    @isTest
    static void testOrderLineEditorControllerSaveLinesAndActivate() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Order ord = TestDataFactory.createOrder(acc.Id, 'Draft');
        Product2 prod = [SELECT Id FROM Product2 LIMIT 1];
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :prod.Id LIMIT 1];

        String linesJson = '[{"Quantity":2,"UnitPrice":50,"Description":"line 1",'
            + '"PricebookEntryId":"' + pbe.Id + '","Product2Id":"' + prod.Id + '"}]';

        Test.startTest();
        OrderLineEditorController.saveOrderLines(ord.Id, linesJson, new List<Id>());
        OrderLineEditorController.activateOrder(ord.Id);
        Test.stopTest();

        Order updated = [SELECT Status FROM Order WHERE Id = :ord.Id];
        System.assertEquals('Activated', updated.Status);
    }

    @isTest
    static void testOrderLineEditorControllerActivateAlreadyActivatedThrows() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Product2 prod = [SELECT Id FROM Product2 LIMIT 1];
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :prod.Id LIMIT 1];
        Order ord = TestDataFactory.createOrder(acc.Id, 'Draft');
        TestDataFactory.createOrderItem(ord.Id, prod.Id, pbe.Id, 1, 10);
        TestDataFactory.activateOrder(ord.Id);

        Boolean threw = false;
        Test.startTest();
        try {
            OrderLineEditorController.activateOrder(ord.Id);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw);
    }

    @isTest
    static void testOrderLineEditorControllerSaveLinesOnNonDraftThrows() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Product2 prod = [SELECT Id FROM Product2 LIMIT 1];
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :prod.Id LIMIT 1];
        Order ord = TestDataFactory.createOrder(acc.Id, 'Draft');
        TestDataFactory.createOrderItem(ord.Id, prod.Id, pbe.Id, 1, 10);
        TestDataFactory.activateOrder(ord.Id);

        Boolean threw = false;
        Test.startTest();
        try {
            OrderLineEditorController.saveOrderLines(ord.Id, '[]', new List<Id>());
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw);
    }
}
