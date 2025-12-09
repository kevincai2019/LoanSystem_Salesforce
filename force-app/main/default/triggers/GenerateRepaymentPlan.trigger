/**
 * 触发器：Loan__c新增/修改时，按必填固定还款日自动生成/更新还款计划
 * 字段均为必填，仅校验合法性，无空值判断
 */
trigger GenerateRepaymentPlan on Loan__c (after insert, after update) {

    Set<Id> validLoanIds = new Set<Id>();
    for (Loan__c loan : Trigger.new) {
        validLoanIds.add(loan.Id);
    }
    if (validLoanIds.isEmpty()) return;

    // 3. 删除关联的旧还款计划（避免重复）
    List<Repayment_Plan__c> oldPlans = [SELECT Id FROM Repayment_Plan__c WHERE Loan__c IN :validLoanIds];
    if (!oldPlans.isEmpty()) {
        delete oldPlans;
    }

    // 4. 批量查询贷款详情，生成新计划
    List<Repayment_Plan__c> newPlans = new List<Repayment_Plan__c>();
    List<Loan__c> loanList = [
        SELECT Id, Total_Loan_Amount__c, Annual_Interest_Rate__c,
               Total_Installments__c, Repayment_Mode__c, Start_Date__c, Deduction_Date__c
        FROM Loan__c WHERE Id IN :validLoanIds
    ];

    for (Loan__c loan : loanList) {
        Integer totalPeriods = loan.Total_Installments__c.intValue();
        // 按还款模式生成对应计划
        if (loan.Repayment_Mode__c == '等额本息(EMI)') {
            newPlans.addAll(RepaymentPlanCalculator.calculateEqualPrincipalInterest(
                loan.Id,
                loan.Total_Loan_Amount__c,
                loan.Annual_Interest_Rate__c,
                totalPeriods,
                loan.Start_Date__c,
                loan.Deduction_Date__c
            ));
        } else if (loan.Repayment_Mode__c == '等额本金(EPP)') {
            newPlans.addAll(RepaymentPlanCalculator.calculateEqualPrincipal(
                loan.Id,
                loan.Total_Loan_Amount__c,
                loan.Annual_Interest_Rate__c,
                totalPeriods,
                loan.Start_Date__c,
                loan.Deduction_Date__c
            ));
        }
    }

    // 5. 批量插入新计划（避免DML超限）
    if (!newPlans.isEmpty()) {
        insert newPlans;
    }
}