@{
    Severity = @('Error', 'Warning')

    ExcludeRules = @(
        # Source files are stored as UTF-8 without BOM in Git. PowerShell 5.1 reads
        # the module correctly because executable source and help text are ASCII.
        'PSUseBOMForUnicodeEncodedFile'

        # WMI is used only as a Windows PowerShell 5.1 fallback when CIM cmdlets
        # are unavailable on an older target.
        'PSAvoidUsingWMICmdlet'

        # Internal New-* functions construct objects and reports; they do not
        # mutate external state and therefore should not expose ShouldProcess.
        'PSUseShouldProcessForStateChangingFunctions'
    )

    Rules = @{
        PSAvoidUsingCmdletAliases = @{
            Whitelist = @()
        }

        PSUseConsistentIndentation = @{
            Enable              = $true
            Kind                = 'space'
            IndentationSize     = 4
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
        }
    }
}
