/**
 * Central factory for building test records. Keeps @TestSetup blocks free of
 * inline record construction and provides consistent, reusable test data.
 */
@isTest
public class TestDataFactory {
    /**
     * Builds Accounts with a controllable Active__c flag.
     *
     * @param count Number of Accounts to build.
     * @param isActive Value for the Account.Active__c checkbox.
     * @param doInsert Whether to insert the records before returning them.
     * @return The list of built (and optionally inserted) Accounts.
     */
    public static List<Account> createAccounts(Integer count, Boolean isActive, Boolean doInsert) {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            accounts.add(new Account(
                Name = 'Test Account ' + i,
                Active__c = isActive
            ));
        }
        if (doInsert) {
            insert accounts;
        }
        return accounts;
    }

    /**
     * Builds Contacts linked to the supplied Account.
     *
     * @param count Number of Contacts to build.
     * @param accountId The parent Account for every Contact.
     * @param doInsert Whether to insert the records before returning them.
     * @return The list of built (and optionally inserted) Contacts.
     */
    public static List<Contact> createContacts(Integer count, Id accountId, Boolean doInsert) {
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < count; i++) {
            contacts.add(new Contact(
                LastName = 'Tester ' + i,
                Email = 'tester' + i + '@example.com',
                Department = 'Sales',
                AccountId = accountId
            ));
        }
        if (doInsert) {
            insert contacts;
        }
        return contacts;
    }

    /**
     * Builds Opportunities.
     *
     * @param count Number of Opportunities to build.
     * @param doInsert Whether to insert the records before returning them.
     * @return The list of built (and optionally inserted) Opportunities.
     */
    public static List<Opportunity> createOpportunities(Integer count, Boolean doInsert) {
        List<Opportunity> opportunities = new List<Opportunity>();
        for (Integer i = 0; i < count; i++) {
            opportunities.add(new Opportunity(
                Name = 'Test Opportunity ' + i,
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30)
            ));
        }
        if (doInsert) {
            insert opportunities;
        }
        return opportunities;
    }
}
