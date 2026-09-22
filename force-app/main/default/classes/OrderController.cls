public with sharing class OrderController {

    @AuraEnabled(cacheable=true)
    public static Quote getQuoteForOrder(Id quoteId) {
        return [
            SELECT Id, Name, QuoteNumber, AccountId, Account.Name,
                   OpportunityId, Opportunity.Name,
                   Pricebook2Id, Start_Date__c, ExpirationDate,
                   BillingStreet, BillingCity, BillingState,
                   BillingPostalCode, BillingCountry
            FROM Quote
            WHERE Id = :quoteId
            LIMIT 1
        ];
    }

    @AuraEnabled(cacheable=false)
    public static Order getOrderGeneralInfo(Id orderId) {
        return [
            SELECT Id, OrderNumber, AccountId, Account.Name,
                   OpportunityId, Opportunity.Name,
                   Pricebook2Id, EffectiveDate, EndDate, Status, Description,
                   BillingStreet, BillingCity, BillingState,
                   BillingPostalCode, BillingCountry
            FROM Order
            WHERE Id = :orderId
            LIMIT 1
        ];
    }

    @AuraEnabled
    public static Id createOrder(Id quoteId, String orderJson, Boolean copyLines) {
        Map<String, Object> f = (Map<String, Object>) JSON.deserializeUntyped(orderJson);
        Quote q = [
            SELECT AccountId, Pricebook2Id, OpportunityId,
                   Start_Date__c, ExpirationDate,
                   BillingStreet, BillingCity, BillingState,
                   BillingPostalCode, BillingCountry
            FROM Quote
            WHERE Id = :quoteId
            LIMIT 1
        ];

        Order ord = new Order(
            AccountId     = q.AccountId,
            Pricebook2Id  = f.get('Pricebook2Id') != null ? (Id) f.get('Pricebook2Id') : q.Pricebook2Id,
            Status        = f.get('Status') != null ? (String) f.get('Status') : 'Draft',
            EffectiveDate = f.get('EffectiveDate') != null
                            ? Date.valueOf((String) f.get('EffectiveDate')) : Date.today()
        );
        if (q.OpportunityId != null) ord.OpportunityId = q.OpportunityId;
        if (f.get('EndDate') != null) {
            Date endDate = Date.valueOf((String) f.get('EndDate'));
            if (endDate >= ord.EffectiveDate) ord.EndDate = endDate;
        }
        if (f.get('Description')    != null) ord.Description   = (String) f.get('Description');
        if (f.get('BillingStreet')  != null) ord.BillingStreet = (String) f.get('BillingStreet');
        if (f.get('BillingCity')    != null) ord.BillingCity   = (String) f.get('BillingCity');
        if (f.get('BillingState')   != null) ord.BillingState  = (String) f.get('BillingState');
        if (f.get('BillingPostalCode') != null) ord.BillingPostalCode = (String) f.get('BillingPostalCode');
        if (f.get('BillingCountry') != null) ord.BillingCountry = (String) f.get('BillingCountry');
        insert ord;

        if (copyLines == true && quoteId != null) {
            List<QuoteLineItem> qlis = [
                SELECT Product2Id, PricebookEntryId, Quantity, UnitPrice, Description
                FROM QuoteLineItem
                WHERE QuoteId = :quoteId
                ORDER BY SortOrder ASC NULLS LAST
            ];
            if (!qlis.isEmpty()) {
                List<OrderItem> items = new List<OrderItem>();
                for (QuoteLineItem qli : qlis) {
                    items.add(new OrderItem(
                        OrderId          = ord.Id,
                        Product2Id       = qli.Product2Id,
                        PricebookEntryId = qli.PricebookEntryId,
                        Quantity         = qli.Quantity,
                        UnitPrice        = qli.UnitPrice,
                        Description      = qli.Description
                    ));
                }
                insert items;
            }
        }

        return ord.Id;
    }

    @AuraEnabled
    public static void saveOrderGeneralInfo(Id orderId, String orderJson) {
        Map<String, Object> f = (Map<String, Object>) JSON.deserializeUntyped(orderJson);
        Order ord = new Order(Id = orderId);
        if (f.get('Status')        != null) ord.Status        = (String) f.get('Status');
        if (f.get('Description')   != null) ord.Description   = (String) f.get('Description');
        if (f.get('OpportunityId') != null) ord.OpportunityId = (Id) f.get('OpportunityId');
        if (f.get('EffectiveDate') != null)
            ord.EffectiveDate = Date.valueOf((String) f.get('EffectiveDate'));
        if (f.get('EndDate') != null)
            ord.EndDate = Date.valueOf((String) f.get('EndDate'));
        if (f.get('BillingStreet')     != null) ord.BillingStreet     = (String) f.get('BillingStreet');
        if (f.get('BillingCity')       != null) ord.BillingCity       = (String) f.get('BillingCity');
        if (f.get('BillingState')      != null) ord.BillingState      = (String) f.get('BillingState');
        if (f.get('BillingPostalCode') != null) ord.BillingPostalCode = (String) f.get('BillingPostalCode');
        if (f.get('BillingCountry')    != null) ord.BillingCountry    = (String) f.get('BillingCountry');
        update ord;
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getOrderData(Id orderId) {
        Order o = [
            SELECT Id, OrderNumber, AccountId, Account.Name,
                   Pricebook2Id, EffectiveDate, EndDate, Status
            FROM Order
            WHERE Id = :orderId
            LIMIT 1
        ];

        List<OrderItem> items = [
            SELECT Id, Product2Id, Product2.Name, Product2.Product_Type__c,
                   Product2.IsBundle__c, PricebookEntryId,
                   PricebookEntry.UnitPrice,
                   UnitPrice, Quantity, TotalPrice, Description
            FROM OrderItem
            WHERE OrderId = :orderId
            ORDER BY CreatedDate ASC
        ];

        List<PricebookEntry> entries = new List<PricebookEntry>();
        if (o.Pricebook2Id != null) {
            entries = [
                SELECT Id, Product2Id, Product2.Name, Product2.Product_Type__c,
                       Product2.UOM__c, Product2.IsBundle__c, UnitPrice
                FROM PricebookEntry
                WHERE Pricebook2Id = :o.Pricebook2Id
                AND IsActive = true
                ORDER BY Product2.Name ASC
            ];
        } else {
            Pricebook2 stdPb = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
            if (stdPb != null) {
                entries = [
                    SELECT Id, Product2Id, Product2.Name, Product2.Product_Type__c,
                           Product2.UOM__c, Product2.IsBundle__c, UnitPrice
                    FROM PricebookEntry
                    WHERE Pricebook2Id = :stdPb.Id
                    AND IsActive = true
                    ORDER BY Product2.Name ASC
                ];
            }
        }

        return new Map<String, Object>{
            'order'            => o,
            'lines'            => items,
            'pricebookEntries' => entries
        };
    }

    @AuraEnabled
    public static void saveOrderLines(
        Id orderId,
        String orderHeaderJson,
        String linesToUpsertJson,
        List<Id> lineIdsToDelete
    ) {
        try {
            if (String.isNotBlank(orderHeaderJson)) {
                Map<String, Object> hdr = (Map<String, Object>) JSON.deserializeUntyped(orderHeaderJson);
                Order oUpdate = new Order(Id = orderId);
                if (hdr.containsKey('EffectiveDate') && hdr.get('EffectiveDate') != null)
                    oUpdate.EffectiveDate = Date.valueOf((String) hdr.get('EffectiveDate'));
                if (hdr.containsKey('EndDate') && hdr.get('EndDate') != null)
                    oUpdate.EndDate = Date.valueOf((String) hdr.get('EndDate'));
                if (hdr.containsKey('Pricebook2Id') && hdr.get('Pricebook2Id') != null)
                    oUpdate.Pricebook2Id = (Id) hdr.get('Pricebook2Id');
                update oUpdate;
            }

            if (lineIdsToDelete != null && !lineIdsToDelete.isEmpty()) {
                delete [SELECT Id FROM OrderItem WHERE Id IN :lineIdsToDelete AND OrderId = :orderId];
            }

            if (String.isNotBlank(linesToUpsertJson)) {
                List<Object> rawLines = (List<Object>) JSON.deserializeUntyped(linesToUpsertJson);
                List<OrderItem> toInsert = new List<OrderItem>();
                List<OrderItem> toUpdate = new List<OrderItem>();

                for (Object raw : rawLines) {
                    Map<String, Object> d = (Map<String, Object>) raw;
                    OrderItem item = new OrderItem();
                    String lineId = (String) d.get('Id');
                    Boolean isNew = String.isBlank(lineId);

                    item.Quantity    = Decimal.valueOf(String.valueOf(d.get('Quantity')));
                    item.UnitPrice   = Decimal.valueOf(String.valueOf(d.get('UnitPrice')));
                    item.Description = (String) d.get('Description');

                    if (isNew) {
                        item.OrderId          = orderId;
                        item.PricebookEntryId = (Id) d.get('PricebookEntryId');
                        item.Product2Id       = (Id) d.get('Product2Id');
                        toInsert.add(item);
                    } else {
                        item.Id = (Id) lineId;
                        toUpdate.add(item);
                    }
                }

                if (!toInsert.isEmpty()) insert toInsert;
                if (!toUpdate.isEmpty()) update toUpdate;
            }
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}
