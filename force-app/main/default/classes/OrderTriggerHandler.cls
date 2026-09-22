public with sharing class OrderTriggerHandler {

    public static void handleAfterUpdate(
        List<Order> newList,
        Map<Id, Order> oldMap
    ) {
        Set<Id> activatedOrderIds = new Set<Id>();

        for (Order ord : newList) {
            if (ord.Status == 'Activated' && oldMap.get(ord.Id).Status != 'Activated') {
                activatedOrderIds.add(ord.Id);
            }
        }

        if (!activatedOrderIds.isEmpty()) {
            OrderActivationService.processActivatedOrders(activatedOrderIds);
        }
    }
}
