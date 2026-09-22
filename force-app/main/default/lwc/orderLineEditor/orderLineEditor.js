import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getOrderData           from '@salesforce/apex/OrderController.getOrderData';
import saveOrderLines         from '@salesforce/apex/OrderController.saveOrderLines';
import getEntriesForPricebook from '@salesforce/apex/QuoteLineEditorController.getEntriesForPricebook';

const FMT = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', minimumFractionDigits: 2 });
const fmt = (v) => FMT.format(v || 0);

let seq = 0;

export default class OrderLineEditor extends NavigationMixin(LightningElement) {

    @api
    get recordId() { return this._recordId; }
    set recordId(value) {
        this._recordId = value;
        if (value && !this._loaded) this.loadData();
    }
    _recordId;
    _loaded = false;

    @track order              = null;
    @track lines              = [];
    @track deletedLineIds     = [];
    @track isLoading          = false;
    @track isReady            = false;
    @track errorMessage       = '';
    @track isDragOver         = false;

    @track billingPeriod        = '';
    @track startDate            = '';
    @track endDate              = '';
    @track selectedPricebook2Id = '';
    @track productPanelOpen     = false;
    @track selectedRowTempId    = null;

    _allProducts       = [];
    _pricebookEntryMap = {};
    _productIdToEntry  = {};
    _bundleOptionsMap  = {};

    @wire(CurrentPageReference)
    handlePageRef(ref) {
        const id = ref?.state?.c__recordId;
        if (id && !this._loaded) {
            this._recordId = id;
            this.loadData();
        }
    }

    // ── Data Loading ─────────────────────────────────────────────────────────

    async loadData() {
        this._loaded   = true;
        this.isLoading = true;
        this.errorMessage = '';
        try {
            const data = await getOrderData({ orderId: this.recordId });
            this.order = data.order;

            this.startDate            = data.order.EffectiveDate || '';
            this.endDate              = data.order.EndDate        || '';
            this.selectedPricebook2Id = data.order.Pricebook2Id   || '';
            this.billingPeriod        = '';

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

            this.lines = (data.lines || []).map(l => this._mapLine(l));
            this.isReady = true;
        } catch (err) {
            this.errorMessage = err?.body?.message || 'Failed to load order data.';
            this.isReady = true;
        } finally {
            this.isLoading = false;
        }
    }

    // ── Computed ─────────────────────────────────────────────────────────────

    get allProducts()   { return this._allProducts; }

    get orderNumber()   { return this.order?.OrderNumber || ''; }
    get accountName()   { return this.order?.Account?.Name || ''; }

    get linesAreaClass()    { return 'lines-area'; }
    get productPanelClass() { return this.productPanelOpen ? 'product-panel product-panel--open' : 'product-panel'; }

    get stepDotGeneral()   { return 'step-dot'; }
    get stepLabelGeneral() { return 'step-label'; }

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
        if (field === 'EffectiveDate') this.startDate = value;
        if (field === 'EndDate')       this.endDate   = value;
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

    handleToggleProductPanel() {
        this.productPanelOpen = !this.productPanelOpen;
    }

    handleRowClick(event) {
        const tempId = event.currentTarget.dataset.tempid;
        this.selectedRowTempId = tempId === this.selectedRowTempId ? null : tempId;
        this.lines = [...this._lines];
    }

    handleGoToGeneral() {
        window.location.href = `/lightning/cmp/Billantix__orderGeneralInfo?c__recordId=${this.recordId}`;
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
            attributes: { recordId: this.recordId, objectApiName: 'Order', actionName: 'view' }
        });
    }

    async handleSave() {
        if (!this._validate()) return;
        this.isLoading = true;
        this.errorMessage = '';
        try {
            await saveOrderLines({
                orderId:           this.recordId,
                orderHeaderJson:   JSON.stringify({
                    EffectiveDate: this.startDate            || null,
                    EndDate:       this.endDate              || null,
                    Pricebook2Id:  this.selectedPricebook2Id || null
                }),
                linesToUpsertJson: JSON.stringify(
                    this.lines.map(({ Id, PricebookEntryId, Product2Id, Quantity, UnitPrice, Discount, Description }) => ({
                        Id, PricebookEntryId, Product2Id, Quantity, UnitPrice, Discount, Description
                    }))
                ),
                lineIdsToDelete: this.deletedLineIds
            });
            this.deletedLineIds = [];
            this.dispatchEvent(new ShowToastEvent({
                title:   'Order Saved',
                message: 'Order and products saved successfully.',
                variant: 'success'
            }));
            this[NavigationMixin.Navigate]({
                type:       'standard__recordPage',
                attributes: { recordId: this.recordId, objectApiName: 'Order', actionName: 'view' }
            });
        } catch (err) {
            this.errorMessage = err?.body?.message || 'Save failed.';
        } finally {
            this.isLoading = false;
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
