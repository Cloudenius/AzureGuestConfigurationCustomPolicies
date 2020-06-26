# Define the configuration and import GuestConfiguration
Configuration AuditLinuxCronjob
{
    Import-DscResource -ModuleName 'GuestConfiguration'

    Node AuditLinuxCronjob
    {
        ChefInSpecResource 'Audit Cronjob exists'
        {
            Name = 'auditlinuxcronjob'
        }
    }
}

# Compile the configuration to create the MOF files
Import-Module PSDesiredStateConfiguration
AuditLinuxCronjob -OutputPath ./AuditLinuxCronjob/CompiledPolicy