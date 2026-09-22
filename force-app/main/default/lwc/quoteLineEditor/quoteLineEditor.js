import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getQuoteData         from '@salesforce/apex/QuoteLineEditorController.getQuoteData';
import saveQuoteLines       from '@salesforce/apex/QuoteLineEditorController.saveQuoteLines';
import createOrderFromQuote from '@salesforce/apex/QuoteLineEditorController.createOrderFromQuote';
import getEntriesForPricebook from '@salesforce/apex/QuoteLineEditorController.getEntriesForPricebook';

const FMT = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', minimumFractionDigits: 2 });
const fmt = (v) => FMT.format(v || 0);

const BILLING_PERIOD_OPTIONS = [
    { label: 'Monthly',   value: 'Monthly'  },
    { label: 'Quarterly', value: 'Quarterly' },
    { label: 'Annual',    value: 'Annual'    },
    { label: 'One-Time',  value: 'One-Time'  }
];

let seq = 0;

export default class QuoteLineEditor extends NavigationMixin(LightningElement) {

    @api
    get recordId() { return this._recordId; }
    set recordId(value) {
        this._recordId = value;
        if (value && !this.isReady && !this.isLoading) this.loadData();
    }
    _recordId;

    @track quote             = null;
    @track lines             = [];
    @track deletedLineIds    = [];
    @track isLoading         = false;
    @track isReady           = false;
    @track errorMessage      = '';
    @track isDragOver        = false;

    @track billingPeriod       = '';
    @track startDate           = '';
    @track endDate             = '';
    @track headerDiscount      = 0;
    @track selectedPricebook2Id = '';
    @track productPanelOpen    = false;
    @track selectedRowTempId   = null;
    @track showOrderModal      = false;
    _savedQuoteId              = null;

    billingPeriodOptions = BILLING_PERIOD_OPTIONS;

    _allProducts       = [];
    _pricebookEntryMap = {};
    _productIdToEntry  = {};
    _bundleOptionsMap  = {};

    @wire(CurrentPageReference)
    handlePageRef(ref) {
        if (ref?.state?.c__recordId && !this.recordId) {
            this.recordId = ref.state.c__recordId;
        }
        if (this.recordId && !this.isReady) {
            this.loadData();
        }
    }

    connectedCallback() {
        if (this.recordId) this.loadData();
    }

    // ── Data Loading ─────────────────────────────────────────────────────────

    async loadData() {
        this.isLoading = true;
        this.errorMessage = '';
        try {
            const data = await getQuoteData({ quoteId: this.recordId });
            this.quote = data.quote;

            this.billingPeriod        = data.quote.Billing_Period__c || '';
            this.startDate            = data.quote.Start_Date__c     || '';
            this.endDate              = data.quote.ExpirationDate    || '';
            this.selectedPricebook2Id = data.quote.Pricebook2Id      || '';

            this._pricebookEntryMap = {};
            this._productIdToEntry  = {};
            this._allProducts = (data.pricebookEntries || []).map(e => {
                this._pricebookEntryMap[e.Id]        = e;
                this._productIdToEntry[e.Product2Id] = e;
                return {
                    entryId:        e.Id,
                    name:           e.Product2.Name,
                    productType:    e.Product2.Product_Type__c || '',
                    uom:            e.Product2.UOM__c || '',
                    isBundle:       e.Product2.IsBundle__c || false,
                    price:          e.UnitPrice,
                    priceFormatted: fmt(e.UnitPrice)
                };
            });

            this._bundleOptionsMap = {};
            (data.productOptions || []).forEach(opt => {
                const bid = opt.Bundle__c;
                if (!this._bundleOptionsMap[bid]) this._bundleOptionsMap[bid] = [];
                this._bundleOptionsMap[bid].push({
                    componentProductId: opt.Component__c,
                    name:               opt.Component__r?.Name || '',
                    qty:                opt.Quantity__c || 1,
                    isOptional:         opt.IsOptional__c || false
                });
            });

            this.lines = (data.lines || []).map(l => this._mapLine(l));
            this.isReady = true;
        } catch (err) {
            this.errorMessage = err?.body?.message || 'Failed to load quote data.';
            this.isReady = true;
        } finally {
            this.isLoading = false;
        }
    }

    // ── Computed ─────────────────────────────────────────────────────────────

