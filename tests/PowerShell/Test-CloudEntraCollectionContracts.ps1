#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')
. (Join-Path $repositoryRoot 'infra\scripts\cloud-entra-common.ps1')

function Assert-SyntheticCondition {
    param(
        [Parameter(Mandatory)][bool] $Condition,
        [Parameter(Mandatory)][string] $FailureReason
    )

    if (-not $Condition) { throw $FailureReason }
}

function Assert-ExactOneDiscoveryRejected {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Items)

    $rejected = $false
    try {
        $null = @(Invoke-BoundedDiscovery `
            -Discovery { foreach ($item in $Items) { Write-Output $item } } `
            -IsReady { param($state) @($state).Count -eq 1 } `
            -FailureReason 'synthetic-exact-one-required' `
            -MaxAttempts 1 `
            -DelaySeconds 1)
    }
    catch {
        if ($_.Exception.Message -cne 'synthetic-exact-one-required') { throw }
        $rejected = $true
    }
    Assert-SyntheticCondition $rejected 'synthetic-bounded-discovery-accepted-invalid-count'
}

$empty = @(ConvertFrom-SanitizedJsonArray `
    -Lines @('[]') `
    -FailureReason 'synthetic-empty-json-invalid')
$single = @(ConvertFrom-SanitizedJsonArray `
    -Lines @('[{"id":"11111111-1111-1111-1111-111111111111"}]') `
    -FailureReason 'synthetic-single-json-invalid')
$duplicate = @(ConvertFrom-SanitizedJsonArray `
    -Lines @('[{"id":"11111111-1111-1111-1111-111111111111"},{"id":"22222222-2222-2222-2222-222222222222"}]') `
    -FailureReason 'synthetic-duplicate-json-invalid')

Assert-SyntheticCondition ($empty.Count -eq 0) 'synthetic-empty-count-invalid'
Assert-SyntheticCondition ($single.Count -eq 1) 'synthetic-single-count-invalid'
Assert-SyntheticCondition ($duplicate.Count -eq 2) 'synthetic-duplicate-count-invalid'
Assert-SyntheticCondition ($single[0] -isnot [System.Array]) 'synthetic-single-element-nested'
Assert-SyntheticCondition ($null -ne $single[0].PSObject.Properties['id']) 'synthetic-single-id-property-missing'
Assert-SyntheticCondition ($duplicate.Count -gt 1) 'synthetic-duplicate-not-detected'
$singleId = Get-RequiredStringProperty `
    -Object $single[0] `
    -Name 'id' `
    -FailureReason 'synthetic-single-id-read-invalid'
Assert-SyntheticCondition `
    ($singleId -ceq '11111111-1111-1111-1111-111111111111') `
    'synthetic-single-id-value-invalid'

$nestedPropertyReadRejected = $false
try {
    $null = Get-RequiredStringProperty `
        -Object (, $single[0]) `
        -Name 'id' `
        -FailureReason 'synthetic-nested-property-read-rejected'
}
catch {
    if ($_.Exception.Message -cne 'synthetic-nested-property-read-rejected') { throw }
    $nestedPropertyReadRejected = $true
}
Assert-SyntheticCondition $nestedPropertyReadRejected 'synthetic-nested-property-read-accepted'

Assert-ExactOneDiscoveryRejected $empty
Assert-ExactOneDiscoveryRejected $duplicate
$boundedSingle = @(Invoke-BoundedDiscovery `
    -Discovery { foreach ($item in $single) { Write-Output $item } } `
    -IsReady { param($state) @($state).Count -eq 1 } `
    -FailureReason 'synthetic-single-discovery-invalid' `
    -MaxAttempts 1 `
    -DelaySeconds 1)
Assert-SyntheticCondition ($boundedSingle.Count -eq 1) 'synthetic-single-discovery-count-invalid'
Assert-SyntheticCondition ($boundedSingle[0] -isnot [System.Array]) 'synthetic-single-discovery-nested'

Write-Output 'synthetic-count-0:0'
Write-Output 'synthetic-count-1:1'
Write-Output 'synthetic-count-2:2'
Write-Output 'synthetic-duplicate-detection-valid'
Write-Output 'synthetic-nested-property-rejection-valid'
Write-Output 'synthetic-bounded-discovery-exact-one-valid'
