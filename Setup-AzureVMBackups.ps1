# This sets up Azure VM backups and SQL inside an Azure VM DB level backups.
# Andy Roberts - andyr8939@gmail.com

# Set Account Specific Variables here
########################################################################################
## Connection Details
$mySubscription = "123456789-1234-1234-1234-123456789"
$myLocation = "australiaeast"
$myClient = "myclient"
$myEnvironment = "test"
$myRSG = "$myEnvironment-$myLocation-$myClient"
$myBackupVaultName = "$myEnvironment-$myLocation-$myClient-backup-vault"
$myBackupTime = Get-Date -Date "2021-02-1 22:00:00Z" # This gets converted to UTC for local 1am
########################################################################################
# Set your Global Details Here
$myBackupPolicyName = "MyBackupPolicy"
$mySQLBackupPolicyName = "MySQLBackupPolicy"

# VM Backup Cycle
$DailyBackupCount = 7
$WeeklyBackupCount = 4
$MonthlyBackupCount = 12
$YearlyBackupCount = 2
$MonthlyDayOfWeek = "Sunday"
$MonthlyWeek = "Last"
$YearlyMonth = "January"

# SQL in VM Specific Cycle
$sqlFullBackupFrequency = "Weekly"
$sqlFullBackupFrequencyDay = "Sunday"
$sqlFullBackupWeekOfMonth = "First"
$sqlWeeklyCount = "4"
$sqlMonthlyCount = "12"
$sqlYearlyCount = "2"
$sqlYearlyMonth = "January"

$sqlDifferentialEnabled = "True"
$sqlLogBackupEnabled = "True"
$sqlLogRetentionCycle = "Days"
$sqlLogRetentionCount = "7"
$sqlLogBackupFrequencyMins = "120" # Take Log Backup every 2 hours

########################################################################################

# Set Azure Context
Set-AzContext -SubscriptionId $mySubscription

# Get a list of all VMs in the Resource Group
$VMs = Get-AzVm -ResourceGroupName $myRSG

# Register Recovery Services Providor
Register-AzResourceProvider -ProviderNamespace "Microsoft.RecoveryServices"

# Create Backup RecoveryServices Vault - This is different to the replication Vault as needs to be in the same region as the VMs
New-AzRecoveryServicesVault -Name $myBackupVaultName -ResourceGroupName $myRSG -Location $myLocation
$backup_vault = Get-AzRecoveryServicesVault -Name $myBackupVaultName -ResourceGroupName $myRSG

# Set vault redundancy
Set-AzRecoveryServicesBackupProperty -Vault $backup_vault -BackupStorageRedundancy GeoRedundant

# Set vault context
Get-AzRecoveryServicesVault -Name $myBackupVaultName -ResourceGroupName $myRSG | Set-AzRecoveryServicesVaultContext

# Get vault ID
$targetVault = Get-AzRecoveryServicesVault -ResourceGroupName $myRSG -Name $myBackupVaultName

# Set Values for the Protection Policy
$myBackupPolicyName = $myBackupPolicyName
$schPol = Get-AzRecoveryServicesBackupSchedulePolicyObject -WorkloadType "AzureVM"
$UtcTime = $myBackupTime.ToUniversalTime()
$schpol.ScheduleRunTimes[0] = $UtcTime

# Create the Protection Policy
$retPol = Get-AzRecoveryServicesBackupRetentionPolicyObject -WorkloadType "AzureVM"
New-AzRecoveryServicesBackupProtectionPolicy -Name $myBackupPolicyName -WorkloadType "AzureVM" -RetentionPolicy $retPol -SchedulePolicy $schPol

