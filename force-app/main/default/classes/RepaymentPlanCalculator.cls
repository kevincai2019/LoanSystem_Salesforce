/**
 * 还款计划计算工具类：支持等额本息、等额本金两种核心还款模式
 */
public with sharing class RepaymentPlanCalculator {

    // 计算还款日期的辅助方法
    private static Date getDeductionDate(Date baseDate, String deductionDay, Integer addMonths) {
        Date targetMonthDate = baseDate.addMonths(addMonths);
        Integer targetMonth = targetMonthDate.month();
        Integer targetYear = targetMonthDate.year();
        
        return Date.newInstance(targetYear, targetMonth, Integer.valueOf(deductionDay));
    }

    // 等额本息计算：每期还款额固定，按固定还款日生成计划
    public static List<Repayment_Plan__c> calculateEqualPrincipalInterest(
        Id loanId,
        Decimal totalLoanAmount,
        Decimal annualRate,
        Integer totalInstallments,
        Date startDate,
        String deductionDay
    ) {
        List<Repayment_Plan__c> planList = new List<Repayment_Plan__c>();
        Decimal monthlyRate = annualRate / 100 / 12; // 月利率
        Decimal remainingPrincipal = totalLoanAmount;

        // 等额本息核心公式
        Decimal installmentAmount;
        if (monthlyRate > 0) {
            
            Double monthlyRateDouble = monthlyRate.doubleValue();
            Double totalInstallmentsDouble = (Double)totalInstallments;
            
            // pow函数计算(1 + 月利率)^总期数 只支持Double类型
            Double powResult = Math.pow(1 + monthlyRateDouble, totalInstallmentsDouble);
            
            // 转回Decimal计算，保证金额精度
            installmentAmount = (totalLoanAmount * monthlyRate * Decimal.valueOf(powResult)) 
                / (Decimal.valueOf(powResult) - 1);
        } else {
            installmentAmount = totalLoanAmount / totalInstallments; // 0利率兜底
        }

        // 保留2位小数（四舍五入）
        installmentAmount = installmentAmount.setScale(2, System.RoundingMode.HALF_UP);

        // 逐期生成还款计划
        for (Integer i = 1; i <= totalInstallments; i++) {
            Date currentDeductionDate = getDeductionDate(startDate, deductionDay, i);
            Decimal currentInterest = (remainingPrincipal * monthlyRate).setScale(2, System.RoundingMode.HALF_UP);
            // 最后一期补足尾差，确保剩余本金清零
            Decimal currentPrincipal = (i == totalInstallments) 
                ? remainingPrincipal 
                : (installmentAmount - currentInterest).setScale(2, System.RoundingMode.HALF_UP);
            Decimal finalInstallmentAmount = (i == totalInstallments) 
                ? remainingPrincipal + currentInterest 
                : installmentAmount;
            
            planList.add(new Repayment_Plan__c(
                Loan__c = loanId,
                Installment_Number__c = i,
                Name = '第 ' + i + ' 期',
                Scheduled_Repayment_Date__c = currentDeductionDate,
                Scheduled_Principal__c = currentPrincipal,
                Scheduled_Interest__c = currentInterest,
                Scheduled_Repayment_Amount__c = finalInstallmentAmount
            ));

            remainingPrincipal = (remainingPrincipal - currentPrincipal).setScale(2, System.RoundingMode.HALF_UP);
        }
        return planList;
    }

    // 等额本金计算：每期固定本金，利息递减，按固定还款日生成计划
    public static List<Repayment_Plan__c> calculateEqualPrincipal(
        Id loanId,
        Decimal totalLoanAmount,
        Decimal annualRate,
        Integer totalInstallments,
        Date startDate,
        String deductionDay
    ) {
        List<Repayment_Plan__c> planList = new List<Repayment_Plan__c>();
        Decimal monthlyRate = annualRate / 100 / 12; // 月利率
        Decimal remainingPrincipal = totalLoanAmount;

        // 逐期生成还款计划
        for (Integer i = 1; i <= totalInstallments; i++) {
            Date currentDeductionDate = getDeductionDate(startDate, deductionDay, i);
            Decimal currentInterest = (remainingPrincipal * monthlyRate).setScale(2, System.RoundingMode.HALF_UP);
            // 最后一期补足剩余本金
            Decimal currentPrincipal = (i == totalInstallments) ? remainingPrincipal : (remainingPrincipal / totalInstallments).setScale(2, System.RoundingMode.HALF_UP);
            Decimal finalInstallmentAmount = (currentPrincipal + currentInterest).setScale(2, System.RoundingMode.HALF_UP);

            planList.add(new Repayment_Plan__c(
                Loan__c = loanId,
                Installment_Number__c = i,
                Name = '第 ' + i + ' 期',
                Scheduled_Repayment_Date__c = currentDeductionDate,
                Scheduled_Principal__c = currentPrincipal,
                Scheduled_Interest__c = currentInterest,
                Scheduled_Repayment_Amount__c = finalInstallmentAmount
            ));

            remainingPrincipal = (remainingPrincipal - currentPrincipal).setScale(2, System.RoundingMode.HALF_UP);
        }
        return planList;
    }
}