    get allProducts()     { return this._allProducts; }

    get topBarTitle()     { return this.quote ? `Editing: ${this.quote.Name}` : 'Quote Line Editor'; }
    get quoteName()       { return this.quote?.Name        || ''; }
    get quoteNumber()     { return this.quote?.QuoteNumber || ''; }
    get opportunityName() { return this.quote?.Opportunity?.Name || '—'; }
    get accountName()     { return this.quote?.Account?.Name     || '—'; }
    get pricebookName()   { return this.quote?.Pricebook2?.Name  || '—'; }

    get linesAreaClass()    { return 'lines-area'; }
    get productPanelClass() { return this.productPanelOpen ? 'product-panel product-panel--open' : 'product-panel'; }

    get stepDotGeneral()   { return 'step-dot'; }
    get stepLabelGeneral() { return 'step-label'; }

    get statusBadgeCls() {
        const s = (this.quote?.Status || '').toLowerCase().replace(/\s+/g, '-');
        return `status-badge status-badge--${s}`;
    }

    get hasLines()  { return this.lines.length > 0; }
    get isEmpty()   { return this.isReady && this.lines.length === 0; }
    get lineCount() { return this.lines.length; }

    get lines() { return this._lines; }
    set lines(val) {
        this._lines = (val || []).map(l => ({
            ...l,
            rowClass: l.tempId === this.selectedRowTempId ? 'row--selected' : '',
            qtyClass: l.tempId === this.selectedRowTempId ? 'col-qty qty-cell--active' : 'col-qty',
            listPriceFormatted: fmt(l.UnitPrice)
        }));
    }
    _lines = [];

    get dropZoneClass() {
        return this.isDragOver ? 'drop-zone drop-zone--active' : 'drop-zone';
    }

    get subtotal() {
        return this.lines.reduce((s, l) => s + (parseFloat(l.Quantity) || 0) * (parseFloat(l.UnitPrice) || 0), 0);
    }

    get discountTotal() {
        return this.lines.reduce((s, l) => {
            const base = (parseFloat(l.Quantity) || 0) * (parseFloat(l.UnitPrice) || 0);
            return s + base * ((parseFloat(l.Discount) || 0) / 100);
        }, 0);
    }

    get netTotal() { return this.subtotal - this.discountTotal; }

    get subtotalFormatted()      { return fmt(this.subtotal); }
    get discountTotalFormatted() { return this.discountTotal > 0 ? `-${fmt(this.discountTotal)}` : fmt(0); }
    get netTotalFormatted()      { return fmt(this.netTotal); }

    // ── Header Field Handlers ─────────────────────────────────────────────────

    handleHeaderChange(event) {
        const field = event.currentTarget.dataset.field;
        const value = event.detail.value;
        if (field === 'Billing_Period__c') this.billingPeriod = value;
        if (field === 'Start_Date__c')     this.startDate     = value;
        if (field === 'ExpirationDate')    this.endDate       = value;
    }

    async handlePricebookChange(event) {
        const newId = event.detail.recordId || '';
        this.selectedPricebook2Id = newId;
        if (newId) await this._loadProductsForPricebook(newId);
        else this._allProducts = [];
    }

    async _loadProductsForPricebook(pricebook2Id) {
        try {
            const entries = await getEntriesForPricebook({ pricebook2Id });
            this._pricebookEntryMap = {};
            this._productIdToEntry  = {};
            this._allProducts = entries.map(e => {
                this._pricebookEntryMap[e.Id]        = e;
                this._productIdToEntry[e.Product2Id] = e;
                return {
                    entryId:        e.Id,
                    name:           e.Product2.Name,
                    productType:    e.Product2.Product_Type__c || '',
                    uom:            e.Product2.UOM__c || '',
                    isBundle:       e.Product2.IsBundle__c || false,
                    price:          e.UnitPrice,
                    priceFormatted: fmt(e.UnitPrice)
                };
            });
        } catch (err) {
            this.errorMessage = err?.body?.message || 'Failed to load products.';
        }
    }

    handleHeaderDiscountChange(event) {
        this.headerDiscount = parseFloat(event.target.value) || 0;
    }

    handleToggleProductPanel() {
        this.productPanelOpen = !this.productPanelOpen;
    }

