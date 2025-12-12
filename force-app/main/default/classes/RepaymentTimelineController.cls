public with sharing class RepaymentTimelineController {

    // 定义返回的自定义对象（封装所需字段）
    public class LoanSummary {
        @AuraEnabled
        public Date LoanStartDate; // 贷款开始日
        @AuraEnabled
        public Date LoanEndDate;   // 贷款终了日
        @AuraEnabled
        public Decimal TotalInstallments; // 贷款总期数
        @AuraEnabled
        public Decimal LatestInstallmentNumber; // 最新一期还款期数
        @AuraEnabled
        public Date LatestRepaymentDate; // 最新一期还款日
        @AuraEnabled
        public Decimal LatestRepaymentAmount; // 最新一期还款金额
    }

    // 查询指定贷款的还款记录（按扣款日期倒序）
    @AuraEnabled(cacheable=true)
    public static LoanSummary getRepaymentRecordsByLoanId(Id loanId) {
        if (loanId == null) return new LoanSummary();

        List<Loan__c> loan = [SELECT Start_Date__c, End_Date__c, Total_Repaid_Installments__c, Total_Installments__c FROM Loan__c WHERE Id = :loanId];
        
        LoanSummary summary = new LoanSummary();
        summary.LoanStartDate = loan[0].Start_Date__c;
        summary.LoanEndDate = loan[0].End_Date__c;
        summary.LatestInstallmentNumber = loan[0].Total_Repaid_Installments__c;
        summary.TotalInstallments = loan[0].Total_Installments__c;
        if (loan[0].Total_Repaid_Installments__c == null || loan[0].Total_Repaid_Installments__c == 0) {
            List<Repayment_Plan__c> plans = [SELECT Scheduled_Repayment_Date__c, Scheduled_Repayment_Amount__c 
                                           FROM Repayment_Plan__c 
                                           WHERE Loan__c = :loanId And Installment_Number__c = 1
                                           LIMIT 1];
            if (plans.size() > 0) {
                summary.LatestRepaymentDate = plans[0].Scheduled_Repayment_Date__c;
                summary.LatestRepaymentAmount = plans[0].Scheduled_Repayment_Amount__c;
            }
            return summary;
        } else {
            List<Repayment_Plan__c> plans = [SELECT Scheduled_Repayment_Date__c, Scheduled_Repayment_Amount__c 
                                           FROM Repayment_Plan__c 
                                           WHERE Loan__c = :loanId And Installment_Number__c = :loan[0].Total_Repaid_Installments__c
                                           LIMIT 1];
            if (plans.size() > 0) {
                summary.LatestRepaymentDate = plans[0].Scheduled_Repayment_Date__c;
                summary.LatestRepaymentAmount = plans[0].Scheduled_Repayment_Amount__c;
            }
            return summary;
        }
    }
}