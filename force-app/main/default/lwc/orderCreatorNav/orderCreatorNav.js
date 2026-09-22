import { LightningElement, api } from 'lwc';

export default class OrderCreatorNav extends LightningElement {
    @api recordId; // Quote Id

    @api invoke() {
        window.location.href = `/lightning/cmp/Billantix__orderGeneralInfo?c__quoteId=${this.recordId}`;
    }
}
