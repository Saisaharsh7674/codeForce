/**
 * Tests for OpportunityContactRoleController: active-Account contact retrieval
 * and Opportunity Contact Role creation, including negative paths.
 */
@isTest
private class OpportunityContactRoleControllerTest {
    private static final String ROLE = 'Decision Maker';

    @TestSetup
    static void setupTestData() {
        Account activeAccount = TestDataFactory.createAccounts(1, true, true)[0];
        Account inactiveAccount = TestDataFactory.createAccounts(1, false, true)[0];
        TestDataFactory.createContacts(3, activeAccount.Id, true);
        TestDataFactory.createContacts(2, inactiveAccount.Id, true);
        TestDataFactory.createOpportunities(1, true);
    }

    @isTest
    static void shouldReturnOnlyActiveAccountContacts_WhenQueried() {
        // When
        Test.startTest();
        List<Contact> results = OpportunityContactRoleController.getActiveAccountContacts();
        Test.stopTest();

        // Then
        Assert.areEqual(3, results.size(), 'Only contacts on active accounts should be returned');
        for (Contact c : results) {
            Assert.areEqual('Sales', c.Department, 'Department should be populated');
            Assert.isNotNull(c.Account.Name, 'Account name should be populated');
        }
    }

    private static List<OpportunityContactRoleController.ContactRoleAssignment> buildAssignments(List<Contact> contacts) {
        List<OpportunityContactRoleController.ContactRoleAssignment> assignments =
            new List<OpportunityContactRoleController.ContactRoleAssignment>();
        for (Contact c : contacts) {
            OpportunityContactRoleController.ContactRoleAssignment assignment =
                new OpportunityContactRoleController.ContactRoleAssignment();
            assignment.contactId = c.Id;
            assignment.role = ROLE;
            assignments.add(assignment);
        }
        return assignments;
    }

    @isTest
    static void shouldCreateContactRoles_WhenValidInput() {
        // Given
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        List<Contact> contacts = [SELECT Id FROM Contact WHERE Account.Active__c = true];
        List<OpportunityContactRoleController.ContactRoleAssignment> assignments = buildAssignments(contacts);

        // When
        Test.startTest();
        Integer created = OpportunityContactRoleController.createContactRoles(opp.Id, assignments);
        Test.stopTest();

        // Then
        Assert.areEqual(3, created, 'Should report three created contact roles');
        List<OpportunityContactRole> roles = [
            SELECT Id, Role, ContactId FROM OpportunityContactRole WHERE OpportunityId = :opp.Id
        ];
        Assert.areEqual(3, roles.size(), 'Three contact roles should exist for the opportunity');
        Assert.areEqual(ROLE, roles[0].Role, 'Role should match the requested value');
    }

    @isTest
    static void shouldThrow_WhenOpportunityIdNull() {
        // Given
        List<Contact> contacts = [SELECT Id FROM Contact LIMIT 1];
        List<OpportunityContactRoleController.ContactRoleAssignment> assignments = buildAssignments(contacts);

        // When/Then
        Test.startTest();
        try {
            OpportunityContactRoleController.createContactRoles(null, assignments);
            Assert.fail('Expected AuraHandledException for null opportunity');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage(), 'Exception should carry a message');
        }
        Test.stopTest();
    }

    @isTest
    static void shouldThrow_WhenAssignmentsNull() {
        // Given
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        // When/Then
        Test.startTest();
        try {
            OpportunityContactRoleController.createContactRoles(opp.Id, null);
            Assert.fail('Expected AuraHandledException for null assignment list');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage(), 'Exception should carry a message');
        }
        Test.stopTest();
    }

    @isTest
    static void shouldThrow_WhenAssignmentsEmpty() {
        // Given
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        // When/Then
        Test.startTest();
        try {
            OpportunityContactRoleController.createContactRoles(
                opp.Id, new List<OpportunityContactRoleController.ContactRoleAssignment>());
            Assert.fail('Expected AuraHandledException for empty assignment list');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage(), 'Exception should carry a message');
        }
        Test.stopTest();
    }
}
