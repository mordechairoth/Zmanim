﻿properties {
  $zipFileName = "Zmanim150r1.zip"
  $majorVersion = "1.0"
  $majorWithReleaseVersion = "1.5.0"
  $nugetPrerelease = "alpha1"
  $version = GetVersion $majorWithReleaseVersion
  $packageId = "Zmanim"
  $signAssemblies = $false
  $signKeyPath = "C:\Development\Releases\zmanim.snk"
  $buildDocumentation = $false
  $buildNuGet = $true
  $msbuildVerbosity = 'minimal'#normal
  $treatWarningsAsErrors = $false
  $workingName = if ($workingName) {$workingName} else {"Working"}
  $netCliChannel = "2.0"
  $netCliVersion = "2.1.301"
  $nugetUrl = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"

  $baseDir  = resolve-path ..
  $buildDir = "$baseDir\Build"
  $sourceDir = "$baseDir\src"
  $toolsDir = "$baseDir\Tools"
  $docDir = "$baseDir\Doc"
  $releaseDir = "$baseDir\Release"
  $workingDir = "$baseDir\$workingName"
  
  $solutionFile = "$baseDir\Zmanim.sln"
  $mainProjectName = "Zmanim"
  $testProjectPath = "$sourceDir\ZmanimTests\ZmanimTests.csproj"
  $testProjectDirectory = "$sourceDir\ZmanimTests"
  $testAssemblyName = "ZmanimTests.dll"
  
  $nugetPath = "$buildDir\Temp\nuget.exe"
  $vswhereVersion = "2.3.2"
  $vswherePath = "$buildDir\Temp\vswhere.$vswhereVersion"
  $nunitConsoleVersion = "3.8.0"
  $nunitConsolePath = "$buildDir\Temp\NUnit.ConsoleRunner.$nunitConsoleVersion"

  $builds = @(
    @{Framework = "netstandard2.0"; TestsFunction = "NetCliTests"; TestFramework = "netcoreapp2.0"; Enabled=$true},
    @{Framework = "net45"; TestsFunction = "NUnitTests"; TestFramework = "net46"; NUnitFramework="net-4.0"; Enabled=$true},
    @{Framework = "netstandard1.3"; Enabled=$true},
    @{Framework = "netstandard1.0"; Enabled=$true},
    @{Framework = "net40"; Enabled=$true},
    @{Framework = "net35"; Enabled=$true},
    @{Framework = "net20"; Enabled=$true},
    @{Framework = "portable-net45+win8+wpa81+wp8"; Enabled=$true},
    @{Framework = "portable-net40+win8+wpa81+wp8+sl5"; Enabled=$true}
  )
}

framework '4.6x86'

task default -depends Test,Package

# Ensure a clean working directory
task Clean {
  Write-Host "Setting location to $baseDir"
  Set-Location $baseDir

  if (Test-Path -path $workingDir)
  {
    Write-Host "Deleting existing working directory $workingDir"

    Execute-Command -command { del $workingDir -Recurse -Force }
  }

  Write-Host "Creating working directory $workingDir"
  New-Item -Path $workingDir -ItemType Directory

}

# Build each solution, optionally signed
task Build -depends Clean {
  $script:enabledBuilds = $builds | ? {$_.Enabled}
  Write-Host -ForegroundColor Green "Found $($script:enabledBuilds.Length) enabled builds"

  mkdir "$buildDir\Temp" -Force
  EnsureNuGetExists
  EnsureNuGetPackage "vswhere" $vswherePath $vswhereVersion
  EnsureNuGetPackage "NUnit.ConsoleRunner" $nunitConsolePath $nunitConsoleVersion

  $script:msBuildPath = GetMsBuildPath
  Write-Host "MSBuild path $script:msBuildPath"

  NetCliBuild
}

