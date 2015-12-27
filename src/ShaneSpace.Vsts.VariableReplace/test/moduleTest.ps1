param(
	[Parameter(Mandatory=$True)]
    [string]$personalAccessToken
)
# Methods
function Find-Files ($SearchPattern) {
	Write-Host ("Finding files in: {0}" -f $SearchPattern)
	$output = $SearchPattern.Split("`n")
	for ($i = 0; $i -le $output.GetUpperBound(0); $i++)
	{
		 if ($output[$i].Contains("*"))
		{
			$lineText = $output[$i]
			$output[$i] = $lineText.replace("*", "1")
			$output += $lineText.replace("*", "2")
		}
	}
	return $output
}

function Invoke-Test ($testName, $test) {
	Write-Host "Invoking test: $testName"
	if ($test)
	{
		Write-Host -ForegroundColor green "$testName passed.."
	}
	else {
		Write-Host -ForegroundColor Red "$testName failed.."
	}
}

# Arrange Static variables
. "$PSScriptRoot\..\VariableReplace\ShaneSpace.Vsts.VariableReplace.ps1"
$nl = [Environment]::NewLine
$divider = "----------------------------"
$headers = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($personalAccessToken)")) }

# Arrange Test Inputs
$originalFileName = "C:\Users\Shane\Desktop\ConfigTransform\test\web.original.config"; # this is the original web.config that will be copied over 
$fileName = "C:\Users\Shane\Desktop\ConfigTransform\test\web.config";  # web.config file to overwrite at begin of test and test will be ran against
$buildUri = "https://shaneray.visualstudio.com/DefaultCollection/07e79085-14b6-4db1-b12c-55835b80f967/_apis/build/Builds/60"
$sourceDirectory = "C:\Repos\ShaneSpace.Vsts.VariableReplace\ShaneSpace.Vsts.VariableReplace\src\ShaneSpace.Vsts.VariableReplace\test"

# fake VSTS task user inputs
$configFiles = "web.config
test.zip => *.config
test*.zip => *.config
test3.zip => *.config"

$AppSettings = $true;
$ConnectionStrings = $True;
$substituteVariablesFiles = "web.config
test.zip => *.config"
$secretVariables = "Secret1=test1
Secret2 = test2
Secret6= test3
Secret4 =test4
Secret5 = test5"

# Init
Copy-Item -Path $originalFileName -Destination $fileName -Force
# Clean Up (do this at the end in production)
Remove-Item "$sourceDirectory/shanespacetmp/*" -Recurse

# Act
$variableHashtable = Get-BuildVariables $secretVariables $buildUri $headers

# parse input file paths
$xmlFiles = Get-Files $configFiles "configFiles"
$variableFiles = Get-Files $substituteVariablesFiles "substituteVariablesFiles"

# do substitutions
#Convert-XmlFile $fileName $variableHashtable $true $true
#Convert-VariablesInFile $fileName $variableHashtable

# re-zip files

# Assert
#foreach ($xmlFile in $xmlFiles) {
#	Write-host ("{0} - {1}" -f $xmlFile.ZipFileName,[string]::Join(", ", $xmlFile.Paths))
#}
#foreach ($variableFile in $variableFiles) {
#	Write-host ("{0} - {1}" -f $variableFile.ZipFileName,[string]::Join(", ", $variableFile.Paths))
#}
$zipFiles = @();
$zipFiles = $xmlFiles
$zipFiles += $variableFiles
foreach ($group in $zipFiles | Group {$_.ZipFileName}) {
	if ($group.Name -like "*.zip") {
		$group.Name 
		$group.Group[0].ExtractedPath
	}
}
Write-ZIPFile "C:\Repos\ShaneSpace.Vsts.VariableReplace\src\ShaneSpace.Vsts.VariableReplace\test\testCompress" "C:\Repos\ShaneSpace.Vsts.VariableReplace\src\ShaneSpace.Vsts.VariableReplace\test\testZip.zip"

foreach ($file in Get-ChildItem "C:\Repos\ShaneSpace.Vsts.VariableReplace\src\ShaneSpace.Vsts.VariableReplace\test\shanespacetmp" -name -Recurse) {
	Write-Host $file
}
Invoke-Test "Hastable_count_should_be_9" ($variableHashtable.Count -eq 9)
