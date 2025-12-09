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
private class GenerateRepaymentPlanTest {
    // 测试等额本息（还款日10日，12期）
    @isTest
    static void testEqualPrincipalInterest() {
        // 1. 创建测试贷款（所有字段必填）
        Loan__c testLoan = new Loan__c(
            Name = '测试贷款-等额本息',
            Total_Loan_Amount__c = 100000.00,
            Loan_Prime_Rate__c = 3.5,
            Spread_Basis_Points__c = -45,
            Total_Installments__c = 12,
            Repayment_Mode__c = '等额本息(EMI)',
            Start_Date__c = Date.newInstance(2025, 1, 1),
            Deduction_Date__c = '10' // 固定还款日10日
        );
        insert testLoan;

        // 2. 验证计划生成
        List<Repayment_Plan__c> plans = [
            SELECT Id, Installment_Number__c, Scheduled_Repayment_Date__c 
            FROM Repayment_Plan__c WHERE Loan__c = :testLoan.Id
        ];
        System.assertEquals(12, plans.size(), '12期应生成12条计划');
        System.assertEquals(Date.newInstance(2025, 2, 10), plans[0].Scheduled_Repayment_Date__c, '首期还款日应为2025-02-10');
    }

    // 测试等额本金（还款日25日，6期）
    @isTest
    static void testEqualPrincipal() {
        Loan__c testLoan = new Loan__c(
            Name = '测试贷款-等额本金',
            Total_Loan_Amount__c = 60000.00,
            Loan_Prime_Rate__c = 3.5,
            Spread_Basis_Points__c = -45,
            Total_Installments__c = 6,
            Repayment_Mode__c = '等额本金(EPP)',
            Start_Date__c = Date.newInstance(2025, 1, 1),
            Deduction_Date__c = '25'
        );
        insert testLoan;

        List<Repayment_Plan__c> plans = [SELECT Id FROM Repayment_Plan__c WHERE Loan__c = :testLoan.Id];
        System.assertEquals(6, plans.size(), '6期应生成6条计划');
    }

    // 测试修改贷款期数后计划更新
    @isTest
    static void testUpdateInstallments() {
        // 1. 创建初始贷款（6期）
        Loan__c testLoan = new Loan__c(
            Name = '测试贷款-修改期数',
            Total_Loan_Amount__c = 60000.00,
            Loan_Prime_Rate__c = 3.5,
            Spread_Basis_Points__c = -45,
            Total_Installments__c = 6,
            Repayment_Mode__c = '等额本金(EPP)',
            Start_Date__c = Date.newInstance(2025, 1, 1),
            Deduction_Date__c = '15'
        );
        insert testLoan;

        // 2. 修改期数为12期
        testLoan.Total_Installments__c = 12;
        update testLoan;

        // 3. 验证计划数量更新
        List<Repayment_Plan__c> plans = [SELECT Id FROM Repayment_Plan__c WHERE Loan__c = :testLoan.Id];
        System.assertEquals(12, plans.size(), '修改为12期应生成12条计划');
    }

    @isTest
    //0 利率测试
    static void testZeroInterestRate() {
        Loan__c testLoan = new Loan__c(
            Name = '测试贷款-零利率',
            Total_Loan_Amount__c = 120000.00,
            Loan_Prime_Rate__c = 0.0,
            Spread_Basis_Points__c = 0,
            Total_Installments__c = 12,
            Repayment_Mode__c = '等额本息(EMI)',
            Start_Date__c = Date.newInstance(2025, 1, 1),
            Deduction_Date__c = '25'    
        );
        insert testLoan;

        List<Repayment_Plan__c> plans = [SELECT Id, Scheduled_Principal__c, Scheduled_Interest__c, Scheduled_Repayment_Amount__c FROM Repayment_Plan__c WHERE Loan__c = :testLoan.Id ORDER BY Installment_Number__c];
        System.assertEquals(12, plans.size(), '12期应生成12条计划');
        for (Repayment_Plan__c plan : plans) {
            System.assertEquals(0.00, plan.Scheduled_Interest__c, '利息应为0');
            System.assertEquals(10000.00, plan.Scheduled_Principal__c, '每期本金应为10000');
            System.assertEquals(10000.00, plan.Scheduled_Repayment_Amount__c, '每期还款金额应为10000');
        }
    }
}