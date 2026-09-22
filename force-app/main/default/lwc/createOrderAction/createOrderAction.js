import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class CreateOrderAction extends LightningElement {
    @api recordId;

    connectedCallback() {
        this.dispatchEvent(new CloseActionScreenEvent());
        window.location.href = `/lightning/cmp/Billantix__orderGeneralInfo?c__quoteId=${this.recordId}`;
    }
}
