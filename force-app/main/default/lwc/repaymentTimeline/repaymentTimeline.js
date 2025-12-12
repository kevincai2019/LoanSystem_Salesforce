import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import getRepaymentRecordsByLoanId from '@salesforce/apex/RepaymentTimelineController.getRepaymentRecordsByLoanId';

// 导入字段
import LOAN_ID_FIELD from '@salesforce/schema/Loan__c.Id';
import REPAYMENT_STATUS_FIELD from '@salesforce/schema/Repayment_Record__c.Repayment_Status__c';
import REPAYMENT_DATE_FIELD from '@salesforce/schema/Repayment_Record__c.Repayment_Date__c';
import REPAYMENT_AMOUNT_FIELD from '@salesforce/schema/Repayment_Record__c.Repayment_Amount__c';

export default class RepaymentTimeline extends LightningElement {
    @api recordId; // 接收Loan__c的ID（父组件传递）
    repaymentRecords = [];
    isLoading = true;

    // 封装时间轴节点样式（成功/失败区分）
    getNodeClass(status) {
        return status === 'Success' 
            ? 'slds-timeline__icon slds-timeline__icon_success slds-m-right_small' 
            : 'slds-timeline__icon slds-timeline__icon_error slds-m-right_small';
    }

    // 封装节点图标
    getNodeIcon(status) {
        return status === 'Success' 
            ? 'utility:success' 
            : 'utility:error';
    }

    // 封装状态文字样式
    getStatusClass(status) {
        return status === 'Success' 
            ? 'slds-text-color_success' 
            : 'slds-text-color_error';
    }

    // 格式化日期
    formatDate(dateStr) {
        if (!dateStr) return '';
        const date = new Date(dateStr);
        return `${date.getFullYear()}-${(date.getMonth()+1).toString().padStart(2, '0')}-${date.getDate().toString().padStart(2, '0')}`;
    }

    // 加载还款记录（按日期倒序）
    @wire(getRepaymentRecordsByLoanId, { loanId: '$recordId' })
    wiredRepaymentRecords({ data, error }) {
        this.isLoading = false;
        if (data) {
            this.repaymentRecords = data;
            console.log('还款记录加载成功：', data);
        } else if (error) {
            console.error('加载还款记录失败：', error);
        }
    }
}