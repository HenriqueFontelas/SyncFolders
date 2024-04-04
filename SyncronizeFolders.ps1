[CmdletBinding(DefaultParameterSetName="XMLFile")]
param
(
    [parameter(
        ParameterSetName="XMLFile")]
    [ValidateScript({Test-Path -LiteralPath $_ -PathType leaf})]
    [string]$ConfigurationFile=$PSScriptRoot+"\Sync-FolderConfiguration.xml",
    [parameter(
        Mandatory=$True,
        ValueFromPipelineByPropertyName=$True,
        ParameterSetName="FolderPair")]
    [string]$SourceFolder,
    [parameter(
        Mandatory=$True,
        ValueFromPipelineByPropertyName=$True,
        ParameterSetName="FolderPair")]
    [string[]]$TargetFolders,
    [parameter(
        ParameterSetName="FolderPair")]
    [string[]]$Exceptions=$Null,
    [parameter(
        ParameterSetName="FolderPair")]
    [string]$Filter="*",
    [ValidateScript({Test-Path -LiteralPath $_ -PathType leaf -IsValid})]
    [string]$LogFile=$PSScriptRoot+"\SyncFolderLog.txt",
    [int]$LoggingLevel=1,
    [switch]$LogToScreen=$false,
    [switch]$PassThru=$False,
    [switch]$Whatif=$False

)
set-strictmode -version Latest

function Write-Log
{
    [CmdletBinding()]
    param
    (
        [Parameter(
            ValueFromPipeline=$true)]
        [String]$Output="",
        [switch]$IsError=$False,  
        [switch]$IsWarning=$False,
        [switch]$Heading=$False,
        [switch]$Emphasis=$False,
        [switch]$WriteHost=$False,
        [switch]$NoFileWrite=$False,
        [switch]$IsInfo=$False
    )
    BEGIN
    {
        $TitleChar="*"
    }
    PROCESS
    {     
        if(($IsInfo -and $LoggingLevel -gt 0) -or $IsError -or $IsWarning)
        {       
            $FormattedOutput=@()
            if ($Heading)
            {
                $TitleBar=""
                #Builds a line for use in a banner
                for ($i=0;$i -lt ($Output.Length)+2; $i++)
                {
                    $TitleBar+=$TitleChar
                }
                $FormattedOutput=@($TitleBar,"$TitleChar$Output$TitleChar",$TitleBar,"")
            }elseif ($Emphasis)
            {
                $FormattedOutput+="","$TitleChar$Output$TitleChar",""
            }else
            {
                $FormattedOutput+=$Output
            }
            if ($IsError)
            {
                $PreviousFunction=(Get-PSCallStack)[1]
                $FormattedOutput+="Calling Function: $($PreviousFunction.Command) at line $($PreviousFunction.ScriptLineNumber)"
                $FormattedOutput=@($FormattedOutput | ForEach-Object {(Get-Date -Format HH:mm:ss.fff)+" : ERROR " + $_})
                $FormattedOutput | Write-Error
            }elseif ($IsWarning)
            {
                $FormattedOutput=@($FormattedOutput | ForEach-Object {(Get-Date -Format HH:mm:ss.fff)+" : WARNING " + $_})
                $FormattedOutput | Write-Warning            
            }else
            {
                $FormattedOutput=$FormattedOutput | ForEach-Object {(Get-Date -Format HH:mm:ss.fff)+" : " + $_}
                if ($WriteHost)
                {
                    $FormattedOutput | Write-Host
                }else
                {

                    $FormattedOutput | Write-Verbose
                }
            }
        
            if (!$NoFileWrite)
            {
                if (($Null -ne $Script:LogFileName) -and ($Script:LogFileName -ne ""))
                {
                    $FormattedOutput | Out-File -Append $Script:LogFileName
                }  

            }
        }
    }
    END
    {
    }
}

function Test-Exceptions
{
    param
    (
        [parameter(Mandatory=$True)]
        [ValidateScript({Test-Path -LiteralPath $_ -IsValid })]
        [string]$TestPath,
        [string[]]$PassedExceptions
    )
    $Result=$False
    $MatchingException=""
    if ($Null -eq $PassedExceptions)
    {
        Return $False
    }
    Write-Log "Checking $TestPath against exceptions" -IsInfo:($LoggingLevel -gt 1)
    foreach ($EnumeratedException in $PassedExceptions)
    {
        if($TestPath -like $EnumeratedException)
        {
            $Result=$True
            $MatchingException=$_          
        }
    }
    If ($Result)
    {
        Write-Log "Matched Exception : $MatchingException, skipping." -IsInfo -WriteHost:$LogToScreen
    }
    $Result
}

