/**
 * Tests for OpportunityLineItemController covering product retrieval and
 * OpportunityLineItem creation, including negative and error paths.
 */
@isTest
private class OpportunityLineItemControllerTest {
    private static final Decimal STANDARD_PRICE = 100.00;

    @TestSetup
    static void setupTestData() {
        List<Product2> products = TestDataFactory.createProducts(3, true);
        TestDataFactory.createStandardPricebookEntries(products, STANDARD_PRICE, true);
        TestDataFactory.createOpportunities(1, true);
    }

    @isTest
    static void shouldReturnProducts_WhenActiveEntriesExist() {
        // When
        Test.startTest();
        List<OpportunityLineItemController.ProductOption> options =
            OpportunityLineItemController.getProducts();
        Test.stopTest();

        // Then
        Assert.areEqual(3, options.size(), 'All priced products should be returned');
        OpportunityLineItemController.ProductOption first = options[0];
        Assert.areEqual(STANDARD_PRICE, first.standardPrice, 'Standard price should match the PricebookEntry');
        Assert.isNotNull(first.pricebookEntryId, 'PricebookEntry Id should be populated');
        Assert.isNotNull(first.productId, 'Product Id should be populated');
    }

    @isTest
    static void shouldCreateLineItems_WhenValidRequests() {
        // Given
        Opportunity opportunity = [SELECT Id FROM Opportunity LIMIT 1];
        List<Product2> products = [SELECT Id FROM Product2 ORDER BY Name];
        List<OpportunityLineItemController.LineItemRequest> requests =
            new List<OpportunityLineItemController.LineItemRequest>();
        for (Product2 product : products) {
            OpportunityLineItemController.LineItemRequest request =
                new OpportunityLineItemController.LineItemRequest();
            request.productId = product.Id;
            request.quantity = 2;
            request.salesPrice = 150.00;
            requests.add(request);
        }

        // When
        Test.startTest();
        Integer created = OpportunityLineItemController.createLineItems(opportunity.Id, requests);
        Test.stopTest();

        // Then
        Assert.areEqual(3, created, 'All requested line items should be created');
        List<OpportunityLineItem> lineItems = [
            SELECT Id, Quantity, UnitPrice FROM OpportunityLineItem WHERE OpportunityId = :opportunity.Id
        ];
        Assert.areEqual(3, lineItems.size(), 'Three OpportunityLineItem records should exist');
        Assert.areEqual(150.00, lineItems[0].UnitPrice, 'Sales price should persist as UnitPrice');
        Assert.areEqual(2, lineItems[0].Quantity, 'Quantity should persist');
    }

    @isTest
    static void shouldAssignStandardPricebook_WhenOpportunityHasNone() {
        // Given
        Opportunity opportunity = [SELECT Id, Pricebook2Id FROM Opportunity LIMIT 1];
        Assert.isNull(opportunity.Pricebook2Id, 'Opportunity should start without a pricebook');
        Product2 product = [SELECT Id FROM Product2 LIMIT 1];
        OpportunityLineItemController.LineItemRequest request =
            new OpportunityLineItemController.LineItemRequest();
        request.productId = product.Id;
        request.quantity = 1;
        request.salesPrice = 99.00;

        // When
        Test.startTest();
        Integer created = OpportunityLineItemController.createLineItems(
            opportunity.Id,
            new List<OpportunityLineItemController.LineItemRequest>{ request }
        );
        Test.stopTest();

        // Then
        Assert.areEqual(1, created, 'One line item should be created');
        Opportunity refreshed = [SELECT Id, Pricebook2Id FROM Opportunity WHERE Id = :opportunity.Id];
        Assert.isNotNull(refreshed.Pricebook2Id, 'Opportunity should now reference the standard pricebook');
    }

    @isTest
    static void shouldThrow_WhenOpportunityIdIsNull() {
        // Given
        OpportunityLineItemController.LineItemRequest request =
            new OpportunityLineItemController.LineItemRequest();
        request.productId = [SELECT Id FROM Product2 LIMIT 1].Id;
        request.quantity = 1;
        request.salesPrice = 10;

        // When/Then
        Test.startTest();
        try {
            OpportunityLineItemController.createLineItems(
                null,
                new List<OpportunityLineItemController.LineItemRequest>{ request }
            );
            Assert.fail('Expected an AuraHandledException for a null Opportunity');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage(), 'Exception should carry a message');
        }
        Test.stopTest();
    }

    @isTest
    static void shouldThrow_WhenNoItemsProvided() {
        // Given
        Opportunity opportunity = [SELECT Id FROM Opportunity LIMIT 1];

        // When/Then
        Test.startTest();
        try {
            OpportunityLineItemController.createLineItems(
                opportunity.Id,
                new List<OpportunityLineItemController.LineItemRequest>()
            );
            Assert.fail('Expected an AuraHandledException for an empty item list');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage(), 'Exception should carry a message');
        }
        Test.stopTest();
    }
}
