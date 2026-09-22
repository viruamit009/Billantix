import { LightningElement, api, track } from 'lwc';

const FIXED_CATS = [
    { label: 'All',        value: 'all'         },
    { label: 'Recurring',  value: 'Recurring'   },
    { label: 'One-Time',   value: 'One-Time'    },
    { label: 'Usage',      value: 'Usage-Based' },
    { label: 'Bundles',    value: 'bundles'     }
];

export default class ProductSelector extends LightningElement {
    /** Array of { entryId, name, productType, uom, isBundle, price, priceFormatted } */
    @api products = [];

    @track searchTerm     = '';
    @track activeCategory = 'all';

    // ── Computed ──────────────────────────────────────────────────────────────

    get categories() {
        return FIXED_CATS.map(c => ({
            ...c,
            cls: `ps-tab${c.value === this.activeCategory ? ' ps-tab--active' : ''}`
        }));
    }

    get visibleProducts() {
        const term = (this.searchTerm || '').toLowerCase();
        const cat  = this.activeCategory;

        return (this.products || [])
            .filter(p => {
                const matchSearch = !term
                    || p.name.toLowerCase().includes(term)
                    || (p.productType || '').toLowerCase().includes(term);
                const matchCat = cat === 'all'
                    || (cat === 'bundles' && p.isBundle)
                    || (cat !== 'bundles' && !p.isBundle && p.productType === cat);
                return matchSearch && matchCat;
            })
            .map(p => ({
                ...p,
                cardCls: `ps-card${p.isBundle ? ' ps-card--bundle' : ''}`
            }));
    }

    get productCount()  { return (this.products || []).length; }
    get noResults()     { return this.productCount > 0 && this.visibleProducts.length === 0; }
    get isEmpty()       { return this.productCount === 0; }

    // ── Handlers ──────────────────────────────────────────────────────────────

    handleSearch(evt) {
        this.searchTerm = evt.detail.value;
    }

    handleCatChange(evt) {
        this.activeCategory = evt.currentTarget.dataset.value;
    }

    handleDragStart(evt) {
        const entryId = evt.currentTarget.dataset.entryid;
        evt.dataTransfer.setData('text/plain', entryId);
        evt.dataTransfer.effectAllowed = 'copy';
    }

    handleAddClick(evt) {
        evt.stopPropagation();
        const entryId = evt.currentTarget.dataset.entryid;
        this.dispatchEvent(new CustomEvent('productselect', { detail: { entryId } }));
    }
}
