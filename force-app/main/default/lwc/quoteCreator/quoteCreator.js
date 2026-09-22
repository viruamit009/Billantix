import { LightningElement, api, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getOpportunity from '@salesforce/apex/QuoteCreatorController.getOpportunity';
import createQuote    from '@salesforce/apex/QuoteCreatorController.createQuote';

const STATUS_OPTIONS = [
    { label: 'Draft',        value: 'Draft'        },
    { label: 'Needs Review', value: 'Needs Review' },
    { label: 'In Review',    value: 'In Review'    },
    { label: 'Approved',     value: 'Approved'     },
    { label: 'Rejected',     value: 'Rejected'     }
];

export default class QuoteCreator extends LightningElement {

    @api
    get recordId() { return this._recordId; }
    set recordId(value) { this._recordId = value; if (value) this._opportunityId = value; }
    _recordId;

    @track _opportunityId;

    @wire(CurrentPageReference)
    wiredPageRef(ref) {
        const id = ref?.state?.c__recordId;
        if (id && !this._opportunityId) this._opportunityId = id;
    }

    opportunity    = null;
    statusOptions  = STATUS_OPTIONS;

    @track quoteName         = '';
    @track description       = '';
    @track startDate         = '';
    @track expirationDate    = '';
    @track status            = 'Draft';
    @track billingStreet     = '';
    @track billingCity       = '';
    @track billingState      = '';
    @track billingPostalCode = '';
    @track billingCountry    = '';
    @track contactSearch     = '';
    @track oppExpanded       = false;
    @track saving            = false;
    @track isLoading         = true;
    @track isReady           = false;
    @track errorMsg          = null;

    @wire(getOpportunity, { opportunityId: '$_opportunityId' })
    wiredOpp({ data, error }) {
        if (data) {
            this.opportunity       = data;
            this.quoteName         = `Quote for ${data.Name}`;
            this.billingStreet     = data.Account?.BillingStreet     || '';
            this.billingCity       = data.Account?.BillingCity       || '';
            this.billingState      = data.Account?.BillingState      || '';
            this.billingPostalCode = data.Account?.BillingPostalCode || '';
            this.billingCountry    = data.Account?.BillingCountry    || '';
            if (data.CloseDate) this.expirationDate = data.CloseDate;
            this.isLoading = false;
            this.isReady   = true;
        }
        if (error) {
            this.errorMsg  = error.body?.message || 'Failed to load opportunity.';
            this.isLoading = false;
            this.isReady   = true;
        }
    }

    // ── Computed ─────────────────────────────────────────────────────────────

    get accountName()    { return this.opportunity?.Account?.Name          || ''; }
    get accountNumber()  { return this.opportunity?.Account?.AccountNumber  || ''; }
    get pageSubtitle()   { return this.opportunity?.Name || ''; }
    get oppToggleIcon()  { return this.oppExpanded ? 'utility:chevrondown' : 'utility:chevronright'; }

    // ── Handlers ─────────────────────────────────────────────────────────────

    handleNameChange(e)            { this.quoteName         = e.target.value; }
    handleDescriptionChange(e)     { this.description       = e.target.value; }
    handleStartDateChange(e)       { this.startDate         = e.target.value; }
    handleExpirationDateChange(e)  { this.expirationDate    = e.target.value; }
    handleStatusChange(e)          { this.status            = e.detail.value; }
    handleContactSearchChange(e)   { this.contactSearch     = e.target.value; }
    handleContactSearch()          { /* TODO: contact lookup */ }
    handleToggleOpp()              { this.oppExpanded       = !this.oppExpanded; }

    handleBillingChange(e) {
        const field = e.currentTarget.dataset.field;
        this[field] = e.target.value;
    }

    async handleQuickSave() {
        const quoteId = await this._save();
        if (quoteId) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Saved', message: 'Quote created.', variant: 'success' }));
            window.location.href = `/lightning/cmp/Billantix__quoteGeneralInfo?c__recordId=${quoteId}`;
        }
    }

    async handleSaveAndNext() {
        const quoteId = await this._save();
        if (quoteId) {
            window.location.href = `/lightning/cmp/Billantix__quoteLineEditor?c__recordId=${quoteId}`;
        }
    }

    async _save() {
        this.errorMsg = null;
        if (!this.quoteName) {
            this.errorMsg = 'Quote Name is required.';
            return null;
        }
        this.saving = true;
        try {
            return await createQuote({
                opportunityId    : this._opportunityId,
                quoteName        : this.quoteName,
                description      : this.description        || null,
                startDate        : this.startDate          || null,
                expirationDate   : this.expirationDate     || null,
                pricebook2Id     : null,
                billingStreet    : this.billingStreet      || null,
                billingCity      : this.billingCity        || null,
                billingState     : this.billingState       || null,
                billingPostalCode: this.billingPostalCode  || null,
                billingCountry   : this.billingCountry     || null
            });
        } catch (err) {
            this.errorMsg = err.body?.message || 'Failed to create quote.';
            return null;
        } finally {
            this.saving = false;
        }
    }
}
