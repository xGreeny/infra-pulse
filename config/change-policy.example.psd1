@{
    SchemaVersion = '1.0'

    # Critical and unknown results block the change by default.
    FailOn = @(
        'Critical'
        'Unknown'
    )

    # Warning budget after ignore rules are applied.
    MaximumWarnings = 0

    # Every populated field must match. Values use PowerShell wildcard syntax.
    Ignore = @(
        # @{
        #     ComputerName = 'lab-*'
        #     CheckName    = 'Uptime'
        #     Target       = '*'
        #     Status       = 'Warning'
        # }
    )
}
