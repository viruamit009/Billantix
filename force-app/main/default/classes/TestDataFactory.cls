@isTest
public class TestDataFactory {

    public static Account createAccount(String name) {
        Account acc = new Account(
            Name = name,
            RenewalMode__c = 'Manual',
            DefaultBillingFrequency__c = 'Monthly',
            RenewalLeadDays__c = 30
        );
        insert acc;
        return acc;
    }

    public static Product2 createProduct(String name, String productType, String uom, String billingFrequency) {
        Product2 prod = new Product2(
            Name = name,
            IsActive = true,
            Product_Type__c = productType,
            UOM__c = uom,
            Billing_Frequency__c = billingFrequency
        );
        insert prod;
        return prod;
    }

    public static PricebookEntry createStandardPricebookEntry(Id productId, Decimal unitPrice) {
        Id standardPricebookId = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Product2Id = productId,
            Pricebook2Id = standardPricebookId,
            UnitPrice = unitPrice,
            IsActive = true
        );
        insert pbe;
        return pbe;
    }

    public static Opportunity createOpportunity(Id accountId) {
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = accountId,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert opp;
        return opp;
    }

    public static Quote createQuote(Id opportunityId, Id accountId) {
        Quote q = new Quote(
            Name = 'Test Quote',
            OpportunityId = opportunityId,
            Pricebook2Id = Test.getStandardPricebookId(),
            Status = 'Draft',
            Start_Date__c = Date.today(),
            ExpirationDate = Date.today().addDays(30)
        );
        insert q;
        return q;
    }

    public static QuoteLineItem createQuoteLineItem(Id quoteId, Id productId, Id pricebookEntryId, Decimal qty, Decimal unitPrice) {
        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = quoteId,
            Product2Id = productId,
            PricebookEntryId = pricebookEntryId,
            Quantity = qty,
            UnitPrice = unitPrice
        );
        insert qli;
        return qli;
    }

    // Always inserts as Draft — Salesforce requires new/cloned Orders to start
    // Draft, and Activated Orders require at least one OrderItem first.
    // Call activateOrder() separately after OrderItems exist.
    public static Order createOrder(Id accountId, String status) {
        Order ord = new Order(
            AccountId = accountId,
            Pricebook2Id = Test.getStandardPricebookId(),
            Status = 'Draft',
            EffectiveDate = Date.today()
        );
        insert ord;
        return ord;
    }

    public static void activateOrder(Id orderId) {
        update new Order(Id = orderId, Status = 'Activated');
    }

    public static OrderItem createOrderItem(Id orderId, Id productId, Id pricebookEntryId, Decimal qty, Decimal unitPrice) {
        OrderItem item = new OrderItem(
            OrderId = orderId,
            Product2Id = productId,
            PricebookEntryId = pricebookEntryId,
            Quantity = qty,
            UnitPrice = unitPrice
        );
        insert item;
        return item;
    }

    public static BillingSchedule__c createBillingScheduleForOrder(
        Id orderId, Id accountId, String frequency, Date startDate, Date endDate, Boolean autoRenew
    ) {
        BillingSchedule__c bs = new BillingSchedule__c(
            Order__c = orderId,
            Account__c = accountId,
            Billing_Frequency__c = frequency,
            Start_Date__c = startDate,
            End_Date__c = endDate,
            Next_Billing_Date__c = startDate,
            Status__c = 'Active',
            Auto_Renew__c = autoRenew
        );
        insert bs;
        return bs;
    }

    public static Invoice createInvoice(Id accountId, String status) {
        Invoice inv = new Invoice(
            BillingAccountId = accountId,
            InvoiceDate = Date.today(),
            DueDate = Date.today().addDays(30),
            Status = status
        );
        insert inv;
        return inv;
    }

    public static InvoiceLine createInvoiceLine(Id invoiceId, Id productId, Decimal qty, Decimal unitPrice) {
        InvoiceLine line = new InvoiceLine(
            InvoiceId = invoiceId,
            Product2Id = productId,
            Quantity = qty,
            UnitPrice = unitPrice
        );
        insert line;
        return line;
    }

    public static Payment__c createPayment(Id accountId, Id invoiceId, Decimal amount, String status) {
        Payment__c pay = new Payment__c(
            Account__c = accountId,
            Invoice__c = invoiceId,
            Amount__c = amount,
            Status__c = status,
            PaymentDate__c = Date.today()
        );
        insert pay;
        return pay;
    }

    public static Subscription__c createSubscription(Id orderItemId, Id accountId, Id productId, String status) {
        Subscription__c sub = new Subscription__c(
            OrderItem__c = orderItemId,
            Account__c = accountId,
            Product2__c = productId,
            StartDate__c = Date.today(),
            EndDate__c = Date.today().addMonths(1),
            Status__c = status
        );
        insert sub;
        return sub;
    }

    public static Entitlement__c createEntitlement(Id orderItemId, Id accountId, Id productId, String status) {
        Entitlement__c ent = new Entitlement__c(
            OrderItem__c = orderItemId,
            Account__c = accountId,
            Product2__c = productId,
            Quantity__c = 1,
            StartDate__c = Date.today(),
            Status__c = status
        );
        insert ent;
        return ent;
    }

    public static Usage__c createUsage(Id orderId, Id orderItemId, Id accountId, Id productId, Decimal quantity, String status) {
        Usage__c usage = new Usage__c(
            Order__c = orderId,
            Order_Item__c = orderItemId,
            Account__c = accountId,
            Product__c = productId,
            Usage_Date__c = Date.today(),
            Quantity__c = quantity,
            Status__c = status
        );
        insert usage;
        return usage;
    }
}
