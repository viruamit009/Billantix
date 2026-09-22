import { LightningElement, api } from 'lwc';

export default class AccountBillingDashboardAction extends LightningElement {
    @api recordId;

    @api invoke() {
        window.location.href = `/lightning/cmp/Billantix__accountBillingDashboard?c__accountId=${this.recordId}`;
    }
}