# Optional build documentation, add files to final zip
task Package -depends Build {
  foreach ($build in $script:enabledBuilds)
  {
    $finalDir = $build.Framework

    $sourcePath = "$sourceDir\$mainProjectName\bin\Release\$finalDir"

    if (!(Test-Path -path $sourcePath))
    {
      throw "Could not find $sourcePath"
    }

    robocopy $sourcePath $workingDir\Package\Bin\$finalDir *.dll *.pdb *.xml /NFL /NDL /NJS /NC /NS /NP /XO /XF *.CodeAnalysisLog.xml | Out-Default
  }

  if ($buildNuGet)
  {
    Write-Host -ForegroundColor Green "Copy NuGet package"

    mkdir $workingDir\NuGet
    move -Path $sourceDir\$mainProjectName\bin\Release\*.nupkg -Destination $workingDir\NuGet
  }

  Write-Host "Build documentation: $buildDocumentation"

  if ($buildDocumentation)
  {
    $mainBuild = $script:enabledBuilds | where { $_.Framework -eq "net45" } | select -first 1
    $mainBuildFinalDir = $mainBuild.Framework
    $documentationSourcePath = "$workingDir\Package\Bin\$mainBuildFinalDir"
    $docOutputPath = "$workingDir\Documentation\"
    Write-Host -ForegroundColor Green "Building documentation from $documentationSourcePath"
    Write-Host "Documentation output to $docOutputPath"

    # Sandcastle has issues when compiling with .NET 4 MSBuild
    exec { & $script:msBuildPath "/t:Clean;Rebuild" "/v:$msbuildVerbosity" "/p:Configuration=Release" "/p:DocumentationSourcePath=$documentationSourcePath" "/p:OutputPath=$docOutputPath" "/m" "$docDir\doc.shfbproj" | Out-Default } "Error building documentation. Check that you have Sandcastle, Sandcastle Help File Builder and HTML Help Workshop installed."

    move -Path $workingDir\Documentation\LastBuild.log -Destination $workingDir\Documentation.log
  }

  Copy-Item -Path $baseDir\README.md -Destination $workingDir\Package\readme.txt
  Copy-Item -Path $baseDir\LICENSE.md -Destination $workingDir\Package\license.txt

  robocopy $sourceDir $workingDir\Package\Source\Src /MIR /NFL /NDL /NJS /NC /NS /NP /XD bin obj TestResults AppPackages .vs artifacts /XF *.suo *.user *.lock.json | Out-Default
  robocopy $buildDir $workingDir\Package\Source\Build /MIR /NFL /NDL /NJS /NC /NS /NP /XD Temp /XF runbuild.txt | Out-Default
  robocopy $docDir $workingDir\Package\Source\Doc /MIR /NFL /NDL /NJS /NC /NS /NP | Out-Default
  robocopy $toolsDir $workingDir\Package\Source\Tools /MIR /NFL /NDL /NJS /NC /NS /NP | Out-Default

  Compress-Archive -Path $workingDir\Package\* -DestinationPath $workingDir\$zipFileName
}

task Test -depends Build {
  foreach ($build in $script:enabledBuilds)
  {
    if ($build.TestsFunction -ne $null){
        Write-Host "Calling $($build.TestsFunction)"
        & $build.TestsFunction $build
    }
  }
}

