## Minimum requirements
- Windows 10/11 or Server 2016 <=
- PowerShell 5.1 <=
- Scoop installed *ofc*

## Modifications that will happen to your system
1. **New directories**:
    - ``%USERPROFILE%\Documents\ScoopAutoUpdate`` (scheduled script's path) *(changeable)*
    - ``%USERPROFILE%\.scoop\logs`` (logs)
2. **New scheduled task**:
    - ``ScoopAutoUpdate``
        - By default it will run at **3:00 am daily** *(changeable)*
        - Runs on user level

## Monitoring

### Task Status
```powershell
Get-ScheduledTask -TaskName "ScoopAutoUpdate"
```

### Manual execution
```powershell
Start-ScheduledTask -TaskName "ScoopAutoUpdate"
```

---

### **Uninstallation**
```powershell
# Delete task
Unregister-ScheduledTask -TaskName "ScoopAutoUpdate" -Confirm:$false

#Delete script's folder
Remove-Item -Path "$env:USERPROFILE\Documents\ScoopAutoUpdate" -Recurse -Force

# OPTIONAL: Delete logs
Remove-Item -Path "$env:USERPROFILE\.scoop\logs" -Recurse -Force
```


###### *Disclaimer: This script for the exception of the readme file was written with Google's AI Studio. It's a script for my own personal use and I'm hosting it on GitHub for easier access and for people who might find it useful.*