import { LightningElement, api } from 'lwc';

export default class QuoteCreatorNav extends LightningElement {
    @api recordId; // Opportunity Id

    @api invoke() {
        window.location.href = `/lightning/cmp/Billantix__quoteCreator?c__recordId=${this.recordId}`;
    }
}
