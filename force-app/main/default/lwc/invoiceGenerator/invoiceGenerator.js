import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getInvoiceData       from '@salesforce/apex/InvoiceGeneratorController.getInvoiceData';
import postInvoice          from '@salesforce/apex/InvoiceGeneratorController.postInvoice';
import cancelInvoice        from '@salesforce/apex/InvoiceGeneratorController.cancelInvoice';
import runInvoiceBatch      from '@salesforce/apex/InvoiceGeneratorController.runInvoiceBatch';
import scheduleInvoiceBatch from '@salesforce/apex/InvoiceGeneratorController.scheduleInvoiceBatch';
import getScheduledJobs     from '@salesforce/apex/InvoiceGeneratorController.getScheduledJobs';

const FMT = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', minimumFractionDigits: 2 });
const fmt = (v) => FMT.format(v || 0);

const CRON_PRESETS = [
    { label: 'Daily 2am',   cron: '0 0 2 * * ?' },
    { label: 'Daily 6am',   cron: '0 0 6 * * ?' },
    { label: 'Weekly Mon',  cron: '0 0 6 ? * MON' },
    { label: 'Monthly 1st', cron: '0 0 6 1 * ?' }
];

export default class InvoiceGenerator extends LightningElement {

    @api recordId;

    @track invoice       = null;
    @track lines         = [];
    @track scheduledJobs = [];
    @track isLoading     = false;
    @track isReady       = false;
    @track errorMessage  = '';
    @track batchJobId    = '';
    @track cronExpression = '0 0 2 * * ?';
    @track jobName       = '';

    cronPresets = CRON_PRESETS;

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

    async loadData() {
        this.isLoading = true;
        this.errorMessage = '';
        try {
            const data = await getInvoiceData({ invoiceId: this.recordId });
            this.invoice = data.invoice;
            this.lines = (data.lines || []).map(l => ({
                ...l,
                unitPriceFormatted:  fmt(l.UnitPrice),
                lineAmountFormatted: fmt(l.LineAmount)
            }));
            const jobs = await getScheduledJobs();
            this.scheduledJobs = jobs || [];
            this.isReady = true;
        } catch (err) {
            this.errorMessage = err?.body?.message || 'Failed to load invoice data.';
        } finally {
            this.isLoading = false;
        }
    }

    get isDraft()   { return this.invoice?.Status === 'Draft'; }
    get canCancel() { return this.invoice?.Status !== 'Cancelled'; }
    get hasLines()  { return this.lines.length > 0; }
    get isEmpty()   { return this.isReady && this.lines.length === 0; }
    get totalAmountFormatted() { return fmt(this.invoice?.TotalAmount); }

    get statusBadgeClass() {
        const s = this.invoice?.Status;
        if (s === 'Posted')    return 'slds-badge slds-badge_inverse slds-var-m-left_small';
        if (s === 'Cancelled') return 'slds-badge slds-theme_error slds-var-m-left_small';
        return 'slds-badge slds-var-m-left_small';
    }

    get hasScheduledJobs() { return this.scheduledJobs.length > 0; }
    get noScheduledJobs()  { return this.isReady && this.scheduledJobs.length === 0; }

    async handlePost() {
        this.isLoading = true;
        this.errorMessage = '';
        try {
            await postInvoice({ invoiceId: this.recordId });
            this.dispatchEvent(new ShowToastEvent({ title: 'Invoice Posted', message: 'Invoice status updated to Posted.', variant: 'success' }));
            await this.loadData();
        } catch (err) {
            this.errorMessage = err?.body?.message || 'Failed to post invoice.';
            this.isLoading = false;
        }
    }

    async handleCancel() {
        this.isLoading = true;
        this.errorMessage = '';
        try {
            await cancelInvoice({ invoiceId: this.recordId });
            this.dispatchEvent(new ShowToastEvent({ title: 'Invoice Cancelled', message: 'Invoice has been cancelled.', variant: 'warning' }));
            await this.loadData();
        } catch (err) {
            this.errorMessage = err?.body?.message || 'Failed to cancel invoice.';
            this.isLoading = false;
        }
    }

    async handleRunBatch() {
        this.isLoading = true;
        this.errorMessage = '';
        this.batchJobId = '';
        try {
            const jobId = await runInvoiceBatch();
            this.batchJobId = jobId;
            this.dispatchEvent(new ShowToastEvent({ title: 'Batch Started', message: `Job ID: ${jobId}`, variant: 'success' }));
        } catch (err) {
            this.errorMessage = err?.body?.message || 'Failed to run batch.';
        } finally {
            this.isLoading = false;
        }
    }

    async handleScheduleBatch() {
        if (!this.cronExpression?.trim()) {
            this.errorMessage = 'Cron expression is required.';
            return;
        }
        this.isLoading = true;
        this.errorMessage = '';
        try {
            await scheduleInvoiceBatch({ cronExpression: this.cronExpression, jobName: this.jobName });
            this.dispatchEvent(new ShowToastEvent({ title: 'Batch Scheduled', message: 'Invoice batch has been scheduled.', variant: 'success' }));
            const jobs = await getScheduledJobs();
            this.scheduledJobs = jobs || [];
        } catch (err) {
            this.errorMessage = err?.body?.message || 'Failed to schedule batch.';
        } finally {
            this.isLoading = false;
        }
    }

    handlePresetClick(event) { this.cronExpression = event.currentTarget.dataset.cron; }
    handleCronChange(event)    { this.cronExpression = event.detail.value; }
    handleJobNameChange(event) { this.jobName = event.detail.value; }
}
