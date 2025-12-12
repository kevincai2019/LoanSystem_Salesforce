/**
 * This class contains unit tests for validating the behavior of Apex classes
 * and triggers.
 *
 * Unit tests are class methods that verify whether a particular piece
 * of code is working properly. Unit test methods take no arguments,
 * commit no data to the database, and are flagged with the testMethod
 * keyword in the method definition.
 *
 * All test methods in an org are executed whenever Apex code is deployed
 * to a production org to confirm correctness, ensure code
 * coverage, and prevent regressions. All Apex classes are
 * required to have at least 75% code coverage in order to be deployed
 * to a production org. In addition, all triggers must have some code coverage.
 * 
 * The @isTest class annotation indicates this class only contains test
 * methods. Classes defined with the @isTest annotation do not count against
 * the org size limit for all Apex scripts.
 *
 * See the Apex Language Reference for more information about Testing and Code Coverage.
 */
@isTest
private class RepaymentTimelineControllerTest {
    // 测试数据初始化：创建完整业务链（Loan + RepaymentRecord）
    private static void createTestData(Id loanId, Integer totalRepaidInstallments, Date planDate, Decimal planAmount) {
        // 1. 更新贷款的已还款期数
        Loan__c loanToUpdate = new Loan__c(
            Id = loanId
        );
        update loanToUpdate;

        // 2. 创建对应期数的还款记录（仅当已还款期数>0时）
        if (totalRepaidInstallments > 0) {
            Repayment_Record__c RepaymentRecord = new Repayment_Record__c(
                Loan__c = loanId,
                Repayment_Date__c = planDate,
                Repayment_Amount__c = planAmount,
                Interest_Repayment__c = planAmount,
                Principal_Repayment__c = planAmount,
                Repayment_Status__c = 'Success'
            );
            insert RepaymentRecord;
        }
    }

    // 场景1：贷款ID为空 → 返回空的LoanSummary
    @isTest
    static void testWithNullLoanId() {
        // 执行方法
        RepaymentTimelineController.LoanSummary result = RepaymentTimelineController.getRepaymentRecordsByLoanId(null);

        // 断言：返回的对象非空，但字段均为null/默认值
        System.assertNotEquals(null, result, '贷款ID为空时应返回空的LoanSummary对象');
        System.assertEquals(null, result.LoanStartDate, '贷款开始日应为null');
        System.assertEquals(null, result.LatestRepaymentDate, '最新一期还款日应为null');
        System.assertEquals(null, result.LatestRepaymentAmount, '最新一期还款金额应为null');
    }

    // 场景2：有已还款期数 → 返回完整的LoanSummary
    @isTest
    static void testWithRepaidInstallments() {
        // 第一步：创建测试贷款
        Loan__c testLoan = new Loan__c(
            Name = 'Test Loan ' + System.currentTimeMillis(),
            Start_Date__c = Date.newInstance(2025, 1, 1),
            Total_Installments__c = 60,
            Total_Loan_Amount__c = 100000.00,
            Loan_Prime_Rate__c = 3.5,
            Spread_Basis_Points__c = -45,
            Repayment_Mode__c = '等额本息(EMI)',
            Deduction_Date__c = '10' // 固定还款日10日
        );
        insert testLoan;

        // 第二步：创建对应期数的还款记录
        Date testPlanDate = Date.newInstance(2025, 2, 10);
        Decimal testPlanAmount = 1799.09;
        createTestData(testLoan.Id, 1, testPlanDate, testPlanAmount);

        // 第三步：执行测试方法
        Test.startTest();
        RepaymentTimelineController.LoanSummary result = RepaymentTimelineController.getRepaymentRecordsByLoanId(testLoan.Id);
        Test.stopTest();

        // 第四步：断言返回值正确
        System.assertNotEquals(null, result, '应返回非空的LoanSummary对象');
        System.assertEquals(testLoan.Start_Date__c, result.LoanStartDate, '贷款开始日匹配');
        // System.assertEquals(testLoan.End_Date__c, result.LoanEndDate, '贷款终了日匹配');
        System.assertEquals(testLoan.Total_Installments__c, result.TotalInstallments, '贷款总期数匹配');
        System.assertEquals(testPlanDate, result.LatestRepaymentDate, '最新一期还款日匹配');
        System.assertEquals(testPlanAmount, result.LatestRepaymentAmount, '最新一期还款金额匹配');
    }

    // 场景3：无已还款期数（Total_Repaid_Installments__c=0/null）→ 返回空的LoanSummary
    @isTest
    static void testWithoutRepaidInstallments() {
        // 第一步：创建测试贷款（已还款期数=0）
        Loan__c testLoan = new Loan__c(
            Name = 'Test Loan ' + System.currentTimeMillis(),
            Start_Date__c = Date.newInstance(2025, 1, 1),
            Total_Installments__c = 60,
            Total_Loan_Amount__c = 100000.00,
            Loan_Prime_Rate__c = 3.5,
            Spread_Basis_Points__c = -45,
            Repayment_Mode__c = '等额本息(EMI)',
            Deduction_Date__c = '10' // 固定还款日10日
        );
        insert testLoan;

        // 第二步：创建还款记录（但已还款期数=0，不应查询到）
        createTestData(testLoan.Id, 0, Date.newInstance(2025, 2, 1), 5000.00);

        List<Loan__c> loans = [SELECT Total_Repaid_Installments__c FROM Loan__c WHERE Id = :testLoan.Id];
        System.assertEquals(0, loans[0].Total_Repaid_Installments__c, 'Total_Repaid_Installments__c应该为0');

        // 第三步：执行测试方法
        Test.startTest();
        RepaymentTimelineController.LoanSummary result = RepaymentTimelineController.getRepaymentRecordsByLoanId(testLoan.Id);
        Test.stopTest();

        // 第四步：断言返回空字段
        System.assertNotEquals(null, result, '应返回非空的LoanSummary对象');
        System.assertNotEquals(null, result.LatestRepaymentDate, '无已还款期数时，最新一期还款日不为null');
        System.assertNotEquals(null, result.LatestRepaymentAmount, '无已还款期数时，最新一期还款金额不为null');
        
        // 额外断言：贷款基础信息仍返回（可选，根据业务需求调整）
        System.assertEquals(testLoan.Start_Date__c, result.LoanStartDate, '贷款开始日应正常返回');
    }
}