    handleRowClick(event) {
        const tempId = event.currentTarget.dataset.tempid;
        this.selectedRowTempId = tempId === this.selectedRowTempId ? null : tempId;
        this.lines = [...this._lines];
    }

    handleGoToGeneral() {
        window.location.href = `/lightning/cmp/Billantix__quoteGeneralInfo?c__recordId=${this.recordId}`;
    }

    handleGoToCreateOrder() {
        window.location.href = `/lightning/cmp/Billantix__orderGeneralInfo?c__quoteId=${this.recordId}`;
    }

    // ── Product Selector Events ───────────────────────────────────────────────

    handleProductSelect(event) {
        this._addLineFromEntry(event.detail.entryId);
    }

    handleProductDragStart() {
        // dataTransfer is set by productSelector via native event — no action needed here
    }

    // ── Drag & Drop (Drop Zone) ───────────────────────────────────────────────

    handleDragOver(event) {
        event.preventDefault();
        event.dataTransfer.dropEffect = 'copy';
        this.isDragOver = true;
    }

    handleDragLeave() {
        this.isDragOver = false;
    }

    handleDrop(event) {
        event.preventDefault();
        this.isDragOver = false;
        const entryId = event.dataTransfer.getData('text/plain');
        if (entryId) this._addLineFromEntry(entryId);
    }

    // ── Line Management ───────────────────────────────────────────────────────

    handleAddEmptyLine() {
        seq++;
        this.lines = [...this.lines, {
            tempId:             `new-${seq}`,
            Id:                 null,
            Product2Id:         null,
            PricebookEntryId:   null,
            productName:        '',
            productType:        '',
            isBundle:           false,
            isBundleComponent:  false,
            bundleParentTempId: null,
            Quantity:           1,
            UnitPrice:          0,
            Discount:           0,
            Description:        '',
            lineSubtotal:       0,
            lineTotalFormatted: fmt(0)
        }];
    }

    _addLineFromEntry(entryId) {
        const entry = this._pricebookEntryMap[entryId];
        if (!entry) return;

        seq++;
        const parentTempId = `new-${seq}`;

        const newLines = [{
            tempId:             parentTempId,
            Id:                 null,
            Product2Id:         entry.Product2Id,
            PricebookEntryId:   entry.Id,
            productName:        entry.Product2.Name,
            productType:        entry.Product2.Product_Type__c || '',
            isBundle:           entry.Product2.IsBundle__c || false,
            isBundleComponent:  false,
            bundleParentTempId: null,
            Quantity:           1,
            UnitPrice:          entry.UnitPrice,
            Discount:           0,
            Description:        '',
            lineSubtotal:       entry.UnitPrice,
            lineTotalFormatted: fmt(entry.UnitPrice)
        }];

        if (entry.Product2.IsBundle__c) {
            const components = this._bundleOptionsMap[entry.Product2Id] || [];
            components.forEach(comp => {
                seq++;
                const compEntry = this._productIdToEntry[comp.componentProductId];
                const compPrice = compEntry ? compEntry.UnitPrice : 0;
                newLines.push({
                    tempId:             `new-${seq}`,
                    Id:                 null,
                    Product2Id:         comp.componentProductId,
                    PricebookEntryId:   compEntry ? compEntry.Id : null,
                    productName:        comp.name,
                    productType:        compEntry?.Product2?.Product_Type__c || '',
                    isBundle:           false,
                    isBundleComponent:  true,
                    bundleParentTempId: parentTempId,
                    Quantity:           comp.qty,
                    UnitPrice:          compPrice,
                    Discount:           0,
                    Description:        '',
                    lineSubtotal:       compPrice * comp.qty,
                    lineTotalFormatted: fmt(compPrice * comp.qty)
                });
            });
        }

        this.lines = [...this.lines, ...newLines];
    }

    handleRemoveLine(event) {
        const tempId = event.currentTarget.dataset.tempid;
        const line   = this.lines.find(l => l.tempId === tempId);
        if (!line) return;

        const tempIdsToRemove = new Set([tempId]);
        if (line.isBundle) {
            this.lines
                .filter(l => l.bundleParentTempId === tempId)
                .forEach(l => tempIdsToRemove.add(l.tempId));
        }

        this.lines
            .filter(l => tempIdsToRemove.has(l.tempId) && l.Id)
            .forEach(l => { this.deletedLineIds = [...this.deletedLineIds, l.Id]; });

        this.lines = this.lines.filter(l => !tempIdsToRemove.has(l.tempId));
    }

