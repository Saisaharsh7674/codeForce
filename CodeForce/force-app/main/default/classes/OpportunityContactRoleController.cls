/**
 * Controller for the opportunityContactSelector LWC. Provides read access to
 * Contacts belonging to active Accounts and creates Opportunity Contact Role
 * records for a set of selected Contacts against a given Opportunity.
 */
public with sharing class OpportunityContactRoleController {
    @TestVisible
    private static final String NO_CONTACTS_ERROR = 'Select at least one contact before saving.';
    @TestVisible
    private static final String NO_OPPORTUNITY_ERROR = 'A valid Opportunity is required to create contact roles.';

    /**
     * Data transfer object carrying a Contact and its chosen Opportunity
     * Contact Role for creation.
     */
    public class ContactRoleAssignment {
        @AuraEnabled
        public Id contactId { get; set; }
        @AuraEnabled
        public String role { get; set; }
    }

    /**
     * Returns Contacts whose Account is flagged active (Account.Active__c = true).
     * The LWC paginates the returned list client-side (5 records per page).
     *
     * @return List of active-Account Contacts with Name, Email, Account Name and Department.
     * @throws AuraHandledException when the query cannot be executed.
     * @example
     * List<Contact> contacts = OpportunityContactRoleController.getActiveAccountContacts();
     */
    @AuraEnabled(cacheable=true)
    public static List<Contact> getActiveAccountContacts() {
        try {
            return [
                SELECT Id, Name, Email, Department, Account.Name
                FROM Contact
                WHERE Account.Active__c = true
                WITH USER_MODE
                ORDER BY Name ASC
                LIMIT 10000
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Unable to load contacts: ' + e.getMessage());
        }
    }

    /**
     * Creates Opportunity Contact Role records for the supplied Contact/Role
     * assignments against the given Opportunity.
     *
     * @param opportunityId The Opportunity the contact roles belong to.
     * @param assignments The Contact-to-Role assignments to create.
     * @return The number of Opportunity Contact Role records created.
     * @throws AuraHandledException when inputs are invalid or the insert fails.
     * @example
     * Integer created = OpportunityContactRoleController.createContactRoles(oppId, assignments);
     */
    @AuraEnabled
    public static Integer createContactRoles(Id opportunityId, List<ContactRoleAssignment> assignments) {
        if (opportunityId == null) {
            throw new AuraHandledException(NO_OPPORTUNITY_ERROR);
        }
        if (assignments == null || assignments.isEmpty()) {
            throw new AuraHandledException(NO_CONTACTS_ERROR);
        }

        List<OpportunityContactRole> rolesToInsert = new List<OpportunityContactRole>();
        for (ContactRoleAssignment assignment : assignments) {
            rolesToInsert.add(new OpportunityContactRole(
                OpportunityId = opportunityId,
                ContactId = assignment.contactId,
                Role = assignment.role
            ));
        }

        try {
            insert as user rolesToInsert;
        } catch (DmlException e) {
            throw new AuraHandledException('Unable to create contact roles: ' + e.getMessage());
        }
        return rolesToInsert.size();
    }
}
