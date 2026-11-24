@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',
        'PSAvoidGlobalVars',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSUseApprovedVerbs',
        'PSAvoidUsingEmptyCatchBlock',
        'PSAvoidUsingInvokeExpression'
    )
}
