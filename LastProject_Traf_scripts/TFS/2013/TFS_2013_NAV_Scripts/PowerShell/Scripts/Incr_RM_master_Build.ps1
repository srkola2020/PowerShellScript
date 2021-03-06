#####################################################################################
#																				   	#
# Description: PowerShell Script to create incremental build for Navision Code	 	#
#																				   	#
# Author: Khushwant Singh														#
#																					#				
#####################################################################################

echo "Get the CheckOut Version ${Env:TF_BUILD_SOURCEGETVERSION}"

$scriptName = $MyInvocation.MyCommand.Name
$PSScriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
$scriptPath = $PSScriptRoot

function Valfromconfig()
{   
[CmdletBinding()]
    param 
    (
        [String]$variable        
    )            
$string = $(Get-Content "$scriptPath\..\Config\Configuration.txt" | Select-String $variable).ToString().split("=")[1]
return $string
}

Function Get-NAVObjectTypeIdFromName( [String]$TypeName)
{
     switch ($TypeName)
    {
        "TableData" {$Type = 0}
        "Table" {$Type = 1}
        "Page" {$Type = 8}
        "Codeunit" {$Type = 5}
        "Report" {$Type = 3}
        "XMLPort" {$Type = 6}
        "Query" {$Type = 9}
        "MenuSuite" {$Type = 7}
    }
    Return $Type
}

$TfPath=Valfromconfig 'TFS Folder Path'
$NAVFolder=Valfromconfig 'RTC Client Path'
$env:PATH += ";${TfPath};${NAVFolder}"
$BldChngSetFolder="C:\ePuma_Prod\Build-Changeset"
$BldChngSetFlFolder="$scriptPath\..\Build-ChangesetFiles"
$BldDrop="${Env:TF_BUILD_DROPLOCATION}"
$LogFolder="$scriptPath\..\Build-Logs"
$deployErrLogFile="C:\Scripts\Import_Log\Error.txt"
$NavisionCodeLocation="$scriptPath\..\..\NavWorkspace"
$SuccessVerFile="$BldChngSetFolder\SuccessVersionIncrMaster.txt"
$versionlist="${Env:TF_BUILD_BUILDNUMBER}"
$BuildChngSetInfoFl="${BldDrop}\${versionlist}_ChangeSet.txt"
$BldDateFolder="${BldDrop}\${versionlist}"
$fobbuildfile="${BldDrop}\${versionlist}\$versionlist.fob"
$rmfobfile="${BldDrop}\RM.fob"
$deployscript="${scriptPath}\rm_deploy.ps1"
$FinalLatestFob="${BldDrop}\..\..\LatestFob\Latest.fob"

$md5File="${BldDrop}\${versionlist}\md5_${versionlist}.txt"
$Server=Valfromconfig 'Dev_DBServer'
$Database=Valfromconfig 'Dev_Database'
$navSrvPath=Valfromconfig 'serverWorkSpacePath'
$tfsCollection=Valfromconfig 'tfsCollectionURL'
Write-Host "The script name is $scriptName" -ForegroundColor Yellow
Write-Host "The script path is $scriptPath" -ForegroundColor Yellow
Write-Host "`n#####Script ${scriptName} Started#####`n"	-ForegroundColor Yellow
Write-Host "LogFolder is ${LogFolder}`n" -ForegroundColor Yellow
Write-Host "NavisionCodeLocation is ${NavisionCodeLocation}`n" -ForegroundColor Yellow

if (!(Test-Path -Path $BldDrop ))
	{
		echo "Directory $BldDrop does Not Exists"
		New-Item -ItemType directory -Path $BldDrop
		echo "Created Directory $BldDrop"
	}

echo $null > $BuildChngSetInfoFl

Set-Location -Path "${NavisionCodeLocation}"

