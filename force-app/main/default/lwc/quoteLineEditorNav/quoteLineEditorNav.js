import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class QuoteLineEditorNav extends NavigationMixin(LightningElement) {
    @api recordId;

    @api invoke() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: {
                apiName: 'QuoteLineEditor'
            },
            state: {
                c__recordId: this.recordId
            }
        });
    }
}