function NetCliBuild()
{
  $projectPath = $solutionFile
  $libraryFrameworks = ($script:enabledBuilds | Select-Object @{Name="Framework";Expression={$_.Framework}} | select -expand Framework) -join ";"
  $testFrameworks = ($script:enabledBuilds | ? {$_.TestFramework -ne $null} | Select-Object @{Name="Resolved";Expression={ $_.TestFramework }} | select -expand Resolved) -join ";"

  $additionalConstants = switch($signAssemblies) { $true { "SIGNED" } default { "" } }

  Write-Host -ForegroundColor Green "Restoring packages for $libraryFrameworks in $projectPath"
  Write-Host

  exec { & $script:msBuildPath "/t:restore" "/v:$msbuildVerbosity" "/p:Configuration=Release" "/p:LibraryFrameworks=`"$libraryFrameworks`"" "/p:TestFrameworks=`"$testFrameworks`"" "/m" $projectPath | Out-Default } "Error restoring $projectPath"

  Write-Host -ForegroundColor Green "Building $libraryFrameworks in $projectPath"
  Write-Host

  $assemblyVersion = $majorVersion + '.0.0'

  exec { & $script:msBuildPath "/t:build" "/v:$msbuildVerbosity" $projectPath "/p:Configuration=Release" "/p:LibraryFrameworks=`"$libraryFrameworks`"" "/p:TestFrameworks=`"$testFrameworks`"" "/p:AssemblyOriginatorKeyFile=$signKeyPath" "/p:SignAssembly=$signAssemblies" "/p:TreatWarningsAsErrors=$treatWarningsAsErrors" "/p:AdditionalConstants=$additionalConstants" "/p:GeneratePackageOnBuild=$buildNuGet" "/p:ContinuousIntegrationBuild=true" "/p:PackageId=$packageId" "/p:VersionPrefix=$majorWithReleaseVersion" "/p:VersionSuffix=$nugetPrerelease" "/p:AssemblyVersion=$assemblyVersion" "/p:FileVersion=$version" "/m" }
}

function EnsureNuGetExists()
{
  if (!(Test-Path $nugetPath))
  {
    Write-Host "Couldn't find nuget.exe. Downloading from $nugetUrl to $nugetPath"
    (New-Object System.Net.WebClient).DownloadFile($nugetUrl, $nugetPath)
  }
}

function EnsureNuGetPackage($packageName, $packagePath, $packageVersion)
{
  if (!(Test-Path $packagePath))
  {
    Write-Host "Couldn't find $packagePath. Downloading with NuGet"
    exec { & $nugetPath install $packageName -OutputDirectory $buildDir\Temp -Version $packageVersion -ConfigFile "$sourceDir\nuget.config" | Out-Default } "Error restoring $packagePath"
  }
}

function GetMsBuildPath()
{
  $path = & $vswherePath\tools\vswhere.exe -latest -products * -requires Microsoft.Component.MSBuild -property installationPath
  if (!($path)) {
    throw "Could not find Visual Studio install path"
  }
  return join-path $path 'MSBuild\15.0\Bin\MSBuild.exe'
}

function NetCliTests($build)
{
  $projectPath = $testProjectPath
  $location = $testProjectDirectory
  $testDir = if ($build.TestFramework -ne $null) { $build.TestFramework } else { $build.Framework }

  exec { .\Tools\Dotnet\dotnet-install.ps1 -Channel $netCliChannel -Version $netCliVersion | Out-Default }

  try
  {
    Set-Location $location

    exec { dotnet --version | Out-Default }

    Write-Host -ForegroundColor Green "Running tests for $testDir"
    Write-Host "Location: $location"
    Write-Host "Project path: $projectPath"
    Write-Host

    exec { dotnet test $projectPath -f $testDir -c Release -l trx -r $workingDir --no-restore --no-build | Out-Default }
  }
  finally
  {
    Set-Location $baseDir
  }
}

function NUnitTests($build)
{
  $testDir = if ($build.TestFramework -ne $null) { $build.TestFramework } else { $build.Framework }
  $framework = $build.NUnitFramework
  $testRunDir = "$testProjectDirectory\bin\Release\$testDir"

  Write-Host -ForegroundColor Green "Running NUnit tests $testDir"
  Write-Host
  try
  {
    Set-Location $testRunDir
    exec { & $nunitConsolePath\tools\nunit3-console.exe "$testRunDir\$testAssemblyName" --framework=$framework --result=$workingDir\$testDir.xml --out=$workingDir\$testDir.txt | Out-Default } "Error running $testDir tests"
  }
  finally
  {
    Set-Location $baseDir
  }
}

function GetVersion($majorVersion)
{
    $now = [DateTime]::Now

    $year = $now.Year - 2000
    $month = $now.Month
    $totalMonthsSince2000 = ($year * 12) + $month
    $day = $now.Day
    $minor = "{0}{1:00}" -f $totalMonthsSince2000, $day

    $hour = $now.Hour
    $minute = $now.Minute
    $revision = "{0:00}{1:00}" -f $hour, $minute

    return $majorVersion + "." + $minor
}

function Edit-XmlNodes {
    param (
        [xml] $doc,
        [string] $xpath = $(throw "xpath is a required parameter"),
        [string] $value = $(throw "value is a required parameter")
    )

    $nodes = $doc.SelectNodes($xpath)
    $count = $nodes.Count

    Write-Host "Found $count nodes with path '$xpath'"

    foreach ($node in $nodes) {
        if ($node -ne $null) {
            if ($node.NodeType -eq "Element")
            {
                $node.InnerXml = $value
            }
            else
            {
                $node.Value = $value
            }
        }
    }
}

function Execute-Command($command) {
    $currentRetry = 0
    $success = $false
    do {
        try
        {
            & $command
            $success = $true
        }
        catch [System.Exception]
        {
            if ($currentRetry -gt 5) {
                throw $_.Exception.ToString()
            } else {
                write-host "Retry $currentRetry"
                Start-Sleep -s 1
            }
            $currentRetry = $currentRetry + 1
        }
    } while (!$success)
}