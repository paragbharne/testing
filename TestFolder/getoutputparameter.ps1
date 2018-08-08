$outputs = ConvertFrom-Json $($env:ResourceGroupDeploymentOutputs)

foreach ($output in $outputs.PSObject.Properties) 

{

  Write-Host "##vso[task.setvariable variable=$($output.Name)]$($output.Value.value)"
  
}