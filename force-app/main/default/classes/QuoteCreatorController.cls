public with sharing class QuoteCreatorController {

    @AuraEnabled(cacheable=true)
    public static List<Pricebook2> getActivePricebooks() {
        return [SELECT Id, Name FROM Pricebook2 WHERE IsActive = true ORDER BY Name LIMIT 50];
    }

    @AuraEnabled(cacheable=true)
    public static Opportunity getOpportunity(Id opportunityId) {
        return [
            SELECT Id, Name, AccountId, Account.Name, Account.AccountNumber,
                   Account.BillingStreet, Account.BillingCity, Account.BillingState,
                   Account.BillingPostalCode, Account.BillingCountry,
                   Pricebook2Id, CloseDate, StageName, Amount
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];
    }

    @AuraEnabled
    public static Id createQuote(
        Id     opportunityId,
        String quoteName,
        String description,
        String startDate,
        String expirationDate,
        Id     pricebook2Id,
        String billingStreet,
        String billingCity,
        String billingState,
        String billingPostalCode,
        String billingCountry
    ) {
        Opportunity opp = [SELECT Id, Pricebook2Id FROM Opportunity WHERE Id = :opportunityId LIMIT 1];
        Quote q = new Quote(
            OpportunityId = opportunityId,
            Name          = quoteName,
            Status        = 'Draft',
            Pricebook2Id  = pricebook2Id != null ? pricebook2Id : opp.Pricebook2Id
        );
        if (description      != null) q.Description       = description;
        if (expirationDate   != null) q.ExpirationDate    = Date.valueOf(expirationDate);
        if (startDate        != null) q.Start_Date__c     = Date.valueOf(startDate);
        if (billingStreet    != null) q.BillingStreet     = billingStreet;
        if (billingCity      != null) q.BillingCity       = billingCity;
        if (billingState     != null) q.BillingState      = billingState;
        if (billingPostalCode != null) q.BillingPostalCode = billingPostalCode;
        if (billingCountry   != null) q.BillingCountry    = billingCountry;
        insert q;
        return q.Id;
    }

    @AuraEnabled(cacheable=false)
    public static Quote getQuoteGeneralInfo(Id quoteId) {
        return [
            SELECT Id, Name, Description, ExpirationDate, Start_Date__c, Status,
                   AccountId, Account.Name,
                   Pricebook2Id, BillingStreet, BillingCity, BillingState,
                   BillingPostalCode, BillingCountry, ContactId, Contact.Name,
                   OpportunityId, Opportunity.Name, Opportunity.CloseDate, Opportunity.StageName
            FROM Quote
            WHERE Id = :quoteId
            LIMIT 1
        ];
    }

    @AuraEnabled
    public static void saveQuoteGeneralInfo(Id quoteId, String quoteJson) {
        Map<String, Object> f = (Map<String, Object>) JSON.deserializeUntyped(quoteJson);
        Quote q = new Quote(Id = quoteId);
        if (f.containsKey('Name'))             q.Name              = (String) f.get('Name');
        if (f.containsKey('Description'))      q.Description       = (String) f.get('Description');
        if (f.containsKey('ExpirationDate') && f.get('ExpirationDate') != null)
            q.ExpirationDate = Date.valueOf((String) f.get('ExpirationDate'));
        if (f.containsKey('Start_Date__c') && f.get('Start_Date__c') != null)
            q.Start_Date__c  = Date.valueOf((String) f.get('Start_Date__c'));
        if (f.containsKey('Status'))            q.Status            = (String) f.get('Status');
        if (f.containsKey('Pricebook2Id') && f.get('Pricebook2Id') != null)
            q.Pricebook2Id   = (Id) f.get('Pricebook2Id');
        if (f.containsKey('OpportunityId') && f.get('OpportunityId') != null)
            q.OpportunityId  = (Id) f.get('OpportunityId');
        if (f.containsKey('BillingStreet'))     q.BillingStreet     = (String) f.get('BillingStreet');
        if (f.containsKey('BillingCity'))       q.BillingCity       = (String) f.get('BillingCity');
        if (f.containsKey('BillingState'))      q.BillingState      = (String) f.get('BillingState');
        if (f.containsKey('BillingPostalCode')) q.BillingPostalCode = (String) f.get('BillingPostalCode');
        if (f.containsKey('BillingCountry'))    q.BillingCountry    = (String) f.get('BillingCountry');
        update q;
    }
}