# Modify protection policy now its in place
$retPol.DailySchedule.DurationCountInDays = $DailyBackupCount
$retPol.WeeklySchedule.DurationCountInWeeks = $WeeklyBackupCount
$retPol.MonthlySchedule.DurationCountInMonths = $MonthlyBackupCount
$retPol.MonthlySchedule.RetentionScheduleWeekly.DaysOfTheWeek = $MonthlyDayOfWeek
$retPol.MonthlySchedule.RetentionScheduleWeekly.WeeksOfTheMonth = $MonthlyWeek
$retPol.YearlySchedule.DurationCountInYears = $YearlyBackupCount
$retPol.YearlySchedule.MonthsOfYear = $YearlyMonth
$pol = Get-AzRecoveryServicesBackupProtectionPolicy -Name $myBackupPolicyName
Set-AzRecoveryServicesBackupProtectionPolicy -RetentionPolicy $RetPol -Policy $pol -SchedulePolicy $schPol

# Enable Protection for each VM
foreach ($vm in $VMs) {
    $pol = Get-AzRecoveryServicesBackupProtectionPolicy -Name $myBackupPolicyName
    Enable-AzRecoveryServicesBackupProtection -Policy $pol -Name $vm.Name -ResourceGroupName $myRSG
}

# Azure Backup for SQL VMs
# https://docs.microsoft.com/en-us/azure/backup/backup-azure-sql-automation
# Set Values for the SQL Protection Policy
$sqlschPol = Get-AzRecoveryServicesBackupSchedulePolicyObject -WorkloadType "MSSQL"
$sqlretPol = Get-AzRecoveryServicesBackupRetentionPolicyObject -WorkloadType "MSSQL"
$SQLmyBackupTime = ($myBackupTime).AddHours(3) # Set to 3hr after the backup job time
$sqlUtcTime = $SQLmyBackupTime.ToUniversalTime()
$sqlschpol.FullBackupSchedulePolicy.ScheduleRunTimes[0] = $sqlUtcTime
$sqlschpol.DifferentialBackupSchedulePolicy.ScheduleRunTimes[0] = $sqlUtcTime
$sqlschpol.IsCompression = $NULL
$sqlschpol.FullBackupSchedulePolicy.ScheduleRunFrequency = $sqlFullBackupFrequency
$sqlschpol.FullBackupSchedulePolicy.ScheduleRunDays = $sqlFullBackupFrequencyDay
$sqlschpol.FullBackupSchedulePolicy.ScheduleRunTimes[0] = $sqlUtcTime
$sqlretPol.FullBackupRetentionPolicy.IsDailyScheduleEnabled = $NULL # This has to be null, not false like the other scheduleenabled ones! Goodbye 2hrs figuring that out!
$sqlretPol.FullBackupRetentionPolicy.DailySchedule = $NULL
$sqlretPol.FullBackupRetentionPolicy.WeeklySchedule.DurationCountInWeeks = $sqlWeeklyCount
$sqlretPol.FullBackupRetentionPolicy.WeeklySchedule.DaysOfTheWeek = $sqlFullBackupFrequencyDay
$sqlretPol.FullBackupRetentionPolicy.MonthlySchedule.DurationCountInMonths = $sqlMonthlyCount
$sqlretPol.FullBackupRetentionPolicy.MonthlySchedule.RetentionScheduleFormatType = $sqlFullBackupFrequency
$sqlretPol.FullBackupRetentionPolicy.MonthlySchedule.RetentionScheduleDaily = $NULL
$sqlretPol.FullBackupRetentionPolicy.MonthlySchedule.RetentionScheduleWeekly.DaysOfTheWeek = $sqlFullBackupFrequencyDay
$sqlretPol.FullBackupRetentionPolicy.MonthlySchedule.RetentionScheduleWeekly.WeeksOfTheMonth = $sqlFullBackupWeekOfMonth
$sqlretPol.FullBackupRetentionPolicy.YearlySchedule.DurationCountInYears = $sqlYearlyCount
$sqlretPol.FullBackupRetentionPolicy.YearlySchedule.RetentionScheduleFormatType = $sqlFullBackupFrequency
$sqlretPol.FullBackupRetentionPolicy.YearlySchedule.RetentionScheduleWeekly.DaysOfTheWeek = $sqlFullBackupFrequencyDay
$sqlretPol.FullBackupRetentionPolicy.YearlySchedule.RetentionScheduleWeekly.WeeksOfTheMonth = $sqlFullBackupWeekOfMonth
$sqlretPol.FullBackupRetentionPolicy.YearlySchedule.MonthsOfYear = $sqlYearlyMonth
$sqlschPol.IsDifferentialBackupEnabled = $sqlDifferentialEnabled
$sqlschpol.DifferentialBackupSchedulePolicy.ScheduleRunFrequency = $sqlFullBackupFrequency
$sqlschpol.DifferentialBackupSchedulePolicy.ScheduleRunDays = "Monday"
$sqlschpol.DifferentialBackupSchedulePolicy.ScheduleRunDays += "Tuesday"
$sqlschpol.DifferentialBackupSchedulePolicy.ScheduleRunDays += "Wednesday"
$sqlschpol.DifferentialBackupSchedulePolicy.ScheduleRunDays += "Thursday"
$sqlschpol.DifferentialBackupSchedulePolicy.ScheduleRunDays += "Friday"
$sqlschpol.DifferentialBackupSchedulePolicy.ScheduleRunDays += "Saturday"
$sqlschpol.DifferentialBackupSchedulePolicy.ScheduleRunTimes[0] = $sqlUtcTime
$sqlretPol.DifferentialBackupRetentionPolicy.RetentionDurationType = "Days"
$sqlretPol.DifferentialBackupRetentionPolicy.RetentionCount = "7"
$sqlschpol.IsLogBackupEnabled = $sqlLogBackupEnabled
$sqlschpol.LogBackupSchedulePolicy.ScheduleFrequencyInMins = $sqlLogBackupFrequencyMins
$sqlretPol.LogBackupRetentionPolicy.RetentionCount = $sqlLogRetentionCount
$sqlretPol.LogBackupRetentionPolicy.RetentionDurationType = $sqlLogRetentionCycle

