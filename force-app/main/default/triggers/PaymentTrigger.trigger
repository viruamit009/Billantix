trigger PaymentTrigger on Payment__c (after insert, after update, after delete) {
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            PaymentTriggerHandler.handleAfterInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            PaymentTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isDelete) {
            PaymentTriggerHandler.handleAfterDelete(Trigger.old);
        }
    }
}
