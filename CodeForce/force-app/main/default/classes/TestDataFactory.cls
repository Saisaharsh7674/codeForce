/**
 * Reusable test-data builders for Apex test classes. All methods are pure
 * factory helpers; callers decide whether to insert the returned records.
 */
@isTest
public class TestDataFactory {
    /**
     * Builds (and optionally inserts) active Product2 records.
     *
     * @param count Number of products to create.
     * @param doInsert Whether to insert the records before returning.
     * @return The list of Product2 records.
     */
    public static List<Product2> createProducts(Integer count, Boolean doInsert) {
        List<Product2> products = new List<Product2>();
        for (Integer i = 0; i < count; i++) {
            products.add(new Product2(
                Name = 'Test Product ' + i,
                ProductCode = 'PC-' + i,
                Family = 'Hardware',
                IsActive = true
            ));
        }
        if (doInsert) {
            insert products;
        }
        return products;
    }

    /**
     * Returns the Id of the org's standard Pricebook, safe for test context.
     *
     * @return The standard Pricebook Id.
     */
    public static Id getStandardPricebookId() {
        return Test.getStandardPricebookId();
    }

    /**
     * Builds (and optionally inserts) active standard PricebookEntry records
     * for the supplied products.
     *
     * @param products Products to price.
     * @param unitPrice The standard unit price to assign.
     * @param doInsert Whether to insert the records before returning.
     * @return The list of PricebookEntry records.
     */
    public static List<PricebookEntry> createStandardPricebookEntries(
        List<Product2> products,
        Decimal unitPrice,
        Boolean doInsert
    ) {
        Id standardPricebookId = getStandardPricebookId();
        List<PricebookEntry> entries = new List<PricebookEntry>();
        for (Product2 product : products) {
            entries.add(new PricebookEntry(
                Pricebook2Id = standardPricebookId,
                Product2Id = product.Id,
                UnitPrice = unitPrice,
                IsActive = true
            ));
        }
        if (doInsert) {
            insert entries;
        }
        return entries;
    }

    /**
     * Builds (and optionally inserts) Opportunity records.
     *
     * @param count Number of opportunities to create.
     * @param doInsert Whether to insert the records before returning.
     * @return The list of Opportunity records.
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
}
