public with sharing class OrderLineEditorController {

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getOrderData(Id orderId) {
        Order ord = [
            SELECT Id, OrderNumber, AccountId, Account.Name, Status,
                   Pricebook2Id, TotalAmount,
                   (
                       SELECT Id, Product2Id, Product2.Name, Product2.Product_Type__c,
                              Product2.UOM__c, Product2.Billing_Frequency__c,
                              Quantity, UnitPrice, TotalPrice, Description, PricebookEntryId
                       FROM OrderItems
                       ORDER BY CreatedDate ASC
                   )
            FROM Order
            WHERE Id = :orderId
            LIMIT 1
        ];

        List<PricebookEntry> entries = new List<PricebookEntry>();
        if (ord.Pricebook2Id != null) {
            entries = [
                SELECT Id, Product2Id, Product2.Name, Product2.Product_Type__c,
                       Product2.UOM__c, Product2.Billing_Frequency__c,
                       Product2.IsBundle__c, UnitPrice
                FROM PricebookEntry
                WHERE Pricebook2Id = :ord.Pricebook2Id
                AND IsActive = true
                ORDER BY Product2.Name ASC
            ];
        }

        // Fetch ProductOptions for bundle products
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

        BillingSchedule__c schedule = BillingScheduleSelector.getScheduleByOrderId(orderId);

        // Aggregate pending usage for usage-based items
        Set<Id> usageItemIds = new Set<Id>();
        for (OrderItem item : ord.OrderItems) {
            if (item.Product2.Product_Type__c == 'Usage-Based') {
                usageItemIds.add(item.Id);
            }
        }
        Map<Id, Decimal> usageTotals = usageItemIds.isEmpty()
            ? new Map<Id, Decimal>()
            : UsageSelector.getTotalPendingQuantityByOrderItem(usageItemIds);

        return new Map<String, Object>{
            'order'            => ord,
            'lines'            => ord.OrderItems,
            'pricebookEntries' => entries,
            'productOptions'   => productOptions,
            'billingSchedule'  => schedule,
            'usageTotals'      => usageTotals
        };
    }

    @AuraEnabled
    public static void activateOrder(Id orderId) {
        try {
            Order ord = [SELECT Id, Status FROM Order WHERE Id = :orderId LIMIT 1];
            if (ord.Status == 'Activated') {
                throw new AuraHandledException('Order is already activated.');
            }
            ord.Status = 'Activated';
            update ord;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static Id createOrderFromQuote(Id quoteId) {
        Quote q = [SELECT Id, Name, AccountId, OpportunityId, Pricebook2Id FROM Quote WHERE Id = :quoteId LIMIT 1];
        Order ord = new Order(
            Name          = 'Order for ' + q.Name,
            AccountId     = q.AccountId,
            OpportunityId = q.OpportunityId,
            Pricebook2Id  = q.Pricebook2Id,
            Status        = 'Draft',
            EffectiveDate = Date.today()
        );
        insert ord;
        return ord.Id;
    }

    @AuraEnabled
    public static void saveOrderLines(Id orderId, String linesToUpsertJson, List<Id> lineIdsToDelete) {
        Order ord = [SELECT Id, Status FROM Order WHERE Id = :orderId LIMIT 1];
        if (ord.Status != 'Draft') {
            throw new AuraHandledException('Order lines can only be modified when the Order is in Draft status.');
        }

        try {
            if (lineIdsToDelete != null && !lineIdsToDelete.isEmpty()) {
                delete [SELECT Id FROM OrderItem WHERE Id IN :lineIdsToDelete AND OrderId = :orderId];
            }

            if (String.isNotBlank(linesToUpsertJson)) {
                List<Object> rawLines = (List<Object>) JSON.deserializeUntyped(linesToUpsertJson);
                List<OrderItem> toUpsert = new List<OrderItem>();

                for (Object raw : rawLines) {
                    Map<String, Object> d = (Map<String, Object>) raw;

                    OrderItem item = new OrderItem();
                    String itemId = (String) d.get('Id');
                    if (String.isNotBlank(itemId) && itemId.startsWith('0')) {
                        item.Id = (Id) itemId;
                    }

                    item.OrderId          = orderId;
                    item.PricebookEntryId = (Id)     d.get('PricebookEntryId');
                    item.Product2Id       = (Id)     d.get('Product2Id');
                    item.Quantity         = Decimal.valueOf(String.valueOf(d.get('Quantity')));
                    item.UnitPrice        = Decimal.valueOf(String.valueOf(d.get('UnitPrice')));
                    item.Description      = (String) d.get('Description');

                    toUpsert.add(item);
                }

                upsert toUpsert;
            }
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}
