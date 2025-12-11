/**
 * 每日执行的扣款Batch：动态筛选当日还款日的还款计划
 */
public with sharing class AutoDeductionBatch implements Database.Batchable<SObject>, Schedulable {
    public Database.QueryLocator start(Database.BatchableContext bc) {
        Date today = Date.today();
        
        // 核心查询：筛选「还款日=今日」+「贷款未到期」的还款计划
        String query = 'SELECT Id, Scheduled_Repayment_Amount__c, Installment_Number__c, Scheduled_Principal__c, Scheduled_Interest__c, ' +
                       'Loan__c, ' +
                       'Loan__r.Id, Loan__r.Total_Installments__c, Loan__r.End_Date__c, ' + // 贷款信息
                       'Loan__r.Bank_Account__c, ' + // 贷款关联的银行账号（Bank_Account__c的Lookup字段）
                       'Loan__r.Bank_Account__r.Id, Loan__r.Bank_Account__r.Balance__c ' + // 银行账号余额
                       'FROM Repayment_Plan__c ' +
                       'WHERE Scheduled_Repayment_Date__c = :today ' + // 动态匹配当日还款日
                       'AND Loan__r.Bank_Account__c != null';
        return Database.getQueryLocator(query);
    }

    // 2. 批量处理每条还款计划
    public void execute(Database.BatchableContext bc, List<Repayment_Plan__c> scope) {
        List<Bank_Account__c> updateAccounts = new List<Bank_Account__c>();
        List<Repayment_Record__c> newRecords = new List<Repayment_Record__c>();

        for (Repayment_Plan__c plan : scope) {
            Bank_Account__c bankAccount = plan.Loan__r.Bank_Account__r;
            Decimal deductionAmount = plan.Scheduled_Repayment_Amount__c;
            Decimal deductionPrincipal = plan.Scheduled_Principal__c;
            Decimal deductionInterest = plan.Scheduled_Interest__c;
            String status = 'Success';
            String failureReason = null;

            // 余额校验：余额≥月供金额则扣款
            if (bankAccount.Balance__c >= deductionAmount) {
                // 更新银行账号余额
                bankAccount.Balance__c = bankAccount.Balance__c - deductionAmount;
                updateAccounts.add(bankAccount);
            } else {
                status = 'Failure';
                failureReason = '余额不足';
            }

            // 插入还款记录
            newRecords.add(new Repayment_Record__c(
                Loan__c = plan.Loan__c,
                Repayment_Amount__c = deductionAmount,
                Interest_Repayment__c = deductionPrincipal,
                Principal_Repayment__c = deductionInterest,
                Repayment_Date__c = Date.today(),
                Repayment_Status__c = status,
                Remarks__c = failureReason
            ));
        }

        // 批量DML操作（避免超限）
        if (!updateAccounts.isEmpty()) update updateAccounts;
        if (!newRecords.isEmpty()) insert newRecords;
    }

    public void finish(Database.BatchableContext bc) {
        // 批量发送邮件给loan的contact，通知还款结果
        // 查询Batch执行结果
        AsyncApexJob job = [SELECT Id, Status, NumberOfErrors, JobItemsProcessed 
                            FROM AsyncApexJob WHERE Id = :bc.getJobId()];
        
        // 发送执行结果邮件
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        List<String> mailAddress = new List<String>();
        for (Repayment_Record__c record : [SELECT Loan__r.Owner.Email 
                                        FROM Repayment_Record__c 
                                        WHERE CreatedDate = TODAY]) {
            if (record.Loan__r.Owner.Email != null && !mailAddress.contains(record.Loan__r.Owner.Email)) {
                mailAddress.add(record.Loan__r.Owner.Email);
            }
        }
        if (!mailAddress.isEmpty()) {
            // 正常发送邮件
            mail.setToAddresses(mailAddress);
            mail.setSubject('扣款Batch执行完成：' + job.Status);
            mail.setPlainTextBody('处理记录数：' + job.JobItemsProcessed + '，错误数：' + job.NumberOfErrors);
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{mail});
        } else {
            // 记录无收件人的日志
            System.debug('本日无扣款请求或无有效收件人邮箱地址。');
        }
        
    }
    
    // 调度：每日凌晨0点执行（覆盖所有还款日）
    public void execute(SchedulableContext sc) {
        Database.executeBatch(this, 200);
    }
}