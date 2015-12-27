$nl = [Environment]::NewLine
$divider = "----------------------------"
Add-Type -assembly "system.io.compression.filesystem"

function Get-Files 
{
    [cmdletbinding()]
    param(
        [string]$files,
		[string]$type
    )
    $output = @()
	# check for pattern
	if ($files.Contains("=>")) {
		$output += Get-ZipFiles $files $type
	}

	# remove processed zip files from $files
	$nonZip = $files.Split("`n") | Where-Object { $_ -notmatch ".zip" }
	if ($nonZip) {
		$files = [string]::Join("`n",  $nonZip)
	}
	else {
		$files = "";
	}

	if ($files -ne "") {
		Write-Host ("NonZip: {0}" -f $files);
		$splitFiles = $files.Split("`n")
		foreach($file in $splitFiles)
		{
			if ($file.Contains("*") -or $file.Contains("?")) {
			    Write-Host "Pattern found in $type parameter. Calling Find-Files."
			    Write-Host "Find-Files -SearchPattern $files"
			    $findFileOutput = Find-Files -SearchPattern $file -RootFolder $env:SYSTEM_DEFAULTWORKINGDIRECTORY
			}
			else {
			    Write-Host "No Pattern found in $type parameter."
			    $findFileOutput = ,$file
			}

			if ($findFileOutput.Count -gt 0) {
				$singleFiles = @{}
				$singleFiles.ZipFileName = $null
				$singleFiles.Paths = $findFileOutput
				$output += $singleFiles
			}
		}
	}

	if (!$output) {
        throw ("No $type was found using search pattern '{0}'." -f $files)
    }

    return ,$output
}

function Expand-ZIPFile($file, $destination)
{
	if (Test-path $destination)
	{
		Write-Host "$destination already exist. skipping."
	}
	else
	{
		Write-Host "Extracting $file"
		[io.compression.zipfile]::ExtractToDirectory($file, $destination)
	}
}

function Write-ZIPFile($src, $destination)
{
	if (Test-path $destination) { Remove-item $destination }
	Write-Host "Creating $destination from $src."
	[io.compression.zipfile]::CreateFromDirectory($src, $destination)
}

function Get-ZipFiles
{
    param(
        [string]$files,
		[string]$type
    )
	
	# find zip files
	Write-Host "Getting $type Zip Files..."
	$zipFiles = @()
	$zipIndex = 0
	if ($files.Contains("=>"))
	{
		$splitFiles = $files.Split("`n")
		foreach($file in $splitFiles)
		{
			if ($file.Contains("=>"))
			{
				$zipIndex = $file.IndexOf("=>")
				Write-Host ("Finding files for {0}" -f $file.Substring(0, $zipIndex))
				$zipFileNames = Find-Files -SearchPattern $file.Substring(0, $zipIndex).trim() -RootFolder $env:SYSTEM_DEFAULTWORKINGDIRECTORY
				foreach ($zipFileName in $zipFileNames)
				{
					$extractedFolder = ("$env:SYSTEM_DEFAULTWORKINGDIRECTORY\shanespacetmp\{0}" -f (Split-Path $zipFileName -Leaf))
					Write-Host ("Extracting {0} to {1}" -f $zipFileName, $extractedFolder)
					Expand-ZIPFile $zipFileName $extractedFolder
					$zipFile = @{}
					$zipFile.ZipFileName = $zipFileName
					$zipFile.ExtractedPath = $extractedFolder
					$zipFile.Paths = Find-Files -SearchPattern $file.SubString($zipIndex).replace("=>", "").trim()  -RootFolder $extractedFolder
					$zipFiles += $zipFile
				}
			}
		} 
	}
	Write-Host ("{0} Zip files found." -f $zipFiles.Count)
	Write-Host $divider
    return $zipFiles
}

function Convert-VariableString($variableText)
{
    $variables = $variableText.Split([environment]::NewLine);
    $output = @{}
    foreach($variable in $variables)
    {
       if ($variable -and $variable.Trim() -ne "")
       {
            $index = $variable.IndexOf("=")
            $output.Add($variable.SubString(0, $index).Trim(), $variable.SubString($index + 1).Trim())
       }
    }
    return $output
}