if(!(Test-Path -Path $LogFolder ))
	{
		echo "Directory $LogFolder does Not Exists"
		New-Item -ItemType directory -Path $LogFolder
		echo "Created Directory $LogFolder"
	}
else 
	{
		Remove-Item "$LogFolder\*.txt" -Force
	}
	
if (!(Test-Path -Path $BldChngSetFolder ))
	{
		echo "Directory $BldChngSetFolder does Not Exists"
		New-Item -ItemType directory -Path $BldChngSetFolder
		echo "Created Directory $BldChngSetFolder"
	}

if (!(Test-Path -Path $BldChngSetFlFolder ))
	{
		echo "Directory $BldChngSetFolder does Not Exists"
		New-Item -ItemType directory -Path $BldChngSetFlFolder
		echo "Created Directory $BldChngSetFlFolder"
	}
else
	{
		Remove-Item "$BldChngSetFlFolder\*.txt" -Force
	}

if (!(Test-Path -Path $SuccessVerFile))
	{
		
		Write-Host "Creating new Success Version File" -ForegroundColor Yellow
		$chArr=tf history . /r /noprompt |% {if ($_ -match "^\d+") {echo $matches[0]}}
		$chArr=[array]$chArr
		$chArr=$chArr | sort {[int]$_}
		$chArr=[array]$chArr
		$versionNum=$chArr[0]
		echo $versionNum > $SuccessVerFile
		$LatestChSet=$chArr[$chArr.Length-1]
		$dayZero="T"
		Write-Host "Build Version Considered: $versionNum" -ForegroundColor Yellow
	}
else 
	{
		$dayZero="F"
		$versionNumCheck=$(cat $SuccessVerFile).trim()
		$versionNumCheck = [array]$versionNumCheck
		if	( $versionNumCheck.Length -ne 1 )
			{
				Write-Host "The number of entries\lines in file $SuccessVerFile is zero or more than one.Please check the file" -ForegroundColor Red
				Write-Host "Exiting" -ForegroundColor Red
				exit 1
			}	
		else
			{
				if	($versionNumCheck[0] -match "^\d+$")
					{
						$versionNum=$versionNumCheck[0]
					}
				else
					{
						Write-Host "The Changeset : $($versionNum[0]) in the file $SuccessVerFile is not correct" -ForegroundColor Red
						Write-Host "Exiting" -ForegroundColor Red
						exit 1
					}
			}
		Write-Host "`nLast Success Build Version : $versionNum" -ForegroundColor Yellow		
	}

Write-Host "Version list of the current build : ${versionlist}" -ForegroundColor Yellow		
Write-Host "Fetching latest changesets from Version Control for Navision Code" -ForegroundColor Yellow	

if ($dayZero -eq "F")
	{
		[array]$LatestchArr = tf history . /r /version:C$versionNum~${Env:TF_BUILD_SOURCEGETVERSION} /noprompt |% {if ($_ -match "^\d+") {echo $matches[0]}}	
		echo "Displaying LatestArray $LatestchArr"
		if ($versionNum -eq $LatestchArr[0])		
			{
				Write-Host "`nNo version update since last successful build version : $versionNum" -ForegroundColor Yellow
				Write-Host "No Changeset found to Build. So Exiting!!!"
				exit 1
			}
		$chArr = $LatestchArr | Where-Object { $_ -ne $versionNum }
		$chArr=$chArr | sort {[int]$_}
		$chArr = [array]$chArr
		$LatestChSet=$chArr[$chArr.Length-1]
	}

Write-Host "The ChangeSets are $($chArr -join ',')"
	