    handleLineFieldChange(event) {
        const tempId = event.currentTarget.dataset.tempid;
        const field  = event.target.dataset.field;
        const value  = event.target.value;

        this.lines = this.lines.map(line => {
            if (line.tempId !== tempId) return line;
            const updated = { ...line, [field]: value };
            const base    = (parseFloat(updated.Quantity) || 0) * (parseFloat(updated.UnitPrice) || 0);
            const disc    = base * ((parseFloat(updated.Discount) || 0) / 100);
            const net     = base - disc;
            return { ...updated, lineSubtotal: net, lineTotalFormatted: fmt(net) };
        });
    }

    // ── Save / Cancel ─────────────────────────────────────────────────────────

    handleCancel() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: this.recordId, objectApiName: 'Quote', actionName: 'view' }
        });
    }

    async handleSave() {
        if (!this._validate()) return;
        this.isLoading = true;
        this.errorMessage = '';
        try {
            await saveQuoteLines({
                quoteId:           this.recordId,
                quoteHeaderJson:   JSON.stringify({
                    Billing_Period__c: this.billingPeriod        || null,
                    Start_Date__c:     this.startDate            || null,
                    ExpirationDate:    this.endDate              || null,
                    Pricebook2Id:      this.selectedPricebook2Id || null
                }),
                linesToUpsertJson: JSON.stringify(
                    this.lines.map(({ Id, PricebookEntryId, Product2Id, Quantity, UnitPrice, Discount, Description }) => ({
                        Id, PricebookEntryId, Product2Id, Quantity, UnitPrice, Discount, Description
                    }))
                ),
                lineIdsToDelete: this.deletedLineIds
            });
            this.deletedLineIds = [];
            await this.loadData();
            this._savedQuoteId = this.recordId;
            this.showOrderModal = true;
        } catch (err) {
            this.errorMessage = err?.body?.message || 'Save failed.';
        } finally {
            this.isLoading = false;
        }
    }

    // ── Order Modal Handlers ──────────────────────────────────────────────────

    async handleOrderNow() {
        this.showOrderModal = false;
        this.isLoading = true;
        this.errorMessage = '';
        try {
            const orderId = await createOrderFromQuote({ quoteId: this._savedQuoteId });
            this.dispatchEvent(new ShowToastEvent({ title: 'Order Created', message: 'Order created successfully.', variant: 'success' }));
            window.location.href = `/lightning/cmp/Billantix__orderLineEditor?c__recordId=${orderId}`;
        } catch (err) {
            this.errorMessage = err?.body?.message || 'Failed to create order.';
            this.isLoading = false;
        }
    }

    handleOrderLater() {
        this.showOrderModal = false;
        const oppId = this.quote?.OpportunityId;
        if (oppId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId: oppId, objectApiName: 'Opportunity', actionName: 'view' }
            });
        } else {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId: this.recordId, objectApiName: 'Quote', actionName: 'view' }
            });
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    _mapLine(line) {
        const base = (parseFloat(line.Quantity) || 0) * (parseFloat(line.UnitPrice) || 0);
        const disc = base * ((parseFloat(line.Discount) || 0) / 100);
        const net  = base - disc;
        return {
            tempId:             `existing-${line.Id}`,
            Id:                 line.Id,
            Product2Id:         line.Product2Id,
            PricebookEntryId:   line.PricebookEntryId,
            productName:        line.Product2?.Name || '',
            productType:        line.Product2?.Product_Type__c || '',
            isBundle:           line.Product2?.IsBundle__c || false,
            isBundleComponent:  false,
            bundleParentTempId: null,
            Quantity:           line.Quantity,
            UnitPrice:          line.UnitPrice,
            Discount:           line.Discount ?? 0,
            Description:        line.Description ?? '',
            lineSubtotal:       net,
            lineTotalFormatted: fmt(net)
        };
    }

    _validate() {
        if (!this.selectedPricebook2Id) {
            this.errorMessage = 'A Price Book is required.';
            return false;
        }
        const bad = this.lines.filter(l => !l.Quantity || parseFloat(l.Quantity) <= 0);
        if (bad.length) {
            this.errorMessage = 'All lines must have a quantity greater than 0.';
            return false;
        }
        return true;
    }
}
