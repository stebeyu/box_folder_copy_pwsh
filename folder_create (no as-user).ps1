######Pre-Requisites
#Must have Box CLI configured and pointed to correct Box environment
#Must have PowerShell configured
#Must have input.csv properly configured

# File system variables
$BaseFilePath = "/Users/steveyu/PowerShell/input.csv" #Enter path to input.csv here
$Timing = Get-Date -Format "dddd MM dd yyyy HHmm"
$OutputFile = ".\folder_creation_log $Timing.csv" 
Add-content -path $OutputFile -value "Row,ID,ParentID,Name,Status,Message"

#Script execution variables
$timeoutLength = 90 #adjust if needed to avoid 409 operation_blocked_temporary errors

################################# SCRIPT LOGIC DO NOT ALTER BELOW #################################

$folderCreateInput = Import-Csv -path $BaseFilePath
$row = 1

ForEach ($Folder in $folderCreateInput) {
    $row++
    $FolderID = $Folder.ID
    $FolderParent = $Folder.PARENTID
    $FolderName = $Folder.NAME
    $error.clear()
    $createFolder=$null 
    $errorReceived=$null

    Write-Host "Attempting copy for $FolderID into $FolderParent with name $FolderName"

    #silence error-stream output to file using $null because using errorVariable to handle command errors
    $createFolder = Invoke-Expression "box folders:copy $FolderID $FolderParent --name $FolderName --json" -ErrorVariable errorReceived 2>$null

    #------------------------------------Error Handling Logic below------------------------------------
    #Didn't use try/catch because using invoke-expression requires you to manually parse the command exit code/response anyway
    
    if($errorReceived){
        $errorMessage = $errorReceived[0] | Out-String

        #if the source/template folder is in use, sleep for $timeoutLength and retry
        if ($errorMessage.Contains('operation_blocked_temporary')){
                Write-Host "Row $row error received: [409 Conflict] operation_blocked_temporary - The operation is blocked by another on-going operation" -Fore Yellow -NoNewline
                Write-Host " | Waiting and retrying..." -Fore Yellow

                $retryResult = $null
                $retryErrorMessage=$null
                Start-Sleep -s $timeoutLength
                $retryResult = Invoke-Expression "box folders:copy $FolderID $FolderParent --name $FolderName --json" -ErrorVariable retryErrorMessage 2>$null
            
                if($retryErrorMessage){
                    Write-Host "Retry Error: $retryErrorMessage"
                    Write-Host "Row $row error received: Copy failed on retry for item $FolderID - please review logs and retry later `n" -Fore Red
                    Add-content -path $OutputFile -value "$row,$FolderID,$FolderParent,$FolderName,failed,$retryErrorMessage"
                    }
                    
                elseif ($retryResult){
                    $resultRetry = $retryResult | ConvertFrom-Json
                    $newFolderIDRetry = $resultRetry."id"
                    $newFolderTypeRetry = $resultRetry."type"
                    $newFolderNameRetry = $resultRetry."name"
                    $newFolderParentRetry = $resultRetry."parent"."id"
                    $newFolderTimeRetry = $resultRetry."content_created_at"
                    Write-Host "Row $row copy successful on retry - created new created new $newFolderTypeRetry ""$newFolderNameRetry"" with ID $newFolderIDRetry at $newFolderTimeRetry in parent folder $newFolderParentRetry `n" -Fore Green
                    Add-content -path $OutputFile -value "$row,$newFolderIDRetry,$newFolderParentRetry,$newFolderNameRetry,success,"
                }
                else{
                    Write-Host "Row $row error received: Copy failed on retry for item $FolderID - please review logs and retry later `n" -Fore Red
                    Add-content -path $OutputFile -value "$row,$FolderID,$FolderParent,$FolderName,failed,"
                }
            }
        
        elseif($errorMessage.Contains('item_name_in_use')){
            Write-Host "Row $row error received: [409 Conflict] item_name_in_use - Item with the same name already exists" -Fore Red -NoNewline
            Write-Host " | Action: check target/parent for duplicate items with same name `n" -Fore Red
            Add-content -path $OutputFile -value "$row,$FolderID,$FolderParent,$FolderName,failed,$errorReceived"
        }
        
        elseif($errorMessage.Contains('not_found')){
            Write-Host "Row $row error received:[404 Not Found] not_found - Not Found | Action: check item IDs for items in row $row `n" -Fore Red
            Add-content -path $OutputFile -value "$row,$FolderID,$FolderParent,$FolderName,failed,$errorReceived"
        }

        elseif($errorMessage.Contains('access_denied_insufficient_permissions')){
            Write-Host "Row $row error received: [403 Forbidden] access_denied_insufficient_permissions - Access denied - insufficient permission" -Fore Red -NoNewline
            Write-Host " | Action: check that user account has access to target ID `n" -Fore Red
            Add-content -path $OutputFile -value "$row,$FolderID,$FolderParent,$FolderName,failed,$errorReceived"
        }

        else{
            Write-Host "Row $row error received: $errorReceived | Action: check Box CLI docs for more information about error messages `n" -Fore Red
            Add-content -path $OutputFile -value "$row,$FolderID,$FolderParent,$FolderName,failed,$errorReceived"
        }

    }

    elseif ($createFolder){
        $result = $createFolder | ConvertFrom-Json
        $newFolderID = $result."id"
        $newFolderType = $result."type"
        $newFolderName = $result."name"
        $newFolderParent = $result."parent"."id"
        $newFolderTime = $result."content_created_at"
        Write-Host "Row $row copy successful - created new $newFolderType ""$newFolderName"" with ID $newFolderID at $newFolderTime in parent folder $newFolderParent `n" -ForegroundColor Green
        Add-content -path $OutputFile -value "$row,$newFolderID,$newFolderParent,$newFolderName,success,"
    }

    else {
        Write-Host "Row $row error: failed to write | Action: please try again later `n" -Fore Red
        Add-content -path $OutputFile -value "$row,$FolderID,$FolderParent,$FolderName,failed,$errorReceived"
    }

}