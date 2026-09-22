import { LightningElement, api } from 'lwc';

export default class OrderLineEditorNav extends LightningElement {
    @api recordId;

    @api invoke() {
        window.location.href = `/lightning/cmp/Billantix__orderLineEditor?c__recordId=${this.recordId}`;
    }
}
