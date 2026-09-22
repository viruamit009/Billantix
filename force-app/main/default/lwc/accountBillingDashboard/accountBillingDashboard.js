import { LightningElement, api, wire, track } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';

import getOverview       from '@salesforce/apex/AccountBillingDashboardController.getOverview';
import getOrders         from '@salesforce/apex/AccountBillingDashboardController.getOrders';
import getSubscriptions  from '@salesforce/apex/AccountBillingDashboardController.getSubscriptions';
import getEntitlements   from '@salesforce/apex/AccountBillingDashboardController.getEntitlements';
import getInvoices       from '@salesforce/apex/AccountBillingDashboardController.getInvoices';

export default class AccountBillingDashboard extends NavigationMixin(LightningElement) {
    /** Resolved account ID — comes from @api recordId or URL param c__accountId */
    @track _accountId;

    /** Set when embedded on a record page or passed from a quick action */
    @api
    get recordId() { return this._recordId; }
    set recordId(value) {
        this._recordId = value;
        if (value) this._accountId = value;
    }
    _recordId;

    overview      = null;
    orders        = null;
    subscriptions = null;
    entitlements  = null;
    invoices      = null;
    error         = null;

    orderSortField = 'EffectiveDate';
    orderSortDir   = 'desc';

    // ── Resolve accountId from URL params (when opened as a full App Page tab) ─
    @wire(CurrentPageReference)
    wiredPageRef(ref) {
        const urlId = ref?.state?.c__accountId;
        this._accountId = urlId || this.recordId;
    }

    // ── Wire adapters ────────────────────────────────────────────────────────
    @wire(getOverview, { accountId: '$_accountId' })
    wiredOverview({ data, error }) {
        if (data)  this.overview = data;
        if (error) { this.error = error.body?.message || 'Failed to load overview.'; this.overview = {}; }
    }

    @wire(getOrders, { accountId: '$_accountId' })
    wiredOrders({ data, error }) {
        if (data)  this.orders = this._addUrls(data, 'Order');
        if (error) { this.error = error.body?.message || 'Failed to load orders.'; this.orders = []; }
    }

    @wire(getSubscriptions, { accountId: '$_accountId' })
    wiredSubs({ data, error }) {
        if (data) {
            this.subscriptions = data.map(r => ({
                ...r,
                productName:  r.Product2__r?.Name,
                frequency:    r.BillingSchedule__r?.Billing_Frequency__c,
                _url: `/lightning/r/Subscription__c/${r.Id}/view`
            }));
        }
        if (error) { this.error = error.body?.message || 'Failed to load subscriptions.'; this.subscriptions = []; }
    }

    @wire(getEntitlements, { accountId: '$_accountId' })
    wiredEnts({ data, error }) {
        if (data) {
            this.entitlements = data.map(r => ({
                ...r,
                productName: r.Product2__r?.Name,
                _url: `/lightning/r/Entitlement__c/${r.Id}/view`
            }));
        }
        if (error) { this.error = error.body?.message || 'Failed to load entitlements.'; this.entitlements = []; }
    }

    @wire(getInvoices, { accountId: '$_accountId' })
    wiredInv({ data, error }) {
        if (data) {
            this.invoices = data.map(r => ({
                ...r,
                _url: `/lightning/r/Invoice/${r.Id}/view`,
                overdue: (r.DaysOverdue__c || 0) > 0
            }));
        }
        if (error) { this.error = error.body?.message || 'Failed to load invoices.'; this.invoices = []; }
    }

    // ── Computed ─────────────────────────────────────────────────────────────
    get formattedBalanceDue() {
        if (!this.overview) return '--';
        return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' })
            .format(this.overview.totalBalanceDue || 0);
    }

    get formattedLastPayment() {
        if (!this.overview?.lastPaymentAmount) return '--';
        return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' })
            .format(this.overview.lastPaymentAmount);
    }

    get noOrders()        { return this.orders?.length        === 0; }
    get noSubscriptions() { return this.subscriptions?.length === 0; }
    get noEntitlements()  { return this.entitlements?.length  === 0; }
    get noInvoices()      { return this.invoices?.length      === 0; }

    // ── Column defs ──────────────────────────────────────────────────────────
    get orderColumns() {
        return [
            { label: 'Order #',       fieldName: '_url', type: 'url', typeAttributes: { label: { fieldName: 'OrderNumber' }, target: '_blank' } },
            { label: 'Status',        fieldName: 'Status' },
            { label: 'Effective Date',fieldName: 'EffectiveDate', type: 'date-local', sortable: true },
            { label: 'Total Amount',  fieldName: 'TotalAmount',   type: 'currency' },
            { label: 'Renewal Of',    fieldName: 'RenewalOf__c' }
        ];
    }

    get subscriptionColumns() {
        return [
            { label: 'Name',       fieldName: '_url', type: 'url', typeAttributes: { label: { fieldName: 'Name' }, target: '_blank' } },
            { label: 'Product',    fieldName: 'productName' },
            { label: 'Status',     fieldName: 'Status__c' },
            { label: 'Start Date', fieldName: 'StartDate__c', type: 'date-local' },
            { label: 'End Date',   fieldName: 'EndDate__c',   type: 'date-local' },
            { label: 'Frequency',  fieldName: 'frequency' }
        ];
    }

    get entitlementColumns() {
        return [
            { label: 'Name',       fieldName: '_url', type: 'url', typeAttributes: { label: { fieldName: 'Name' }, target: '_blank' } },
            { label: 'Product',    fieldName: 'productName' },
            { label: 'Status',     fieldName: 'Status__c' },
            { label: 'Start Date', fieldName: 'StartDate__c', type: 'date-local' },
            { label: 'End Date',   fieldName: 'EndDate__c',   type: 'date-local' },
            { label: 'Qty',        fieldName: 'Quantity__c',  type: 'number' }
        ];
    }

    get invoiceColumns() {
        return [
            { label: 'Invoice',        fieldName: '_url', type: 'url', typeAttributes: { label: { fieldName: 'InvoiceNumber' }, target: '_blank' } },
            { label: 'Status',         fieldName: 'CollectionStatus__c' },
            { label: 'Due Date',       fieldName: 'DueDate',       type: 'date-local' },
            { label: 'Total',          fieldName: 'TotalAmount',   type: 'currency' },
            { label: 'Paid',           fieldName: 'AmountPaid__c', type: 'currency' },
            { label: 'Balance Due',    fieldName: 'BalanceDue__c', type: 'currency' },
            { label: 'Days Overdue',   fieldName: 'DaysOverdue__c',type: 'number' }
        ];
    }

    // ── Handlers ─────────────────────────────────────────────────────────────
    handleOrderSort(evt) {
        this.orderSortField = evt.detail.fieldName;
        this.orderSortDir   = evt.detail.sortDirection;
        const field = this.orderSortField;
        const dir   = this.orderSortDir === 'asc' ? 1 : -1;
        this.orders = [...this.orders].sort((a, b) => {
            if (a[field] < b[field]) return -1 * dir;
            if (a[field] > b[field]) return  1 * dir;
            return 0;
        });
    }

    // ── Helpers ──────────────────────────────────────────────────────────────
    _addUrls(records, sObjectType) {
        return records.map(r => ({ ...r, _url: `/lightning/r/${sObjectType}/${r.Id}/view` }));
    }
}
