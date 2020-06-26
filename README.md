# Introduction
The `New-WindowsGuestConfigPolicy.ps1` and `New-LinuxGuestConfigPolicy.ps1` script will walk you through the process of creating and publishing a custom Guest Configuration policy. I hope this guide helps you to better understand how all the Guest Configuration cmdlets can be used to create Custom Guest Configuration policies. Please follow the instructions in the script.

# Working with the end result - Windows Guest Config Policy
After executing the script line by line, you will have a Policy Initiative that contains the Deploy and Audit policy.

![](/Images/GuestConfigurationPolicyCreated.png)

If you assign the initiative, you will see the two parameters that you can specify. Tip: if you want to monitor multiple services, just change the assignment name into something like `[Initiative] Guest Configuration Demo - Audit Windows Service 'winrm'`.

![](/Images/GuestConfigurationParameters.png)

Make sure to select the remediation task. Otherwise the prerequisites won't be deployed.

![](/Images/GuestConfigurationRemediationTasks.png)

If you create a Virtual Machine and assign the policy (including the remediation task) to a Virtual Machine, it will look like this first:

![](/Images/GuestConfigurationStatus-Initial.png)

After a couple of minutes it will look like this:

![](/Images/GuestConfigurationStatus-Compliant.png)

If you logon on the Virtual Machine, you will see that a new log directory was created. If you open this log and search for "AuditWindowsService", you'll see why a resource is compliant or not. This status will also be reported back to Azure Guest Configuration so you can see it in the Azure Portal.

![](/Images/GuestConfigurationStatus-LogFiles.png)

You can also open the `gc_worker.log` file to see the DSC status results. Success:

![](/Images/GuestConfigurationStatus-SuccessLog.png)

If you want to see a policy failure, you can disable the service (in this case, the `winrm` service) by running the following PowerShell commands as administrator:

```` powershell
Get-Service winrm | Stop-Service
Get-Service winrm | Set-Service -StartupType Disabled
````

To quickly trigger the Azure Policy engine, you can create a tag on the VM and remove it so that the Azure Policy engine registers a change on the resource. Give it a couple of minutes and keep an eye on the `gc_worker.log` file again. It should report `"complianceStatus": false` soon.