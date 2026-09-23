// Pipeline smoke test — verifies Validate/Deploy/Release trigger correctly end to end.
public with sharing class PricingService {

    public static Decimal calculateLineAmount(OrderItem item, Decimal usageQuantity) {
        String productType = item.Product2.Product_Type__c;

        if (productType == 'Flat Fee') {
            return item.UnitPrice;
        }
        if (productType == 'Recurring') {
            return item.UnitPrice * item.Quantity;
        }
        if (productType == 'Usage-Based') {
            return item.UnitPrice * (usageQuantity != null ? usageQuantity : 0);
        }
        return 0;
    }

    public static Decimal applyBillingFrequencyFactor(Decimal baseAmount, String frequency) {
        Map<String, Integer> monthsMap = new Map<String, Integer>{
            'Monthly'  => 1,
            'Quarterly' => 3,
            'Annual'   => 12,
            'One-Time' => 1
        };
        Integer months = monthsMap.containsKey(frequency) ? monthsMap.get(frequency) : 1;
        return baseAmount * months;
    }

    public static Decimal calculateQuoteLineAmount(QuoteLineItem line) {
        return line.UnitPrice * line.Quantity;
    }

    public static Decimal calculateOrderTotal(List<OrderItem> items, Map<Id, Decimal> usageByOrderItem) {
        Decimal total = 0;
        for (OrderItem item : items) {
            Decimal usageQty = usageByOrderItem != null ? usageByOrderItem.get(item.Id) : null;
            total += calculateLineAmount(item, usageQty != null ? usageQty : 0);
        }
        return total;
    }
}
