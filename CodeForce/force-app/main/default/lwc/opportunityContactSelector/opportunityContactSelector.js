import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import { refreshApex } from '@salesforce/apex';
import OCR_OBJECT from '@salesforce/schema/OpportunityContactRole';
import ROLE_FIELD from '@salesforce/schema/OpportunityContactRole.Role';
import getActiveAccountContacts from '@salesforce/apex/OpportunityContactRoleController.getActiveAccountContacts';
import createContactRoles from '@salesforce/apex/OpportunityContactRoleController.createContactRoles';

const PAGE_SIZE = 5;
const CONTACT_COLUMNS = [
    {
        label: 'Contact Name',
        fieldName: 'contactUrl',
        type: 'url',
        typeAttributes: { label: { fieldName: 'Name' }, target: '_self' }
    },
    { label: 'Contact Email', fieldName: 'Email', type: 'email' },
    { label: 'Account Name', fieldName: 'accountName', type: 'text' },
    { label: 'Department', fieldName: 'Department', type: 'text' }
];

export default class OpportunityContactSelector extends LightningElement {
    @api recordId;

    columns = CONTACT_COLUMNS;
    pageSize = PAGE_SIZE;

    @track allContacts = [];
    @track selectedRoleByContactId = {};
    selectedContactsById = new Map();

    currentPage = 1;
    showSelection = false;
    isSaving = false;
    roleOptions = [];

    wiredContactsResult;

    @wire(getObjectInfo, { objectApiName: OCR_OBJECT })
    objectInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$objectInfo.data.defaultRecordTypeId',
        fieldApiName: ROLE_FIELD
    })
    wiredRolePicklist({ data }) {
        if (data) {
            this.roleOptions = data.values.map((item) => ({
                label: item.label,
                value: item.value
            }));
        }
    }

    @wire(getActiveAccountContacts)
    wiredContacts(result) {
        this.wiredContactsResult = result;
        if (result.data) {
            this.allContacts = result.data.map((contact) => ({
                Id: contact.Id,
                Name: contact.Name,
                Email: contact.Email,
                Department: contact.Department,
                accountName: contact.Account ? contact.Account.Name : '',
                contactUrl: '/' + contact.Id
            }));
        } else if (result.error) {
            this.showToast('Error', this.reduceError(result.error), 'error');
        }
    }

    get totalPages() {
        return Math.max(1, Math.ceil(this.allContacts.length / this.pageSize));
    }

    get pagedContacts() {
        const start = (this.currentPage - 1) * this.pageSize;
        return this.allContacts.slice(start, start + this.pageSize);
    }

    get selectedRowIds() {
        return this.pagedContacts
            .filter((row) => this.selectedContactsById.has(row.Id))
            .map((row) => row.Id);
    }

    get isFirstPage() {
        return this.currentPage <= 1;
    }

    get isLastPage() {
        return this.currentPage >= this.totalPages;
    }

    get pageInfo() {
        return `Page ${this.currentPage} of ${this.totalPages}`;
    }

    get hasContacts() {
        return this.allContacts.length > 0;
    }

    get showStep1() {
        return !this.showSelection;
    }

    get selectedContacts() {
        return Array.from(this.selectedContactsById.values());
    }

    get hasSelection() {
        return this.selectedContactsById.size > 0;
    }

    get isNextDisabled() {
        return !this.hasSelection;
    }

    get isSaveDisabled() {
        if (this.isSaving || !this.hasSelection) {
            return true;
        }
        return this.selectedContacts.some(
            (contact) => !this.selectedRoleByContactId[contact.Id]
        );
    }

    handleRowSelection(event) {
        const selectedOnPage = new Set(event.detail.selectedRows.map((row) => row.Id));
        this.pagedContacts.forEach((row) => {
            if (selectedOnPage.has(row.Id)) {
                this.selectedContactsById.set(row.Id, row);
            } else {
                this.selectedContactsById.delete(row.Id);
            }
        });
    }

    handlePrevious() {
        if (!this.isFirstPage) {
            this.currentPage -= 1;
        }
    }

    handleNext() {
        if (!this.isLastPage) {
            this.currentPage += 1;
        }
    }

    handleContinue() {
        if (!this.hasSelection) {
            this.showToast('No contacts selected', 'Select at least one contact to continue.', 'warning');
            return;
        }
        this.showSelection = true;
    }

    handleBack() {
        this.showSelection = false;
    }

    handleRoleChange(event) {
        const contactId = event.target.dataset.id;
        this.selectedRoleByContactId = {
            ...this.selectedRoleByContactId,
            [contactId]: event.detail.value
        };
    }

    async handleSave() {
        this.isSaving = true;
        const assignments = this.selectedContacts.map((contact) => ({
            contactId: contact.Id,
            role: this.selectedRoleByContactId[contact.Id]
        }));

        try {
            const created = await createContactRoles({
                opportunityId: this.recordId,
                assignments
            });
            this.showToast(
                'Success',
                `${created} Opportunity Contact Role record(s) created.`,
                'success'
            );
            this.resetSelection();
            await refreshApex(this.wiredContactsResult);
        } catch (error) {
            this.showToast('Error', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    resetSelection() {
        this.selectedContactsById = new Map();
        this.selectedRoleByContactId = {};
        this.showSelection = false;
        this.currentPage = 1;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        return error?.body?.message || error?.message || 'Unknown error';
    }
}