# Create the SQL Backup Job
$NewSQLPolicy = New-AzRecoveryServicesBackupProtectionPolicy -Name $mySQLBackupPolicyName -WorkloadType "MSSQL" -RetentionPolicy $sqlretPol -SchedulePolicy $sqlschPol -Verbose

# Get SQL VMs
$sqlvms = Get-AzVM -ResourceGroupName $myRSG -Name *sql*

# Register VMs with SQL on against the backup container
# And Disable SQL IaaS backup extension otherwise it causes conflicts
# Create a null auto backup config to disable IaaS backup
$autobackupconfig = New-AzVMSqlServerAutoBackupConfig -ResourceGroupName $myRSG

# This takes about 5 mins per VM
foreach ($vm in $sqlvms) {
    Register-AzRecoveryServicesBackupContainer -ResourceId $vm.ID -BackupManagementType AzureWorkload -WorkloadType MSSQL -VaultId $targetVault.ID -Force
    Set-AzVMSqlServerExtension -AutoBackupSettings $autobackupconfig -VMName $vm.Name -ResourceGroupName $myRSG -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
}

# Get all protectable SQL DBs found in the vault that can be backed up
$SQLDB = Get-AzRecoveryServicesBackupProtectableItem -WorkloadType MSSQL -VaultId $targetVault.ID

# Enable backups on all DBs not already set to backup
foreach ($db in $SQLDB) {
    Enable-AzRecoveryServicesBackupProtection -ProtectableItem $db -Policy $NewSQLPolicy
}

# Now enable auto protection for all future DBs
# Get the SQL Instance Items
$SQLInstance = Get-AzRecoveryServicesBackupProtectableItem -workloadType MSSQL -ItemType SQLInstance -VaultId $targetVault.ID

# Set Auto Protect for each Instance
# This is then auto executed as a background task every 8hrs
foreach ($instance in $SQLInstance) {
    Enable-AzRecoveryServicesBackupAutoProtection -InputItem $instance -BackupManagementType AzureWorkload -WorkloadType MSSQL -Policy $NewSQLPolicy -VaultId $targetvault.ID
}
