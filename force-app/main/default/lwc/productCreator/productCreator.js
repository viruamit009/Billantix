import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import createProduct from '@salesforce/apex/ProductCreatorController.createProduct';

const PRODUCT_TYPE_OPTIONS = [
    { label: 'Flat Fee',     value: 'Flat Fee'     },
    { label: 'Recurring',    value: 'Recurring'    },
    { label: 'Usage-Based',  value: 'Usage-Based'  }
];

const UOM_OPTIONS = [
    { label: 'Seat',        value: 'Seat'        },
    { label: 'GB',          value: 'GB'          },
    { label: 'Hour',        value: 'Hour'        },
    { label: 'Unit',        value: 'Unit'        },
    { label: 'API Call',    value: 'API Call'    },
    { label: 'Transaction', value: 'Transaction' }
];

const BILLING_FREQUENCY_OPTIONS = [
    { label: 'Monthly',   value: 'Monthly'   },
    { label: 'Quarterly', value: 'Quarterly' },
    { label: 'Annual',    value: 'Annual'    },
    { label: 'One-Time',  value: 'One-Time'  }
];

export default class ProductCreator extends NavigationMixin(LightningElement) {

    @track fields = {
        Name:                '',
        ProductCode:         '',
        Description:         '',
        Product_Type__c:     '',
        UOM__c:              '',
        Billing_Frequency__c: '',
        IsActive:            true
    };

    @track unitPrice    = 0;
    @track isLoading    = false;
    @track errorMessage = '';

    productTypeOptions       = PRODUCT_TYPE_OPTIONS;
    uomOptions               = UOM_OPTIONS;
    billingFrequencyOptions  = BILLING_FREQUENCY_OPTIONS;

    // ── Computed ─────────────────────────────────────────────────────────────

    get showUOM() {
        return this.fields.Product_Type__c === 'Usage-Based';
    }

    get showBillingFrequency() {
        return this.fields.Product_Type__c === 'Recurring' ||
               this.fields.Product_Type__c === 'Usage-Based';
    }

    // ── Handlers ─────────────────────────────────────────────────────────────

    handleFieldChange(event) {
        const field = event.currentTarget.dataset.field;
        this.fields = { ...this.fields, [field]: event.detail.value };
        // Clear conditional fields when type changes
        if (field === 'Product_Type__c') {
            this.fields = { ...this.fields, UOM__c: '', Billing_Frequency__c: '' };
        }
    }

    handleCheckboxChange(event) {
        const field = event.currentTarget.dataset.field;
        this.fields = { ...this.fields, [field]: event.target.checked };
    }

    handleUnitPriceChange(event) {
        this.unitPrice = event.detail.value;
    }

    handleCancel() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'Product2', actionName: 'list' }
        });
    }

    async handleSave() {
        if (!this._validate()) return;

        this.isLoading    = true;
        this.errorMessage = '';
        try {
            const productId = await createProduct({
                productData: JSON.stringify(this.fields),
                unitPrice:   parseFloat(this.unitPrice) || 0
            });

            this.dispatchEvent(new ShowToastEvent({
                title:   'Product Created',
                message: `${this.fields.Name} was created successfully.`,
                variant: 'success'
            }));

            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId: productId, objectApiName: 'Product2', actionName: 'view' }
            });
        } catch (err) {
            this.errorMessage = err?.body?.message || 'Failed to create product.';
        } finally {
            this.isLoading = false;
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    _validate() {
        if (!this.fields.Name?.trim()) {
            this.errorMessage = 'Product Name is required.';
            return false;
        }
        if (!this.fields.Product_Type__c) {
            this.errorMessage = 'Product Type is required.';
            return false;
        }
        if (this.unitPrice == null || parseFloat(this.unitPrice) < 0) {
            this.errorMessage = 'Unit Price must be 0 or greater.';
            return false;
        }
        return true;
    }
}