function Get-BuildVariables($secretVariablesText, $buildUri, $headers)
{
	if ($env:AGENT_JOBNAME -eq "Release") {
		Write-Host "Loading variables..."
		Write-Host ("URI: {0}{1}" -f $buildUri, $nl)
		$response = Invoke-RestMethod -Method Get -Uri $buildUri -Headers $headers
		$variables = Convert-VariableString $secretVariablesText
	}
	else
	{
		Write-Host "Loading parameters..."
		Write-Host ("URI: {0}{1}" -f $buildUri, $nl)
		$response = Invoke-RestMethod -Method Get -Uri $buildUri -Headers $headers
		$parameters = $response.parameters | ConvertFrom-Json

		Write-Host "Loading variables..."
		Write-Host ("URI: {0}{1}" -f $response.definition.url, $nl)
		$response = Invoke-RestMethod -Method Get -Uri $response.definition.url -Headers $headers
		$variables = Convert-VariableString $secretVariablesText
	}
	Write-Host "Variables and parameters loaded proccessing..."
	$response.variables | get-member -type NoteProperty | foreach-object {
		if ($_)
		{
			$name = $_.Name
			$value = $response.variables."$($_.Name)"
			
			# if an override parameter is set use its value.
			if ($parameters."$($_.Name)" -and $value.allowOverride) {
				$value.value = $parameters."$($_.Name)"
			}
	
			# if its secret and it was not provided show message, else add to variables
			if ($value.isSecret) {
				if (!$variables.ContainsKey($name)) {
					write-host ("Secret variable ignored: $name. To include a secret variable add it to the build task with this line in the secret variable input `"$name = `$($name)`"")
				}
			}
			else {
				if ($variables.ContainsKey($name)) {
					Write-Host "Duplicate assignment for $name,  If this is not a secret variable there is no need for it to be in the secret variable text."
					$variables.Remove($name)
				}

				$variables.Add($name,$value.value);
			}
		}
	}
	Write-Host ("{0} variables found" -f $variables.Count);
	Write-Host $divider
	return $variables
}

function Convert-XmlFile($fileName, $variables, $appSettings, $connectionStrings)
{
	$nl = [Environment]::NewLine
	$divider = "----------------------------"

	# Load config file
	[xml]$config = Get-Content $fileName
	[System.Xml.XmlElement] $root = $config.get_DocumentElement()

	# make replacements
	if ($appSettings)
	{
		[System.Xml.XmlElement] $configAppSettings = $root.appSettings

		Write-Host "Processing Appsettings..."
		foreach ($node in $configAppSettings.ChildNodes)
		{
			if ($node.key) {
				if ($variables.ContainsKey($node.key))
				{
					Write-Host ("appSetting replaced: {0} old value ({1}) new value ({2})" -f $node.key, $node.value, $variables[$node.key])
					$node.value = $variables[$node.key]
				}
			}
		}
		Write-Host ($divider)
	}
	
	if ($connectionStrings)
	{
		[System.Xml.XmlElement] $configConnectionStrings = $root.connectionStrings
		Write-Host "Processing ConnectionStrings:"
		foreach ($node in $configConnectionStrings.ChildNodes)
		{
			if ($variables.ContainsKey($node.name))
			{
				$node.connectionString = $variables[$node.name]
				Write-Host ("connectionString replaced: {0} old value ({1}) new value ({2})" -f $node.name, $node.connectionString, $variables[$node.name])
			}
		}
		Write-Host ($divider)
	}

	# save config file
	$config.Save($fileName);
}

function Convert-VariablesInFile($fileName, $variables)
{
	Write-Host "Processing variable replace..."
	$encoding = Get-FileEncoding($fileName)
	$config = (Get-Content $fileName) | Foreach-Object {
		$line = $_
		foreach ($variable in $variables.GetEnumerator()) {
			$line = $line -replace ("\$\({0}\)" -f $variable.Name), $variables[$variable.Name]
		}
		$line
	} | Set-Content $fileName -Encoding $encoding
	$divider
}

function Get-FileEncoding($Path)
{
    $bytes = [byte[]](Get-Content $Path -Encoding byte -ReadCount 4 -TotalCount 4)

    if(!$bytes) { return 'utf8' }

    switch -regex ('{0:x2}{1:x2}{2:x2}{3:x2}' -f $bytes[0],$bytes[1],$bytes[2],$bytes[3]) {
        '^efbbbf'   { return 'utf8' }
        '^2b2f76'   { return 'utf7' }
        '^fffe'     { return 'unicode' }
        '^feff'     { return 'bigendianunicode' }
        '^0000feff' { return 'utf32' }
        default     { return 'ascii' }
    }
}