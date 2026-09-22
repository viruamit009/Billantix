import { LightningElement, api } from 'lwc';

export default class QuoteLineItemsNav extends LightningElement {
    @api recordId;

    @api invoke() {
        window.location.href = `/lightning/cmp/Billantix__quoteLineEditor?c__recordId=${this.recordId}`;
    }
}
