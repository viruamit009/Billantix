import { LightningElement, api, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getQuoteForOrder     from '@salesforce/apex/OrderController.getQuoteForOrder';
import getOrderGeneralInfo  from '@salesforce/apex/OrderController.getOrderGeneralInfo';
import createOrder          from '@salesforce/apex/OrderController.createOrder';
import saveOrderGeneralInfo from '@salesforce/apex/OrderController.saveOrderGeneralInfo';

const STATUS_OPTIONS = [
    { label: 'Draft',     value: 'Draft'     },
    { label: 'Activated', value: 'Activated' }
];

export default class OrderGeneralInfo extends LightningElement {

    // c__quoteId  → create mode (order not yet created)
    // c__recordId → edit mode  (order already exists)
    _quoteId  = null;
    _orderId  = null;
    _loaded   = false;

    @wire(CurrentPageReference)
    wiredPageRef(ref) {
        const quoteId = ref?.state?.c__quoteId;
        const orderId = ref?.state?.c__recordId;
        if ((quoteId || orderId) && !this._loaded) {
            this._quoteId = quoteId || null;
            this._orderId = orderId || null;
            Promise.resolve().then(() => this.loadData());
        }
    }

    order          = null;
    statusOptions  = STATUS_OPTIONS;

    @track accountName          = '';
    @track orderNumber          = '';
    @track opportunityId        = '';
    @track sourceQuoteId        = '';
    @track selectedPricebook2Id = '';
    @track description          = '';
    @track effectiveDate        = '';
    @track endDate              = '';
    @track status               = 'Draft';
    @track billingStreet     = '';
    @track billingCity       = '';
    @track billingState      = '';
    @track billingPostalCode = '';
    @track billingCountry    = '';
    @track saving            = false;
    @track isLoading         = true;
    @track isReady           = false;
    @track errorMsg          = null;

    async loadData() {
        this._loaded   = true;
        this.isLoading = true;
        this.isReady   = false;
        this.errorMsg  = null;
        try {
            if (this._orderId) {
                // Edit mode — load existing order
                const o = await getOrderGeneralInfo({ orderId: this._orderId });
                this.order                = o;
                this.accountName          = o.Account?.Name          || '';
                this.orderNumber          = o.OrderNumber            || '';
                this.opportunityId        = o.OpportunityId          || '';
                this.selectedPricebook2Id = o.Pricebook2Id           || '';
                this.description          = o.Description            || '';
                this.effectiveDate        = o.EffectiveDate          || '';
                this.endDate              = o.EndDate                || '';
                this.status               = o.Status                 || 'Draft';
                this.billingStreet        = o.BillingStreet          || '';
                this.billingCity          = o.BillingCity            || '';
                this.billingState         = o.BillingState           || '';
                this.billingPostalCode    = o.BillingPostalCode      || '';
                this.billingCountry       = o.BillingCountry         || '';
            } else if (this._quoteId) {
                // Create mode — pre-fill from quote
                const q = await getQuoteForOrder({ quoteId: this._quoteId });
                this.accountName          = q.Account?.Name          || '';
                this.opportunityId        = q.OpportunityId          || '';
                this.sourceQuoteId        = this._quoteId            || '';
                this.selectedPricebook2Id = q.Pricebook2Id           || '';
                this.effectiveDate        = q.Start_Date__c          || '';
                this.endDate              = q.ExpirationDate         || '';
                this.billingStreet        = q.BillingStreet          || '';
                this.billingCity          = q.BillingCity            || '';
                this.billingState         = q.BillingState           || '';
                this.billingPostalCode    = q.BillingPostalCode      || '';
                this.billingCountry       = q.BillingCountry         || '';
            }
            this.isReady = true;
        } catch (err) {
            this.errorMsg = err?.body?.message || 'Failed to load data.';
            this.isReady  = true;
        } finally {
            this.isLoading = false;
        }
    }

    // ── Computed ─────────────────────────────────────────────────────────────

    get pageTitle()    { return this._orderId ? (this.order?.OrderNumber || 'Order') : 'Create Order'; }
    get pageSubtitle() { return this.accountName; }
    get statusClass()  { return (this.status || 'draft').toLowerCase().replace(/\s+/g, '-'); }
    get isEditMode()   { return !!this._orderId; }
    get isSpinning()   { return this.isLoading || this.saving; }
    get spinnerLabel() { return this.saving ? 'Saving...' : 'Loading...'; }

    // ── Handlers ─────────────────────────────────────────────────────────────

    handleDescriptionChange(e)   { this.description          = e.target.value; }
    handleEffectiveDateChange(e) { this.effectiveDate        = e.target.value; }
    handleEndDateChange(e)       { this.endDate              = e.target.value; }
    handleStatusChange(e)        { this.status               = e.detail.value; }
    handlePricebookChange(e)     { this.selectedPricebook2Id = e.detail.recordId || ''; }
    handleOpportunityChange(e)   { this.opportunityId        = e.detail.recordId || ''; }
    handleQuoteChange(e)         { this.sourceQuoteId        = e.detail.recordId || ''; }

    async handleGoToLines() {
        if (this._orderId) {
            window.location.href = `/lightning/cmp/Billantix__orderLineEditor?c__recordId=${this._orderId}`;
        } else {
            await this.handleSaveAndNext();
        }
    }

    handleBillingChange(e) {
        const field = e.currentTarget.dataset.field;
        this[field] = e.target.value;
    }

    async handleQuickSave() {
        const id = await this._save();
        if (id) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Saved', message: 'Order saved.', variant: 'success' }));
            if (!this._orderId) {
                this._orderId = id;
                this._quoteId = null;
                await this.loadData();
            } else {
                await this.loadData();
            }
        }
    }

    async handleSaveAndNext() {
        const id = await this._save(true);
        if (id) {
            window.location.href = `/lightning/cmp/Billantix__orderLineEditor?c__recordId=${id}`;
        }
    }

    async _save(copyLines = false) {
        this.errorMsg = null;
        this.saving   = true;
        const payload = JSON.stringify({
            Pricebook2Id:      this.selectedPricebook2Id || null,
            OpportunityId:     this.opportunityId        || null,
            Status:            this.status,
            EffectiveDate:     this.effectiveDate        || null,
            EndDate:           this.endDate              || null,
            Description:       this.description          || null,
            BillingStreet:     this.billingStreet        || null,
            BillingCity:       this.billingCity          || null,
            BillingState:      this.billingState         || null,
            BillingPostalCode: this.billingPostalCode    || null,
            BillingCountry:    this.billingCountry       || null
        });
        try {
            if (this._orderId) {
                await saveOrderGeneralInfo({ orderId: this._orderId, orderJson: payload });
                return this._orderId;
            } else {
                const newId = await createOrder({ quoteId: this._quoteId, orderJson: payload, copyLines });
                return newId;
            }
        } catch (err) {
            this.errorMsg = err?.body?.message || 'Save failed.';
            return null;
        } finally {
            this.saving = false;
        }
    }
}
