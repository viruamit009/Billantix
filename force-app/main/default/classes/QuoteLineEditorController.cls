public with sharing class QuoteLineEditorController {

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getQuoteData(Id quoteId) {
        Quote q = [
            SELECT Id, Name, OpportunityId, Opportunity.Name,
                   AccountId, Account.Name, Status, Pricebook2Id, Pricebook2.Name,
                   GrandTotal, TotalPrice, Discount,
                   Start_Date__c, ExpirationDate, Billing_Period__c
            FROM Quote
            WHERE Id = :quoteId
            LIMIT 1
        ];

        List<QuoteLineItem> lines = [
            SELECT Id, Product2Id, Product2.Name, Product2.Product_Type__c,
                   Product2.UOM__c, Product2.Billing_Frequency__c,
                   Quantity, UnitPrice, Discount, TotalPrice,
                   Description, PricebookEntryId
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId
            ORDER BY CreatedDate ASC
        ];

        List<PricebookEntry> entries = new List<PricebookEntry>();
        if (q.Pricebook2Id != null) {
            entries = [
                SELECT Id, Product2Id, Product2.Name, Product2.Product_Type__c,
                       Product2.UOM__c, Product2.Billing_Frequency__c,
                       Product2.IsBundle__c, UnitPrice
                FROM PricebookEntry
                WHERE Pricebook2Id = :q.Pricebook2Id
                AND IsActive = true
                ORDER BY Product2.Name ASC
            ];
        } else {
            // Fall back to Standard Pricebook
            Pricebook2 stdPb = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
            if (stdPb != null) {
                entries = [
                    SELECT Id, Product2Id, Product2.Name, Product2.Product_Type__c,
                           Product2.UOM__c, Product2.Billing_Frequency__c,
                           Product2.IsBundle__c, UnitPrice
                    FROM PricebookEntry
                    WHERE Pricebook2Id = :stdPb.Id
                    AND IsActive = true
                    ORDER BY Product2.Name ASC
                ];
            }
        }

        // Fetch ProductOptions for all bundle products in the pricebook
        Set<Id> bundleProductIds = new Set<Id>();
        for (PricebookEntry e : entries) {
            if (e.Product2.IsBundle__c) bundleProductIds.add(e.Product2Id);
        }
        List<ProductOption__c> productOptions = new List<ProductOption__c>();
        if (!bundleProductIds.isEmpty()) {
            productOptions = [
                SELECT Id, Bundle__c, Component__c, Component__r.Name,
                       Quantity__c, IsOptional__c, Sequence__c
                FROM ProductOption__c
                WHERE Bundle__c IN :bundleProductIds
                ORDER BY Bundle__c, Sequence__c ASC NULLS LAST
            ];
        }

        return new Map<String, Object>{
            'quote'            => q,
            'lines'            => lines,
            'pricebookEntries' => entries,
            'productOptions'   => productOptions
        };
    }

    @AuraEnabled(cacheable=true)
    public static List<PricebookEntry> getEntriesForPricebook(Id pricebook2Id) {
        return [
            SELECT Id, Product2Id, Product2.Name, Product2.Product_Type__c,
                   Product2.UOM__c, Product2.IsBundle__c, UnitPrice
            FROM PricebookEntry
            WHERE Pricebook2Id = :pricebook2Id
            AND IsActive = true
            ORDER BY Product2.Name ASC
        ];
    }

    @AuraEnabled
    public static Id createOrderFromQuote(Id quoteId) {
        try {
            Quote q = [
                SELECT Id, AccountId, Pricebook2Id, Start_Date__c
                FROM Quote
                WHERE Id = :quoteId
                LIMIT 1
            ];

            List<QuoteLineItem> qlis = [
                SELECT Id, Product2Id, PricebookEntryId, Quantity, UnitPrice, Discount, Description
                FROM QuoteLineItem
                WHERE QuoteId = :quoteId
                ORDER BY CreatedDate ASC
            ];

            if (qlis.isEmpty()) {
                throw new AuraHandledException('Cannot create an Order from a Quote with no lines.');
            }

            Order ord = new Order(
                AccountId     = q.AccountId,
                Pricebook2Id  = q.Pricebook2Id,
                EffectiveDate = q.Start_Date__c != null ? q.Start_Date__c : Date.today(),
                Status        = 'Draft'
            );
            insert ord;

            List<OrderItem> items = new List<OrderItem>();
            for (QuoteLineItem qli : qlis) {
                Decimal unitPrice = qli.UnitPrice;
                if (qli.Discount != null && qli.Discount > 0) {
                    unitPrice = unitPrice * (1 - qli.Discount / 100);
                }
                items.add(new OrderItem(
                    OrderId          = ord.Id,
                    Product2Id       = qli.Product2Id,
                    PricebookEntryId = qli.PricebookEntryId,
                    Quantity         = qli.Quantity,
                    UnitPrice        = unitPrice,
                    Description      = qli.Description,
                    QuoteLineItem__c = qli.Id
                ));
            }
            insert items;

            return ord.Id;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void saveQuoteLines(
        Id quoteId,
        String quoteHeaderJson,
        String linesToUpsertJson,
        List<Id> lineIdsToDelete
    ) {
        try {
            // Update quote header fields
            if (String.isNotBlank(quoteHeaderJson)) {
                Map<String, Object> hdr = (Map<String, Object>) JSON.deserializeUntyped(quoteHeaderJson);
                Quote qUpdate = new Quote(Id = quoteId);

                if (hdr.containsKey('Billing_Period__c')) {
                    qUpdate.Billing_Period__c = (String) hdr.get('Billing_Period__c');
                }
                if (hdr.containsKey('Start_Date__c') && hdr.get('Start_Date__c') != null) {
                    qUpdate.Start_Date__c = Date.valueOf((String) hdr.get('Start_Date__c'));
                }
                if (hdr.containsKey('ExpirationDate') && hdr.get('ExpirationDate') != null) {
                    qUpdate.ExpirationDate = Date.valueOf((String) hdr.get('ExpirationDate'));
                }
                if (hdr.containsKey('Pricebook2Id') && hdr.get('Pricebook2Id') != null) {
                    qUpdate.Pricebook2Id = (Id) hdr.get('Pricebook2Id');
                }
                update qUpdate;
            }

            // Delete removed lines
            if (lineIdsToDelete != null && !lineIdsToDelete.isEmpty()) {
                delete [SELECT Id FROM QuoteLineItem WHERE Id IN :lineIdsToDelete AND QuoteId = :quoteId];
            }

            // Insert / Update lines (QuoteId is create-only, not updateable)
            if (String.isNotBlank(linesToUpsertJson)) {
                List<Object> rawLines = (List<Object>) JSON.deserializeUntyped(linesToUpsertJson);
                List<QuoteLineItem> toInsert = new List<QuoteLineItem>();
                List<QuoteLineItem> toUpdate = new List<QuoteLineItem>();

                for (Object raw : rawLines) {
                    Map<String, Object> d = (Map<String, Object>) raw;

                    QuoteLineItem qli    = new QuoteLineItem();
                    String        lineId = (String) d.get('Id');
                    Boolean       isNew  = String.isBlank(lineId) || !lineId.startsWith('0');

                    // Fields editable on both insert and update
                    qli.Quantity    = Decimal.valueOf(String.valueOf(d.get('Quantity')));
                    qli.UnitPrice   = Decimal.valueOf(String.valueOf(d.get('UnitPrice')));
                    qli.Discount    = d.get('Discount') != null
                                      ? Decimal.valueOf(String.valueOf(d.get('Discount'))) : 0;
                    qli.Description = (String) d.get('Description');

                    if (isNew) {
                        // Create-only fields — set on insert only
                        qli.QuoteId          = quoteId;
                        qli.PricebookEntryId = (Id) d.get('PricebookEntryId');
                        qli.Product2Id       = (Id) d.get('Product2Id');
                        toInsert.add(qli);
                    } else {
                        qli.Id = (Id) lineId;
                        toUpdate.add(qli);
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