function New-ReportObject
{
    New-Object -typename PSObject| Add-Member NoteProperty "Successful" $False -PassThru |
    Add-Member NoteProperty "Process" "" -PassThru |
    Add-Member NoteProperty "Message" "" -PassThru    
}

function Get-PropertyExists
{
    param
    (
        [PSObject]$Queryobject,
        [string]$PropertyName
    )
    Return (($Queryobject | Get-Member -MemberType Property | Select-Object -ExpandProperty Name) -contains $PropertyName)
}

function Sync-OneFolder
{
    param
    (
        [parameter(Mandatory=$True)]
        [ValidateScript({Test-Path -LiteralPath $_ -PathType Container})]
        [string]$SourceFolder,
        [parameter(Mandatory=$True)]
        [ValidateScript({Test-Path -LiteralPath $_ -IsValid })]
        [string[]]$TargetFolders,
        [string[]]$PassedExceptions,
        [string]$Filter="*",
        [switch]$WhatIf=$False
 
    )
    Write-Log "Source Folder : $SourceFolder" -IsInfo:($LoggingLevel -gt 1) -WriteHost:$LogToScreen
    Write-Log "Target Folder : $TargetFolders" -IsInfo:($LoggingLevel -gt 1) -WriteHost:$LogToScreen
    Write-Log "Filter : $Filter" -IsInfo:($LoggingLevel -gt 1) -WriteHost:$LogToScreen
    if ($null -ne $PassedExceptions)
    {
        Write-Log "Exceptions:" -IsInfo:($LoggingLevel -gt 1) -WriteHost:$LogToScreen 
        $PassedExceptions | ForEach-Object{Write-Log $_ -IsInfo:($LoggingLevel -gt 1) -WriteHost:$LogToScreen}
    }
    Foreach ($TargetFolder in $TargetFolders)
    {
        Write-Log "Checking For Folders to Create" -IsInfo:($LoggingLevel -gt 1) -WriteHost:$LogToScreen
        if (!(Test-Path -LiteralPath $TargetFolder -PathType Container))
        {
            $Output=New-ReportObject
            Write-Log "Creating Folder : $($TargetFolder)" -IsInfo -WriteHost:$LogToScreen
            $Output.Process="Create Folder"
            try
            {
                $Output.Message="Adding folder missing from Target : $TargetFolder"
                Write-Log $Output.Message -IsInfo -WriteHost:$LogToScreen
                New-Item $TargetFolder -ItemType "Directory" -WhatIf:$WhatIf > $null
                $Output.Successful=$True
            }
            catch
            {
                $Output.Message="Error adding folder $TargetFolder)"
                Write-Log $Output.Message -IsError -WriteHost:$LogToScreen
                Write-Log $_ -IsError
            }
            $Output
        }
        Write-Log "Getting File Lists" -IsInfo:($LoggingLevel -gt 1) -WriteHost:$LogToScreen
        $FilteredSourceFiles=$FilteredTargetFiles=$TargetList=@()
        $FilteredSourceFolders=$FilteredTargetFolders=@()
        try
        {
            $SourceList=Get-ChildItem -LiteralPath $SourceFolder -Attributes !ReparsePoint
        }
        catch
        {
            Write-Log "Error accessing $SourceFolder" -IsError
            Write-Log $_ -IsError
            $SourceList=@()
        }
        try
        {
            $TargetList=Get-ChildItem -LiteralPath $TargetFolder -Attributes !ReparsePoint
        }
        catch
        {
            Write-Log "Error accessing $TargetFolder" -IsError
            Write-Log $_ -IsError
            $SourceList=@()
        }
        $FilteredSourceFiles+=$SourceList | Where-Object {$_.PSIsContainer -eq $False -and $_.FullName -like $Filter -and
            !(Test-Exceptions $_.FullName $PassedExceptions)}
        $FilteredTargetFiles+=$TargetList | Where-Object {$_.PSIsContainer -eq $False -and $_.FullName -like $Filter -and
            !(Test-Exceptions $_.FullName $PassedExceptions)}
        $FilteredSourceFolders+=$SourceList | Where-Object {$_.PSIsContainer -eq $True -and !(Test-Exceptions $_.FullName $PassedExceptions)}
        $FilteredTargetFolders+=$TargetList | Where-Object {$_.PSIsContainer -eq $True -and !(Test-Exceptions $_.FullName $PassedExceptions)}
        $MissingFiles=@(Compare-Object $FilteredSourceFiles $FilteredTargetFiles -Property Name)
        $MissingFolders=@(Compare-Object $FilteredSourceFolders $FilteredTargetFolders -Property Name)
        Write-Log "Comparing Missing File Lists" -IsInfo:($LoggingLevel -gt 1) -WriteHost:$LogToScreen
        foreach ($MissingFile in $MissingFiles)
        {
            $Output=New-ReportObject
            if($MissingFile.SideIndicator -eq "<=")
            {
                $Output.Process="Copy File"
                try
                {          
                    $Output.Message="Copying missing file : $($TargetFolder+"\"+$MissingFile.Name)" 
                    Write-Log $Output.Message -IsInfo -WriteHost:$LogToScreen
                    Copy-Item -LiteralPath ($SourceFolder+"\"+$MissingFile.Name) -Destination ($TargetFolder+"\"+$MissingFile.Name) -WhatIf:$WhatIf
                    $Output.Successful=$True
                }
                catch
                {
                    $Output.Message="Error copying missing file $($TargetFolder+"\"+$MissingFile.Name)"
                    Write-Log $Output.Message -IsError -WriteHost:$LogToScreen
                    Write-Log $_ -IsError -WriteHost:$LogToScreen
                }
            }elseif ($MissingFile.SideIndicator="=>")
            {
                $Output.Process="Remove File"
                try
                {
                    $Output.Message="Removing file missing from Source : $($TargetFolder+"\"+$MissingFile.Name)"
                    Write-Log $Output.Message -IsInfo -WriteHost:$LogToScreen
                    Remove-Item -LiteralPath ($TargetFolder+"\"+$MissingFile.Name) -WhatIf:$WhatIf
                    $Output.Successful=$True
                }
                catch
                {
                    $Output.Message="Error removing file $($TargetFolder+"\"+$MissingFile.Name)"
                    Write-Log $Output.Message -IsError -WriteHost:$LogToScreen
                    Write-Log $_ -IsError -WriteHost:$LogToScreen
                }           
            }
            $Output
         
        }
        Write-Log "Comparing Missing Folder Lists" -IsInfo:($LoggingLevel -gt 1) -WriteHost:$LogToScreen
        foreach ($MissingFolder in $MissingFolders)
        {        
            if ($MissingFolder.SideIndicator -eq "=>")
            {
                $Output=New-ReportObject
                $Output.Process="Remove Folder"
                try
                {
                    $Output.Message="Removing folder missing from Source : $($TargetFolder+"\"+$MissingFolder.Name)"
                    Write-Log $Output.Message -IsInfo -WriteHost:$LogToScreen
                    Remove-Item -LiteralPath ($TargetFolder+"\"+$MissingFolder.Name) -Recurse -WhatIf:$WhatIf
                    $Output.Successful=$True
                }
                catch
                {
                    $Output.Message="Error removing folder $($TargetFolder+"\"+$MissingFolder.Name)"
                    Write-Log $Output.Message -IsError -WriteHost:$LogToScreen
                    Write-Log $_ -IsError -WriteHost:$LogToScreen
                }
                $Output
            }   
        }
        Write-Log "Copying Changed Files : $($FilteredTargetFiles.Count) to check" -IsInfo:($LoggingLevel -gt 1) -WriteHost:$LogToScreen
        ForEach ($TargetFile in $FilteredTargetFiles)
        {
            Write-Log "Getting Matching Files for $($TargetFile.Name)" -IsInfo:($LoggingLevel -gt 1) -WriteHost:$LogToScreen
            $MatchingSourceFile= $FilteredSourceFiles | Where-Object {$_.Name -eq $TargetFile.Name}
            If ($null -ne $MatchingSourceFile)
            {
                If ($MatchingSourceFile.LastWriteTime -gt $TargetFile.LastWriteTime)
                {
                    $Output=New-ReportObject
                    $Output.Process="Update File"
                    try
                    {
                        $Output.Message="Copying updated file : $($TargetFolder+"\"+$MatchingSourceFile.Name)" 
                        Write-Log $Output.Message -IsInfo -WriteHost:$LogToScreen
                        Copy-Item -LiteralPath ($SourceFolder+"\"+$MatchingSourceFile.Name) -Destination ($TargetFolder+"\"+$MatchingSourceFile.Name) -Force -WhatIf:$WhatIf
                        $Output.Successful=$True
                    }
                    catch
                    {
                        $Output.Message="Error copying updated file $($TargetFolder+"\"+$MatchingSourceFile.Name)"
                        Write-Log $Output.Message -IsError -WriteHost:$LogToScreen
                        Write-Log $_ -IsError -WriteHost:$LogToScreen
                    }
                    $Output
                }

            }      
        }
        Write-Log "Comparing Sub-Folders" -IsInfo:($LoggingLevel -gt 1) -WriteHost:$LogToScreen
        foreach($SingleFolder in $FilteredSourceFolders)
        {
            Sync-OneFolder -SourceFolder $SingleFolder.FullName -TargetFolder ($TargetFolder+"\"+$SingleFolder.Name) -PassedExceptions $PassedExceptions -Filter $Filter -WhatIf:$WhatIf #
        }
    }
}

<#Main Program Loop#>

#$Script:WriteInfo=-not $LogWarningsAndErrorsOnly
#Add a timestamp to the logfile
#Split off the suffix first
[string[]]$FileNameSplit=$LogFile.Split(".")
$Suffix=".txt"
if($FileNameSplit.Count -gt 1)
{
    $Suffix="."+$FileNameSplit[$FileNameSplit.Count-1]
}
$Script:LogFileName=$LogFile.Split(".")[0] + "-"+[string](Get-Date -Format "yyyy-MM-dd-HH-mm")
$LogFileNameCount=0
#Check the logfilename is unique, if not add a number from 1 to 9 to it
While($LogFileNameCount -lt 8 -and (Test-Path -LiteralPath ($Script:LogFileName+$Suffix) -PathType Leaf))
{
    $LogFileNameCount+=1;
    $Script:LogFileName=$LogFile.Split(".")[0] + "-"+[string](Get-Date -Format "yyyy-MM-dd-HH-mm")+"-"+[string]$LogFileNameCount
}
$Script:LogFileName+=$Suffix
#If the LogFileName is STILL not unique throw and error
if(Test-Path -LiteralPath $Script:LogFileName -PathType Leaf)
{
    Write-Log -IsError "Unable to create a unique LogFileName" 
}else
{
    Write-Log ("LogFile: " + $Script:LogFileName) -NoFileWrite -WriteHost -IsInfo
}


$ResultObjects=$Changes=$CurrentExceptions=@()
$CurrentFilter="*"
Write-Log "Running Sync-Folder Script" -NoFileWrite -IsInfo
If ($WhatIf)
{
    Write-Host "WhatIf Switch specified;  no changes will be made."
}
if ($PSBoundParameters.ContainsKey("SourceFolder"))
{
    Write-Log "Syncing folder pair passed as parameters." -IsInfo -WriteHost:$LogToScreen
    foreach ($TargetFolder in $TargetFolders)
    {
        $ResultObjects=Sync-OneFolder -SourceFolder $SourceFolder -TargetFolder $TargetFolder -PassedExceptions $Exceptions -Filter $Filter -WhatIf:$WhatIf | 
    Tee-Object -Variable Changes
    }
}else
{
    Write-Log "Running with Configuration File : $ConfigurationFile" -IsInfo
    $Config=[xml](Get-Content $ConfigurationFile)
    $FolderChanges=$Null
    foreach ($Pair in $Config.Configuration.SyncPair)
    {
        Write-Log "Processing Pair $($Pair.Source) $($Pair.Target)" -IsInfo -WriteHost:$LogToScreen
        $CurrentExceptions=$Null
        If(Get-PropertyExists -Queryobject $Pair -PropertyName ExceptionList)
        {
            $CurrentExceptions=@($Pair.ExceptionList.Exception)
        }
        If(Get-PropertyExists -Queryobject $Pair -PropertyName Filter)
        {
            if (($null -ne $Pair.Filter) -and ($Pair.Filter -ne ""))
            {
                $CurrentFilter=$Pair.Filter
            }
        }   
        foreach($Target in $Pair.Target)
        {
                $ResultObjects=Sync-OneFolder -SourceFolder $Pair.Source -TargetFolder $Target -PassedExceptions $CurrentExceptions -Filter $CurrentFilter -WhatIf:$WhatIf |
        Tee-Object -Variable FolderChanges  
        }

        if($FolderChanges -ne $Null)    
        {
            $Changes+=$FolderChanges
        }    
    }
    
}
$FolderCreations=$FileCopies=$FileRemovals=$FolderRemovals=$FileUpdates=0
Foreach ($Change in $Changes)
{
    switch ($Change.Process)
    {
        "Create Folder"
        {
            $FolderCreations+=1
        }
        "Copy File"
        {
            $FileCopies+=1
        }
        "Remove File"
        {
            $FileRemovals+=1
        }
        "Remove Folder"
        {
            $FolderRemovals+=1
        }
        "Update File"
        {
            $FileUpdates+=1
        }
    }
}
Write-Log "" -WriteHost -IsInfo
Write-Log "Statistics" -WriteHost -IsInfo
Write-Log "" -WriteHost -IsInfo
Write-Log "Folder Creations: `t$FolderCreations" -WriteHost -IsInfo
Write-Log "Folder Removals: `t$FolderRemovals" -WriteHost -IsInfo
Write-Log "File Copies: `t`t$FileCopies" -WriteHost -IsInfo
Write-Log "File Removals: `t`t$FileRemovals" -WriteHost -IsInfo
Write-Log "File Updates: `t`t$FileUpdates`n" -WriteHost -IsInfo
If ($PassThru)
{
    $ResultObjects
}