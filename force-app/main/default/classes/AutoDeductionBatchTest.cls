@isTest
private class AutoDeductionBatchTest {
    // 测试数据初始化：创建完整的业务数据链
    private static void createTestData(Date repaymentDate, Decimal bankBalance, Decimal deductionAmount) {
        // 1. 创建测试用户（用于邮件接收）
        User testUser = new User(
            Alias = 'testuser',
            Email = 'wen.cai.dl@ibm.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Test',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User'].Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'test' + System.currentTimeMillis() + '@example.com'
        );
        insert testUser;

        // 2. 创建Contact（关联银行账号）
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'wen.cai.dl@ibm.com'
        );
        insert testContact;

        // 3. 创建Bank_Account__c（设置余额）
        Bank_Account__c testBankAccount = new Bank_Account__c(
            Name = 'Test Bank Account',
            Balance__c = bankBalance, // 测试余额（充足/不足）
            Contact__c = testContact.Id // 关联Contact
        );
        insert testBankAccount;

        // 4. 创建Loan__c（关联银行账号，设置结束日）
        Loan__c testLoan = new Loan__c(
            Name = 'Test Loan',
            Total_Installments__c = 12, // 总期数
            Bank_Account__c = testBankAccount.Id, // 关联银行账号
            Repayment_Mode__c = '等额本息(EMI)', // 还款方式
            Deduction_Date__c = '15', // 还款日设置为测试日期的日部分
            Loan_Prime_Rate__c = 3.5,
            Spread_Basis_Points__c = -45,
            Loan_Type__c = '个人一手楼住房贷款',
            Total_Loan_Amount__c = 60000.00,
            Start_Date__c = repaymentDate.addMonths(-1), // 贷款起始日
            OwnerId = testUser.Id // 贷款所有者（用于邮件接收）
        );
        insert testLoan;

        // 5. 创建Repayment_Plan__c（还款日为今日，待扣款状态）
        Repayment_Plan__c testPlan = new Repayment_Plan__c(
            Loan__c = testLoan.Id, // 关联贷款
            Scheduled_Repayment_Date__c = repaymentDate, // 还款日=今日
            Scheduled_Repayment_Amount__c = deductionAmount, // 月供金额
            Scheduled_Principal__c = deductionAmount * 0.8, // 本金（示例比例）
            Scheduled_Interest__c = deductionAmount * 0.2, // 利息（示例比例）
            Installment_Number__c = 1 // 期数
        );
        insert testPlan;
    }

    // 测试场景1：余额充足 → 扣款成功
    @isTest
    static void testDeductionSuccess() {
        // 1. 初始化测试数据：余额1000，月供500（充足）
        Date today = Date.today();
        createTestData(today, 1000.00, 500.00);

        // 2. 模拟Batch执行
        Test.startTest();
        AutoDeductionBatch batch = new AutoDeductionBatch();
        Id batchJobId = Database.executeBatch(batch, 200);
        Test.stopTest();

        // 3. 断言验证
        // 3.1 验证银行账号余额：1000 - 500 = 500
        Bank_Account__c updatedAccount = [SELECT Balance__c FROM Bank_Account__c LIMIT 1];
        System.assertEquals(500.00, updatedAccount.Balance__c, '余额充足时，银行余额应扣减月供金额');

        // 3.2 验证还款记录：状态为Success，无失败原因
        Repayment_Record__c repaymentRecord = [SELECT Repayment_Status__c, Remarks__c, Repayment_Amount__c FROM Repayment_Record__c LIMIT 1];
        System.assertEquals('Success', repaymentRecord.Repayment_Status__c, '余额充足时，还款记录状态应为Success');
        System.assertEquals(null, repaymentRecord.Remarks__c, '余额充足时，失败原因应为空');
        System.assertEquals(500.00, repaymentRecord.Repayment_Amount__c, '还款记录金额应等于月供金额');

        // 3.3 验证Batch执行状态（无错误）
        AsyncApexJob batchJob = [SELECT Status, NumberOfErrors FROM AsyncApexJob WHERE Id = :batchJobId];
        System.assertEquals('Completed', batchJob.Status, 'Batch应执行完成');
        System.assertEquals(0, batchJob.NumberOfErrors, 'Batch执行应无错误');
    }

    // 测试场景2：余额不足 → 扣款失败
    @isTest
    static void testDeductionFailure() {
        // 1. 初始化测试数据：余额300，月供500（不足）
        Date today = Date.today();
        createTestData(today, 300.00, 500.00);

        // 2. 模拟Batch执行
        Test.startTest();
        AutoDeductionBatch batch = new AutoDeductionBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        // 3. 断言验证
        // 3.1 验证银行账号余额：未扣减，仍为300
        Bank_Account__c updatedAccount = [SELECT Balance__c FROM Bank_Account__c LIMIT 1];
        System.assertEquals(300.00, updatedAccount.Balance__c, '余额不足时，银行余额应保持不变');

        // 3.2 验证还款记录：状态为Failure，失败原因为“余额不足”
        Repayment_Record__c repaymentRecord = [SELECT Repayment_Status__c, Remarks__c FROM Repayment_Record__c LIMIT 1];
        System.assertEquals('Failure', repaymentRecord.Repayment_Status__c, '余额不足时，还款记录状态应为Failure');
        System.assertEquals('余额不足', repaymentRecord.Remarks__c, '失败原因应标注“余额不足”');
    }

    // 测试场景3：调度逻辑测试（Schedulable接口）
    @isTest
    static void testSchedulableExecution() {
        Date today = Date.today();
        createTestData(today, 2000.00, 800.00);

        Test.startTest();
        // 方式1：模拟调度创建（状态为WAITING）
        AutoDeductionBatch schedulableBatch = new AutoDeductionBatch();
        String cronExpr = '0 0 0 * * ?';
        Id scheduleJobId = System.schedule('Test Scheduled Deduction', cronExpr, schedulableBatch);
        
        // 方式2：直接执行调度逻辑（触发Batch）
        schedulableBatch.execute(null);
        Test.stopTest();

        // 验证调度任务创建成功
        CronTrigger cronTrigger = [SELECT State, NextFireTime FROM CronTrigger WHERE Id = :scheduleJobId];
        System.assertEquals('WAITING', cronTrigger.State, '调度任务应处于等待状态');
        System.assertNotEquals(null, cronTrigger.NextFireTime, '应设置下次执行时间');

        // 验证扣款结果
        Bank_Account__c updatedAccount = [SELECT Balance__c FROM Bank_Account__c LIMIT 1];
        System.assertEquals(1200.00, updatedAccount.Balance__c, '调度执行后应扣款成功');

        // 清理测试调度任务
        System.abortJob(scheduleJobId);
    }

    // 测试场景4：非当日还款日 → Batch无处理（边界场景）
    @isTest
    static void testNonTodayRepaymentDate() {
        // 1. 初始化测试数据：还款日为明日，而非今日
        Date tomorrow = Date.today().addDays(1);
        createTestData(tomorrow, 1000.00, 500.00);

        // 2. 模拟Batch执行
        Test.startTest();
        AutoDeductionBatch batch = new AutoDeductionBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        // 3. 断言验证：无还款记录生成，银行余额不变
        Integer repaymentRecordCount = [SELECT COUNT() FROM Repayment_Record__c];
        System.assertEquals(0, repaymentRecordCount, '非当日还款日不应生成还款记录');

        Bank_Account__c account = [SELECT Balance__c FROM Bank_Account__c LIMIT 1];
        System.assertEquals(1000.00, account.Balance__c, '非当日还款日银行余额应不变');
    }
}