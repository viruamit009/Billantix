import { LightningElement, api, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getQuoteGeneralInfo  from '@salesforce/apex/QuoteCreatorController.getQuoteGeneralInfo';
import saveQuoteGeneralInfo from '@salesforce/apex/QuoteCreatorController.saveQuoteGeneralInfo';

const STATUS_OPTIONS = [
    { label: 'Draft',        value: 'Draft'        },
    { label: 'Needs Review', value: 'Needs Review' },
    { label: 'In Review',    value: 'In Review'    },
    { label: 'Approved',     value: 'Approved'     },
    { label: 'Rejected',     value: 'Rejected'     }
];

export default class QuoteGeneralInfo extends LightningElement {

    @api
    get recordId() { return this._recordId; }
    set recordId(value) {
        this._recordId = value;
        if (value && !this._loaded) this._triggerLoad();
    }
    _recordId;
    _loaded = false;

    @wire(CurrentPageReference)
    wiredPageRef(ref) {
        const id = ref?.state?.c__recordId;
        if (id) {
            this._recordId = id;
            if (!this._loaded) this._triggerLoad();
        }
    }

    quote            = null;
    statusOptions    = STATUS_OPTIONS;

    @track quoteName           = '';
    @track description         = '';
    @track startDate           = '';
    @track expirationDate      = '';
    @track status              = 'Draft';
    @track selectedPricebook2Id = '';
    @track opportunityId        = '';
    @track billingStreet        = '';
    @track billingCity          = '';
    @track billingState         = '';
    @track billingPostalCode    = '';
    @track billingCountry       = '';
    @track contactSearch        = '';
    @track oppExpanded          = false;
    @track saving               = false;
    @track isLoading            = true;
    @track isReady              = false;
    @track errorMsg             = null;

    _triggerLoad() {
        // Defer to next microtask so all wires have settled
        Promise.resolve().then(() => this.loadData());
    }

    async loadData() {
        if (!this._recordId) return;
        this._loaded    = true;
        this.isLoading  = true;
        this.isReady    = false;
        this.errorMsg   = null;
        try {
            const q = await getQuoteGeneralInfo({ quoteId: this._recordId });
            this.quote               = q;
            this.quoteName           = q.Name              || '';
            this.description         = q.Description       || '';
            this.startDate           = q.Start_Date__c     || '';
            this.expirationDate      = q.ExpirationDate    || '';
            this.status              = q.Status            || 'Draft';
            this.selectedPricebook2Id = q.Pricebook2Id     || '';
            this.opportunityId       = q.OpportunityId     || '';
            this.billingStreet       = q.BillingStreet     || '';
            this.billingCity         = q.BillingCity       || '';
            this.billingState        = q.BillingState      || '';
            this.billingPostalCode   = q.BillingPostalCode || '';
            this.billingCountry      = q.BillingCountry    || '';
            this.contactSearch       = q.Contact?.Name     || '';
            this.isReady             = true;
        } catch (err) {
            this.errorMsg = err?.body?.message || err?.message || 'Failed to load quote.';
            this.isReady  = true;
        } finally {
            this.isLoading = false;
        }
    }

    // ── Computed ─────────────────────────────────────────────────────────────

    get quoteTitle()     { return this.quote?.Name        || 'General Information'; }
    get pageSubtitle()   { return this.quote?.Opportunity?.Name || ''; }
    get accountName()    { return this.quote?.Account?.Name || ''; }
    get hasOpportunity() { return !!this.quote?.OpportunityId; }
    get oppToggleIcon()  { return this.oppExpanded ? 'utility:chevrondown' : 'utility:chevronright'; }

    // Opportunity record picker filter
    get opportunityFilter() {
        return { criteria: [{ fieldPath: 'IsDeleted', operator: 'eq', value: false }] };
    }

    // ── Handlers ─────────────────────────────────────────────────────────────

    handleNameChange(e)           { this.quoteName         = e.target.value; }
    handleDescriptionChange(e)    { this.description       = e.target.value; }
    handleStartDateChange(e)      { this.startDate         = e.target.value; }
    handleExpirationDateChange(e) { this.expirationDate    = e.target.value; }
    handleStatusChange(e)         { this.status            = e.detail.value; }
    handlePricebookChange(e)      { this.selectedPricebook2Id = e.detail.recordId || ''; }
    handleContactSearchChange(e)  { this.contactSearch     = e.target.value; }
    handleContactSearch()         { /* TODO: contact lookup */ }
    handleToggleOpp()             { this.oppExpanded       = !this.oppExpanded; }
    handleGoToGeneral()           { /* already here */ }
    handleGoToLines()             { window.location.href = `/lightning/cmp/Billantix__quoteLineEditor?c__recordId=${this._recordId}`; }

    handleOpportunityChange(e) {
        this.opportunityId = e.detail.recordId || '';
        // Refresh quote data to get updated Account info after opportunity change
        if (this.opportunityId) this.quote = { ...this.quote, OpportunityId: this.opportunityId };
    }

    handleBillingChange(e) {
        const field = e.currentTarget.dataset.field;
        this[field] = e.target.value;
    }

    async handleQuickSave() {
        const ok = await this._save();
        if (ok) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Saved', message: 'Quote updated.', variant: 'success' }));
            await this.loadData();
        }
    }

    async handleSaveAndNext() {
        const ok = await this._save();
        if (ok) {
            window.location.href = `/lightning/cmp/Billantix__quoteLineEditor?c__recordId=${this._recordId}`;
        }
    }

    async _save() {
        this.errorMsg = null;
        if (!this.quoteName) {
            this.errorMsg = 'Quote Name is required.';
            return false;
        }
        this.saving = true;
        try {
            await saveQuoteGeneralInfo({
                quoteId: this._recordId,
                quoteJson: JSON.stringify({
                    Name:              this.quoteName,
                    Description:       this.description          || null,
                    ExpirationDate:    this.expirationDate       || null,
                    Start_Date__c:     this.startDate            || null,
                    Status:            this.status,
                    Pricebook2Id:      this.selectedPricebook2Id || null,
                    OpportunityId:     this.opportunityId        || null,
                    BillingStreet:     this.billingStreet        || null,
                    BillingCity:       this.billingCity          || null,
                    BillingState:      this.billingState         || null,
                    BillingPostalCode: this.billingPostalCode    || null,
                    BillingCountry:    this.billingCountry       || null
                })
            });
            return true;
        } catch (err) {
            this.errorMsg = err?.body?.message || 'Save failed.';
            return false;
        } finally {
            this.saving = false;
        }
    }
}