################
# Fob logic here
################
function MakeBuild
{
[CmdletBinding()]
    param 
    (
        [String]$Database,
        [String]$Server,
		[array]$Changesets
    )

		$validFiles=@()
		$deletedFiles=@()
		foreach ($changeNum in $Changesets)
				{
					$buildFiles=@()
					$changeSetFile="${LogFolder}\${changeNum}_changeset.txt"
					tf.exe changeset ${changeNum} /collection:${tfsCollection} /noprompt > ${changeSetFile}
					$ChangeData = $(Get-Content ${changeSetFile})
					$(echo "ChangetSet ${changeNum}";echo "") >> $BuildChngSetInfoFl
					$ChangeData -match "(\s+[a-z]+.*\s\$\/)" >> $BuildChngSetInfoFl
					echo "" >> $BuildChngSetInfoFl
##					Please make sure $navSrvPath is defined in the script to get the result#########
					$validObjects=$($ChangeData -match "(add\s+\${navSrvPath}\/[a-zA-Z]+\/[a-zA-Z]+_\d+\.txt)|(merge\s+\${navSrvPath}\/[a-zA-Z]+\/[a-zA-Z]+_\d+\.txt)|(edit\s+\${navSrvPath}\/[a-zA-Z]+\/[a-zA-Z]+_\d+\.txt)"|% {$_ -replace "edit|add|merge|\$navSrvPath/",""}|% {$_.trim()})
					$deleteObjects=$($ChangeData -match "(delete\s+\${navSrvPath}\/[a-zA-Z]+\/[a-zA-Z]+_\d+\.txt)"|% {$_ -replace "delete|\$navSrvPath/|;.*",""}|% {$_.trim()})
					$validObjects > ${BldChngSetFlFolder}\${changeNum}_valid_changeset.txt
					$deleteObjects >  ${BldChngSetFlFolder}\${changeNum}_delete_changeset.txt
					$validFiles += $validObjects
					$deletedFiles += $deleteObjects
				}
		
		$validFiles=$validFiles|select -uniq 
		$validFiles > ${BldChngSetFlFolder}\Uniq_valid_changeset.txt
		$deletedFiles=$deletedFiles|select -uniq			
		$deletedFiles > ${BldChngSetFlFolder}\Uniq_delete_changeset.txt
		####Get the local workspace to latest changeset####
		echo "Getting the local workspace to latest changeset : $LatestChSet"
		tf get /version:$LatestChSet
		
		foreach($delFl in $deletedFiles)
				{	
					$objectType=$delFl.split("/")[0]
					$objectName=$delFl.split("/")[1]
					if ($validFiles -contains $delFl)
						{	
							$objectFileName="$NavisionCodeLocation\$objectType\$objectName"
							if (!(Test-Path $objectFileName)) 
								{
									echo "$objectFileName is not available at $NavisionCodeLocation"
									$validFiles=$validFiles -ne ${delFl}
								}
						}				
				}

		$validFiles > ${BldChngSetFlFolder}\Final_object_file.txt

#		We can make a change here for manual test of build for selected objects
#		$validFiles=@("Table/Table_10.txt","Table/Table_14.txt","Codeunit/Codeunit_10.txt")

		if ($ValidFiles.Length -eq 0)
			{
				Write-Host "Build will not be created as there are no valid files considered to create an incremental build"
				Write-Host "Build Success" -ForegroundColor Green
				echo $LatestChSet >  $SuccessVerFile
				exit 1			
			}
		else
			{
				echo "The Files considered for incremental Fob are -> $($($validFiles|%{ $_.Split('/')[1];}) -join ', ')"
				#Write-Host "Build will be created for total $($ValidFiles.Length) files"
			}

		#Performing Import of the objects into Navision
		#Setting the Flag initially as True
		$ImpCompFlag="T"

		foreach ($objFl in $validFiles)
			{
				$objectType=$objFl.split("/")[0]
				$objectFileName=$objFl.split("/")[1]
				$ID=$($objectFileName -match "\d+" > $null;$matches[0])
				$LogFile = "$LogFolder\Error_import_$objectFileName"
				$importFile = "$NavisionCodeLocation\$objectType\$objectFileName"
				$Type=Get-NAVObjectTypeIdFromName($objectType)
				if (Test-Path "$Logfolder\navcommandresult.txt") 
					{
						Remove-Item "$Logfolder\navcommandresult.txt"
					}
				$finSqlCommand = """$NAVFolder\finsql.exe"" command=importobjects,file=$importFile,servername=$Server,database=$Database,synchronizeschemachanges=force,importaction=overwrite,Logfile=$LogFile,filter=Type=$objecttype;ID=$ID"
				#echo $importfinsqlcommand
				Write-Debug $finSqlCommand
				cmd /c $finsqlCommand
				if (Test-Path $LogFile)
					{
						Write-Host "Error in import for $importFile.Please Check $LogFile for more Details"
						Write-Host "----------------------------------------------------------------------" -ForegroundColor Red
						cat $LogFile
						Write-Host "----------------------------------------------------------------------" -ForegroundColor Red
						$ImpCompFlag="F"
					}
				else 
					{
						Write-Host "Object with [ID]=$ID and Type=$Type Imported sucessfully" -ForegroundColor Green
					}
			}		
																
		if ($ImpCompFlag -eq "F")
			{				
				Write-Host "There are one or more import errors encountered while importing the objects into Navision" -ForegroundColor Red
				Write-Host "Please check the logs at $LogFolder for more information....." -ForegroundColor Red
				if ($dayZero -eq "T")
					{
						if (Test-Path ${SuccessVerFile}) 
							{	
								Remove-Item "${SuccessVerFile}" -Force
							}	
					}
				Write-Host "Build Failed" -ForegroundColor Red
				exit 1
			}
		else 
			{
				Write-Host "Import of all the objects completed sucessfully" -ForegroundColor Green			
			}
			
		#Performing Compilation of the objects which are imported into Navision			
		#Setting the Flag initially as True
		$ImpCompFlag="T"
			
		foreach ($objFl in $validFiles)
			{
				$objectType=$objFl.split("/")[0]
				$objectFileName=$objFl.split("/")[1]
				$ID=$($objectFileName -match "\d+" > $null;$matches[0])
				$LogFile = "$LogFolder\Error_compile_$objectFileName"
				$importFile = "$NavisionCodeLocation\$objectType\$objectFileName"
				$Type=Get-NAVObjectTypeIdFromName($objectType)
				
				if (Test-Path "$Logfolder\navcommandresult.txt") 
					{
						Remove-Item "$Logfolder\navcommandresult.txt"
					}				

				Write-Host "Compilation of object with [ID]=$ID and Type=$Type started" -ForegroundColor Yellow
				$finSqlCommand = """$NAVFolder\finsql.exe"" command=compileobjects,file=$ExportFile,servername=$Server,database=$Database,synchronizeschemachanges=force,Logfile=$LogFile,filter=Type=$objecttype;ID=$ID"
				Write-Debug $finSqlCommand
				cmd /c $finSqlCommand
				if (Test-Path $LogFile) 
					{   
						Write-Host "Compilation of object with [ID]=$ID and Type=$Type failed.. Please check log for more detail" -ForegroundColor Red 
						Write-Host "--------------------------------------------------------------------------------------------" -ForegroundColor Red
						cat $LogFile
						Write-Host "--------------------------------------------------------------------------------------------" -ForegroundColor Red
						$ImpCompFlag="F"
					}
				else
					{        
						Write-Host "Object with [ID]=$ID and Type=$Type Compiled successfully" -ForegroundColor Green
						#Updating [Version List] value of the imported object in Navision
						$sqlConnection = new-object System.Data.SqlClient.SqlConnection "server=$Server;database=$Database;Integrated Security=sspi"
						$sqlConnection.Open()
						$sqlCommand = $sqlConnection.CreateCommand()
						$sqlCommand.CommandText ="update Object set [Version List]='$versionlist' where [Type]=$type and [ID]=$ID"  
						$sqlReader = $sqlCommand.ExecuteReader()
						$sqlConnection.Close()																
					}						
			}
				
		if ($ImpCompFlag -eq "F")
			{				
				Write-Host "There are one or more compilation errors encountered while compiling the imported objects into Navision" -ForegroundColor Red
				Write-Host "Please check the logs at $LogFolder for more information....." -ForegroundColor Red
				if ($dayZero -eq "T")
					{
						if (Test-Path ${SuccessVerFile}) 
							{	
								Remove-Item "${SuccessVerFile}" -Force
							}	
					}
				Write-Host "Build Failed" -ForegroundColor Red
				exit 1
			}
		else 
			{
				Write-Host "Compilation of all the imported objects completed sucessfully" -ForegroundColor Green			
			}
									
		# Create and open a database connection
		$sqlConnection = new-object System.Data.SqlClient.SqlConnection "server=$Server;database=$Database;Integrated Security=sspi"
		$sqlConnection.Open()
		#Create a command object
		$sqlCommand = $sqlConnection.CreateCommand()
		$sqlCommand.CommandText ="select count(*) Result from Object where [Version List]='$versionlist'"  
		#Execute the Command
		$sqlReader = $sqlCommand.ExecuteReader()
		#Parse the records
		while ($sqlReader.Read())
		{ 
			$validVersionList=$sqlReader["Result"]
		} 
		# Close the database connection
		$sqlConnection.Close()

		echo "There are $validVersionList objects having [Version List]=${versionlist}"	
		if (${validVersionList} -eq 0)
			{
				Write-Host "No object found in Navision having Version list as ${versionlist}" -ForegroundColor Red
				if ($dayZero -eq "T")
					{
						if (Test-Path ${SuccessVerFile}) 
							{	
								Remove-Item "${SuccessVerFile}" -Force
							}	
					}
				Write-Host "Build Failed" -ForegroundColor Red
				exit 1
			}		
		
		$LogFile ="$LogFolder\Error_export_$versionlist.txt"
		
		if (Test-Path "$LogFolder\navcommandresult.txt")
			{
				Remove-Item "$LogFolder\navcommandresult.txt" -Force			
			}

		New-Item -ItemType directory -Path ${BldDateFolder}	
		$finSqlCommand = """$NAVFolder\finsql.exe"" command=exportobjects,file=$fobbuildfile,servername=$Server,database=$Database,Logfile=$LogFile,filter=Version List='$versionlist'" 
		echo $finSqlCommand
		cmd /c $finSqlCommand
		if (Test-Path "$LogFolder\navcommandresult.txt")
			{
				Type "$LogFolder\navcommandresult.txt"
			}	
		
		if (!(Test-Path -Path $LogFolder\Error_*.txt))
			{
				if (Test-Path "$fobbuildfile")
					{
						
						certutil -hashfile ${fobbuildfile} | ?{!($_ | select-string "hash")} > $md5File
						Copy-Item -Path "${fobbuildfile}" "${rmfobfile}" -recurse -Force
						Copy-Item -Path "${fobbuildfile}" "${FinalLatestFob}" -recurse -Force 
						Copy-Item -Path "${deployscript}" "${BldDrop}" -recurse -Force 
					}
				mv ${BuildChngSetInfoFl} ${BldDateFolder}
				Write-Host "Build Successful" -ForegroundColor Green
				echo $LatestChSet >  $SuccessVerFile
			}
		else 
			{				
				if ($dayZero -eq "T")
					{
						if (Test-Path ${SuccessVerFile}) 
							{	
								Remove-Item "${SuccessVerFile}" -Force
							}	
					}
				Write-Host "Build Failed" -ForegroundColor Red
				exit 1
			}
			
		echo "Exiting in the end: Good Bye"
		exit 0	
}	 

echo "Executing MakeBuild Function"
echo "Latest ChangeSet is : $LatestChSet"
MakeBuild -Database $Database -Server $Server -Changesets $chArr

##############################################################################################################









