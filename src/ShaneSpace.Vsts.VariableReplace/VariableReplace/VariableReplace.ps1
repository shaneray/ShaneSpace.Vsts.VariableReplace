param(
    [string]$configFiles,
    [string]$appSettings,
    [string]$connectionStrings,
    [string]$substituteVariablesFiles,
	[string]$secretVariables
)

# Import the modules
import-module "Microsoft.TeamFoundation.DistributedTask.Task.Internal"
import-module "Microsoft.TeamFoundation.DistributedTask.Task.Common"
. $PSScriptRoot\ShaneSpace.Vsts.VariableReplace.ps1

# convert boolean strings
$connectionStringsValue = Convert-String $connectionStrings Boolean
$appSettingsValue = Convert-String $appSettings Boolean

# constants
$nl = [Environment]::NewLine
$divider = "----------------------------"
if ($env:AGENT_JOBNAME -eq "Release") {
	$buildUri = ("{0}{1}/_apis/ReleaseManagement/releases/{2}"  -f ($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI -replace ".visualstudio.com",".vsrm.visualstudio.com") ,$env:SYSTEM_TEAMPROJECTID, $env:RELEASE_RELEASEID)
}
else {
	$buildUri = ("{0}{1}/_apis/build/Builds/{2}"  -f $env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI,$env:SYSTEM_TEAMPROJECTID, $env:BUILD_BUILDID)
}

# debug
Write-Verbose ("Selected Settings...{0}" -f $nl)
Write-Verbose ("Config File Path: {0}{1}" -f $configFiles,$nl)
Write-Verbose ("Replace AppSettings: {0}{1}" -f $appSettingsValue,$nl)
Write-Verbose ("Replace ConnectionStrings: {0}{1}" -f $connectionStringsValue,$nl)
Write-Verbose ("Substitute Variables Files: {0}{1}" -f $substituteVariablesFiles,$nl)
Write-Verbose ("Build Uri: {0}" -f $env:BUILD_BUILDURI)
Write-Verbose ("Build Number: {0}" -f $env:BUILD_BUILDNUMBER)
Write-Verbose ("System Project Id: {0}" -f  $env:SYSTEM_TEAMPROJECTID)
Write-Verbose ("SYSTEM_TEAMFOUNDATIONCOLLECTIONURI: {0}" -f  $env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI)
Write-Verbose ("Build Uri: {0}" -f  $buildUri)
Write-Verbose ("Secrets: {0}" -f  $secretVariables)
Write-Verbose ("SYSTEM_DEFAULTWORKINGDIRECTORY: {0}" -f  $env:SYSTEM_DEFAULTWORKINGDIRECTORY)
Write-Verbose ("BUILD_SOURCESDIRECTORY: {0}" -f  $env:BUILD_SOURCESDIRECTORY)
Write-Verbose $divider

# get VSTS api token
$vssEndPoint = Get-ServiceEndPoint -Name "SystemVssConnection" -Context $distributedTaskContext
$headers = @{Authorization = "Bearer {0}" -f $vssEndpoint.Authorization.Parameters.AccessToken}

# extract and parse file paths
$xmlFiles = Get-Files $configFiles "configFiles"
$variableFiles = Get-Files $substituteVariablesFiles "substituteVariablesFiles"

# get variables
$variableHashtable = Get-BuildVariables $secretVariables $buildUri $headers

# xml replace
foreach ($xmlFile in $xmlFiles)
{
	foreach ($path in $xmlFile.Paths)
	{
		Write-Host "Processing $path"
		Convert-XmlFile $path $variableHashtable $appSettingsValue $connectionStringsValue
	}
}

# variable replace
if ($substituteVariablesFiles)
{
	foreach ($variableFile in $variableFiles)
	{
		foreach ($path in $variableFile.Paths)
		{
			Write-Host "Processing $path"
			Convert-VariablesInFile $path $variableHashtable
		}
	}
}

# zip up
Write-Host "Zipping files..."
$zipFiles = $xmlFiles
$zipFiles += $variableFiles
foreach ($group in $zipFiles | Group {$_.ZipFileName}) {
	if ($group.Name -like "*.zip") {
		foreach ($file in Get-ChildItem $group.Group[0].ExtractedPath -name -Recurse) {
			Write-Host $file
		}
		Write-ZIPFile $group.Group[0].ExtractedPath $group.Name 
	}
}