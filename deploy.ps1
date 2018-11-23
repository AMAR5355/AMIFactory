Import-Module AWSPowerShell

Write-Host 'Enter the name of the deployment environment:'
$bakingEnv = Read-Host

Write-Host 'Enter the ID of subnet to be used to launch instances:'
$subnet = Read-Host

Write-Host 'Enter the KeyPair to be used to launch instances:'
$keypair = Read-Host

Function TagParameters() {
  $amiFactoryParameters = Get-SSMParametersByPath -Path /amifactory -Recursive $true -ProfileName deploy

  [System.Collections.ArrayList]$ssmTagList = @()
  $tag = new-object Amazon.SimpleSystemsManagement.Model.Tag
  $tag.Key = 'Application'
  $tag.Value = 'amifactory'
  [void]$ssmTagList.Add($tag)

  foreach($p in $amiFactoryParameters) {
    Add-SSMResourceTag -ResourceId $p.Name -ResourceType "Parameter" -Tag $ssmTagList -ProfileName deploy
  }
  Write-Host 'SSM Parameters have been tagged with the specified values' -ForegroundColor Green
}

Function DeployDocument($name) {
  $documentName = "AMIFactory-$name"
  $documentContent = Get-Content -Raw ".\sample-documents\$name.json"

  $documentExists = $false

  try
  {
    $doc = Get-SSMDocument -Name $documentName -ProfileName deploy
    $documentExists = $true
  }
  catch 
  { }

  if($documentExists)
  {
    # Document exists, attempt to update it
    try 
    {
      $updateDocumentResult = Update-SSMDocument -Content $documentContent -Name $documentName -DocumentVersion '$LATEST' -ProfileName deploy
      Update-SSMDocumentDefaultVersion -Name $documentName -DocumentVersion $updateDocumentResult.LatestVersion -ProfileName deploy
      Write-Host "$documentName Document updated to version $($updateDocumentResult.LatestVersion)" -ForegroundColor Green
    }    
    catch
    {
      if(-not($_.Exception.Message.Contains('has the same metadata and content as latest version document'))) {
        Throw
      } else {
        Write-Host "$documentName reports 'No updates are to be performed.'  Continuing without updating." -ForegroundColor Yellow
      }
    }
  }
  else
  {
    New-SSMDocument -Content $documentContent -DocumentType 'Automation' -Name $documentName -ProfileName deploy
    Write-Host "$documentName Document created" -ForegroundColor Green
  }
}

Write-Host 'Deploying security stack'
aws cloudformation deploy --template-file templates/security.template --stack-name amifactory-security --capabilities CAPABILITY_NAMED_IAM --tags Application=amifactory --profile deploy

Write-Host 'Deploying automation stack'
aws cloudformation deploy --template-file templates/automation.template --stack-name amifactory-automation --tags Application=amifactory --profile deploy

Write-Host 'Deploying statemachine stack'
aws cloudformation deploy --template-file templates/statemachine.template --stack-name amifactory-statemachine  --tags Application=amifactory --profile deploy

Write-Host 'Deploying parameters stack'
aws cloudformation deploy --template-file templates/parameters.template --stack-name amifactory-parameters --tags Application=amifactory --profile deploy --parameter-overrides BakingEnvironment=$bakingEnv BakingSubnetId=$subnet InstanceKeyPair=$keypair

# Apply tags to parameters for tracking and IAM policies
TagParameters

DeployDocument 'Foundation'
DeployDocument 'Foundation-Validation'
DeployDocument 'WebServer'
DeployDocument 'WebServer-Validation'
