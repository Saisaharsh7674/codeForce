/**
 * Controller for the opportunityLineItemCreator LWC. Exposes active Products
 * with their standard price for a data table and creates OpportunityLineItem
 * records against a given Opportunity using the matching PricebookEntry.
 */
public with sharing class OpportunityLineItemController {
    @TestVisible
    private static final String NO_PRODUCTS_ERROR = 'No active products with a standard price were found.';
    @TestVisible
    private static final String NO_OPPORTUNITY_ERROR = 'A valid Opportunity is required to create line items.';
    @TestVisible
    private static final String NO_ITEMS_ERROR = 'Select at least one product to create line items.';
    @TestVisible
    private static final String MISSING_PRICEBOOK_ENTRY_ERROR = 'No standard PricebookEntry was found for one or more selected products.';

    /**
     * Data container returned to the LWC for each selectable product row.
     */
    public class ProductOption {
        @AuraEnabled public Id productId;
        @AuraEnabled public String name;
        @AuraEnabled public String productCode;
        @AuraEnabled public String family;
        @AuraEnabled public Decimal standardPrice;
        @AuraEnabled public Id pricebookEntryId;
    }

    /**
     * Request payload sent from the LWC describing a single line item to create.
     */
    public class LineItemRequest {
        @AuraEnabled public Id productId;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal salesPrice;
    }

    /**
     * Returns active products that have a standard PricebookEntry, along with
     * the standard price for display in the data table.
     *
     * @return List of ProductOption records ordered by product name.
     * @example
     * List<OpportunityLineItemController.ProductOption> products =
     *     OpportunityLineItemController.getProducts();
     */
    @AuraEnabled(cacheable=true)
    public static List<ProductOption> getProducts() {
        try {
            List<PricebookEntry> entries = [
                SELECT Id, UnitPrice, Product2Id, Product2.Name,
                       Product2.ProductCode, Product2.Family
                FROM PricebookEntry
                WHERE IsActive = true
                  AND Pricebook2.IsStandard = true
                  AND Product2.IsActive = true
                WITH USER_MODE
                ORDER BY Product2.Name
                LIMIT 10000
            ];

            List<ProductOption> options = new List<ProductOption>();
            for (PricebookEntry entry : entries) {
                ProductOption option = new ProductOption();
                option.productId = entry.Product2Id;
                option.name = entry.Product2.Name;
                option.productCode = entry.Product2.ProductCode;
                option.family = entry.Product2.Family;
                option.standardPrice = entry.UnitPrice;
                option.pricebookEntryId = entry.Id;
                options.add(option);
            }
            return options;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Creates OpportunityLineItem records for the supplied Opportunity using the
     * standard PricebookEntry that matches each selected product.
     *
     * @param opportunityId The Opportunity the line items belong to.
     * @param items The selected products with their quantity and sales price.
     * @return The number of OpportunityLineItem records created.
     * @example
     * Integer created = OpportunityLineItemController.createLineItems(oppId, requests);
     */
    @AuraEnabled
    public static Integer createLineItems(Id opportunityId, List<LineItemRequest> items) {
        if (opportunityId == null) {
            throw new AuraHandledException(NO_OPPORTUNITY_ERROR);
        }
        if (items == null || items.isEmpty()) {
            throw new AuraHandledException(NO_ITEMS_ERROR);
        }

        try {
            Set<Id> productIds = new Set<Id>();
            for (LineItemRequest item : items) {
                if (item.productId != null) {
                    productIds.add(item.productId);
                }
            }

            ensureOpportunityPricebook(opportunityId);

            Map<Id, PricebookEntry> entriesByProductId = new Map<Id, PricebookEntry>();
            for (PricebookEntry entry : [
                SELECT Id, Product2Id
                FROM PricebookEntry
                WHERE Product2Id IN :productIds
                  AND IsActive = true
                  AND Pricebook2.IsStandard = true
                WITH USER_MODE
            ]) {
                entriesByProductId.put(entry.Product2Id, entry);
            }

            List<OpportunityLineItem> lineItems = new List<OpportunityLineItem>();
            for (LineItemRequest item : items) {
                PricebookEntry entry = entriesByProductId.get(item.productId);
                if (entry == null) {
                    throw new AuraHandledException(MISSING_PRICEBOOK_ENTRY_ERROR);
                }
                OpportunityLineItem lineItem = new OpportunityLineItem();
                lineItem.OpportunityId = opportunityId;
                lineItem.PricebookEntryId = entry.Id;
                lineItem.Quantity = item.quantity;
                lineItem.UnitPrice = item.salesPrice;
                lineItems.add(lineItem);
            }

            insert as user lineItems;
            return lineItems.size();
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Ensures the Opportunity references the standard Pricebook so that the
     * standard PricebookEntry can be used for line item creation.
     *
     * @param opportunityId The Opportunity to check and update if needed.
     */
    private static void ensureOpportunityPricebook(Id opportunityId) {
        List<Opportunity> opportunities = [
            SELECT Id, Pricebook2Id
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH USER_MODE
            LIMIT 1
        ];
        if (opportunities.isEmpty()) {
            throw new AuraHandledException(NO_OPPORTUNITY_ERROR);
        }
        if (opportunities[0].Pricebook2Id != null) {
            return;
        }

        List<Pricebook2> standardPricebooks = [
            SELECT Id
            FROM Pricebook2
            WHERE IsStandard = true
            WITH USER_MODE
            LIMIT 1
        ];
        if (standardPricebooks.isEmpty()) {
            throw new AuraHandledException(MISSING_PRICEBOOK_ENTRY_ERROR);
        }
        opportunities[0].Pricebook2Id = standardPricebooks[0].Id;
        update as user opportunities;
    }
}
