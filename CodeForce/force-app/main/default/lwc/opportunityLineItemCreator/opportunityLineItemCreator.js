import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getProducts from '@salesforce/apex/OpportunityLineItemController.getProducts';
import createLineItems from '@salesforce/apex/OpportunityLineItemController.createLineItems';

const PAGE_SIZE = 5;

const PRODUCT_COLUMNS = [
    {
        label: 'Product Name',
        fieldName: 'productUrl',
        type: 'url',
        typeAttributes: { label: { fieldName: 'name' }, target: '_self' }
    },
    { label: 'Product Code', fieldName: 'productCode' },
    { label: 'Product Family', fieldName: 'family' },
    { label: 'Standard Price', fieldName: 'standardPrice', type: 'currency' }
];

const DETAIL_COLUMNS = [
    { label: 'Opportunity Id', fieldName: 'opportunityId' },
    { label: 'Product Id', fieldName: 'productId' },
    { label: 'Quantity', fieldName: 'quantity', type: 'number', editable: true },
    { label: 'Sales Price', fieldName: 'salesPrice', type: 'currency', editable: true }
];

export default class OpportunityLineItemCreator extends LightningElement {
    @api recordId;

    productColumns = PRODUCT_COLUMNS;
    detailColumns = DETAIL_COLUMNS;

    @track allProducts = [];
    @track detailRows = [];
    selectedProductIds = [];
    draftValues = [];

    isLoading = false;
    showDetailStep = false;
    errorMessage;

    pageNumber = 1;
    pageSize = PAGE_SIZE;

    connectedCallback() {
        this.loadProducts();
    }

    async loadProducts() {
        this.isLoading = true;
        try {
            const results = await getProducts();
            this.allProducts = results.map((product) => ({
                ...product,
                productUrl: `/${product.productId}`
            }));
            this.errorMessage = undefined;
        } catch (error) {
            this.errorMessage = this.getErrorMessage(error);
            this.showToast('Error', this.errorMessage, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    get totalPages() {
        return Math.max(1, Math.ceil(this.allProducts.length / this.pageSize));
    }

    get pagedProducts() {
        const start = (this.pageNumber - 1) * this.pageSize;
        return this.allProducts.slice(start, start + this.pageSize);
    }

    get isFirstPage() {
        return this.pageNumber <= 1;
    }

    get isLastPage() {
        return this.pageNumber >= this.totalPages;
    }

    get pageInfo() {
        return `Page ${this.pageNumber} of ${this.totalPages}`;
    }

    get hasSelection() {
        return this.selectedProductIds.length > 0;
    }

    get hasNoSelection() {
        return this.selectedProductIds.length === 0;
    }

    get hasProducts() {
        return this.allProducts.length > 0;
    }

    handleRowSelection(event) {
        const pageSelectedIds = event.detail.selectedRows.map((row) => row.productId);
        const pageProductIds = this.pagedProducts.map((product) => product.productId);
        const retained = this.selectedProductIds.filter(
            (id) => !pageProductIds.includes(id)
        );
        this.selectedProductIds = [...retained, ...pageSelectedIds];
    }

    get selectedRowsForPage() {
        return this.pagedProducts
            .filter((product) => this.selectedProductIds.includes(product.productId))
            .map((product) => product.productId);
    }

    handlePrevious() {
        if (!this.isFirstPage) {
            this.pageNumber -= 1;
        }
    }

    handleNext() {
        if (!this.isLastPage) {
            this.pageNumber += 1;
        }
    }

    handleProceed() {
        if (!this.hasSelection) {
            this.showToast('No selection', 'Select at least one product to continue.', 'warning');
            return;
        }
        const selectedProducts = this.allProducts.filter((product) =>
            this.selectedProductIds.includes(product.productId)
        );
        this.detailRows = selectedProducts.map((product) => ({
            id: product.productId,
            opportunityId: this.recordId,
            productId: product.productId,
            quantity: 1,
            salesPrice: product.standardPrice
        }));
        this.draftValues = [];
        this.showDetailStep = true;
    }

    handleBack() {
        this.showDetailStep = false;
        this.draftValues = [];
    }

    handleCellChange(event) {
        this.draftValues = event.detail.draftValues;
    }

    applyDraftValues() {
        if (!this.draftValues.length) {
            return;
        }
        const draftsById = {};
        this.draftValues.forEach((draft) => {
            draftsById[draft.id] = draft;
        });
        this.detailRows = this.detailRows.map((row) => {
            const draft = draftsById[row.id];
            if (!draft) {
                return row;
            }
            return {
                ...row,
                quantity: draft.quantity !== undefined ? draft.quantity : row.quantity,
                salesPrice: draft.salesPrice !== undefined ? draft.salesPrice : row.salesPrice
            };
        });
        this.draftValues = [];
    }

    async handleSave() {
        this.applyDraftValues();
        const items = this.detailRows.map((row) => ({
            productId: row.productId,
            quantity: row.quantity,
            salesPrice: row.salesPrice
        }));

        this.isLoading = true;
        try {
            const created = await createLineItems({
                opportunityId: this.recordId,
                items
            });
            this.showToast(
                'Success',
                `${created} Opportunity Line Item${created === 1 ? '' : 's'} created.`,
                'success'
            );
            this.resetToProductStep();
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    resetToProductStep() {
        this.showDetailStep = false;
        this.selectedProductIds = [];
        this.detailRows = [];
        this.draftValues = [];
        this.pageNumber = 1;
        this.loadProducts();
    }

    getErrorMessage(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        if (error && error.message) {
            return error.message;
        }
        return 'An unexpected error occurred.';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
