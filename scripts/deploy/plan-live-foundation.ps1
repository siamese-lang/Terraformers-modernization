[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TfvarsPath,

    [ValidateSet("reuse", "create")]
    [string]$OidcProviderMode = "reuse",

    [string]$TerraformExe = "",

    [string]$PlanPath = "",

    [string]$ExpectedBranch = "agent/rdb-domain-realignment",

    [string]$ExpectedHead = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-LastExitCode {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Code
    )

    if ($LASTEXITCODE -ne 0) {
        throw $Code
    }
}

function Get-FullPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return [IO.Path]::GetFullPath($Path)
}

$RepoRoot = Get-FullPath (Join-Path $PSScriptRoot "..\..")
$FoundationDir = Join-Path $RepoRoot "infra\terraform\bootstrap\aws-live-foundation"

if ([string]::IsNullOrWhiteSpace($TerraformExe)) {
    $TerraformExe = Join-Path $env:LOCALAPPDATA "Programs\Terraform\1.15.8\terraform.exe"
}

if ([string]::IsNullOrWhiteSpace($PlanPath)) {
    $PrivateDir = Join-Path $env:LOCALAPPDATA "Terraformers\live-foundation"
    New-Item -ItemType Directory -Force -Path $PrivateDir | Out-Null
    $PlanPath = Join-Path $PrivateDir "foundation.tfplan"
}

if (-not (Test-Path -LiteralPath $TerraformExe -PathType Leaf)) {
    throw "TERRAFORM_1_15_8_NOT_FOUND"
}

if (-not (Test-Path -LiteralPath $TfvarsPath -PathType Leaf)) {
    throw "PRIVATE_FOUNDATION_TFVARS_NOT_FOUND"
}

$TfvarsFullPath = (Resolve-Path -LiteralPath $TfvarsPath).Path
$PlanFullPath = Get-FullPath $PlanPath
$RepoPrefix = $RepoRoot.TrimEnd("\") + "\"

if ($TfvarsFullPath.StartsWith($RepoPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "PRIVATE_TFVARS_MUST_BE_OUTSIDE_REPOSITORY"
}

if ($PlanFullPath.StartsWith($RepoPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "BINARY_PLAN_MUST_BE_OUTSIDE_REPOSITORY"
}

$TfvarsText = Get-Content -LiteralPath $TfvarsFullPath -Raw
if ($TfvarsText -match 'replace-|<12-digit|000000000000|state_bucket_name\s*=\s*""') {
    throw "PRIVATE_TFVARS_CONTAINS_PLACEHOLDER"
}

Set-Location $RepoRoot

$WorkingTreeChanges = @(& git status --porcelain)
Assert-LastExitCode "GIT_STATUS_FAILED"
if ($WorkingTreeChanges.Count -gt 0) {
    $WorkingTreeChanges | ForEach-Object { Write-Host $_ }
    throw "WORKING_TREE_NOT_CLEAN"
}

$CurrentBranch = (& git branch --show-current).Trim()
Assert-LastExitCode "GIT_BRANCH_READ_FAILED"
if (-not [string]::IsNullOrWhiteSpace($ExpectedBranch) -and $CurrentBranch -ne $ExpectedBranch) {
    throw "BRANCH_MISMATCH"
}

$CurrentHead = (& git rev-parse HEAD).Trim()
Assert-LastExitCode "GIT_HEAD_READ_FAILED"
if (-not [string]::IsNullOrWhiteSpace($ExpectedHead) -and $CurrentHead -ne $ExpectedHead) {
    throw "HEAD_MISMATCH"
}

$TerraformVersionLine = (& $TerraformExe version | Select-Object -First 1)
Assert-LastExitCode "TERRAFORM_VERSION_READ_FAILED"
if ($TerraformVersionLine -ne "Terraform v1.15.8") {
    throw "TERRAFORM_VERSION_MISMATCH"
}

$PreviousAutomationValue = $env:TF_IN_AUTOMATION
$env:TF_IN_AUTOMATION = "1"

Push-Location $FoundationDir
try {
    & $TerraformExe init -backend=false -input=false -lockfile=readonly
    Assert-LastExitCode "LOCKED_TERRAFORM_INIT_FAILED"

    & $TerraformExe fmt -check -diff
    Assert-LastExitCode "TERRAFORM_FMT_FAILED"

    & $TerraformExe validate
    Assert-LastExitCode "TERRAFORM_VALIDATE_FAILED"

    Remove-Item -LiteralPath $PlanFullPath -Force -ErrorAction SilentlyContinue

    $PlanOutput = @(
        & $TerraformExe plan `
            -input=false `
            -lock=false `
            -var-file=$TfvarsFullPath `
            -out=$PlanFullPath `
            -no-color 2>&1
    )
    $PlanExitCode = $LASTEXITCODE

    if ($PlanExitCode -ne 0) {
        $PlanOutput |
            Select-Object -Last 80 |
            ForEach-Object { Write-Host $_ }
        throw "FOUNDATION_PLAN_FAILED"
    }

    if (-not (Test-Path -LiteralPath $PlanFullPath -PathType Leaf)) {
        throw "FOUNDATION_PLAN_NOT_CREATED"
    }

    $PlanJsonText = (& $TerraformExe show -json $PlanFullPath) -join "`n"
    Assert-LastExitCode "TERRAFORM_SHOW_FAILED"
    $PlanObject = $PlanJsonText | ConvertFrom-Json

    $Changes = @(
        foreach ($Change in @($PlanObject.resource_changes)) {
            if ([string]$Change.mode -ne "managed") {
                continue
            }

            [PSCustomObject]@{
                Address   = [string]$Change.address
                Type      = [string]$Change.type
                Actions   = (@($Change.change.actions) -join ",")
                RawChange = $Change
            }
        }
    )

    $ExpectedAddresses = @(
        "aws_iam_role.terraform_plan"
        "aws_iam_role_policy.terraform_state_access"
        "aws_iam_role_policy_attachment.terraform_plan_read_only"
        "aws_s3_bucket.terraform_state"
        "aws_s3_bucket_ownership_controls.terraform_state"
        "aws_s3_bucket_policy.terraform_state"
        "aws_s3_bucket_public_access_block.terraform_state"
        "aws_s3_bucket_server_side_encryption_configuration.terraform_state"
        "aws_s3_bucket_versioning.terraform_state"
    )

    if ($OidcProviderMode -eq "create") {
        $ExpectedAddresses += "aws_iam_openid_connect_provider.github_actions[0]"
    }

    $ExpectedSorted = @($ExpectedAddresses | Sort-Object)
    $ActualSorted = @($Changes | ForEach-Object { [string]$_.Address } | Sort-Object)
    $AddressDifference = @(Compare-Object -ReferenceObject $ExpectedSorted -DifferenceObject $ActualSorted)

    if ($AddressDifference.Count -gt 0) {
        $AddressDifference | Format-Table -AutoSize
        throw "FOUNDATION_RESOURCE_SET_MISMATCH"
    }

    $DangerousChanges = @(
        $Changes | Where-Object { $_.Actions -match "delete|update" }
    )
    if ($DangerousChanges.Count -gt 0) {
        $DangerousChanges |
            Select-Object Address, Type, Actions |
            Format-Table -AutoSize
        throw "DANGEROUS_FOUNDATION_CHANGE_FOUND"
    }

    $NonCreateChanges = @(
        $Changes | Where-Object { $_.Actions -ne "create" }
    )
    if ($NonCreateChanges.Count -gt 0) {
        $NonCreateChanges |
            Select-Object Address, Type, Actions |
            Format-Table -AutoSize
        throw "NON_CREATE_FOUNDATION_ACTION_FOUND"
    }

    $RoleChange = ($Changes | Where-Object { $_.Address -eq "aws_iam_role.terraform_plan" }).RawChange
    $AttachmentChange = ($Changes | Where-Object { $_.Address -eq "aws_iam_role_policy_attachment.terraform_plan_read_only" }).RawChange
    $BucketChange = ($Changes | Where-Object { $_.Address -eq "aws_s3_bucket.terraform_state" }).RawChange
    $PublicAccessChange = ($Changes | Where-Object { $_.Address -eq "aws_s3_bucket_public_access_block.terraform_state" }).RawChange
    $VersioningChange = ($Changes | Where-Object { $_.Address -eq "aws_s3_bucket_versioning.terraform_state" }).RawChange
    $EncryptionChange = ($Changes | Where-Object { $_.Address -eq "aws_s3_bucket_server_side_encryption_configuration.terraform_state" }).RawChange

    $ExpectedAccountId = [string]$PlanObject.variables.expected_aws_account_id.value
    $AwsRegion = [string]$PlanObject.variables.aws_region.value
    $StatePrefix = [string]$PlanObject.variables.state_prefix.value
    $ExpectedBucketName = "terraformers-modernization-$ExpectedAccountId-apne2-state"
    $ExpectedOidcSubject = "repo:siamese-lang/Terraformers-modernization:environment:aws-live-plan"
    $AssumeRolePolicy = [string]$RoleChange.change.after.assume_role_policy
    $EncryptionAlgorithm = [string]$EncryptionChange.change.after.rule[0].apply_server_side_encryption_by_default[0].sse_algorithm

    $SecurityChecks = [ordered]@{
        ExpectedAccountIdValid = $ExpectedAccountId -match "^[0-9]{12}$"
        AwsRegionExact         = $AwsRegion -eq "ap-northeast-2"
        StatePrefixExact       = $StatePrefix -eq "terraformers-modernization/dev"
        StateBucketNameExact   = [string]$BucketChange.change.after.bucket -eq $ExpectedBucketName
        OidcSubjectExact       = $AssumeRolePolicy.Contains($ExpectedOidcSubject)
        OidcAudienceExact      = $AssumeRolePolicy.Contains("sts.amazonaws.com")
        OidcProviderExact      = $AssumeRolePolicy.Contains("oidc-provider/token.actions.githubusercontent.com")
        ReadOnlyPolicyExact    = [string]$AttachmentChange.change.after.policy_arn -eq "arn:aws:iam::aws:policy/ReadOnlyAccess"
        ForceDestroyDisabled   = $BucketChange.change.after.force_destroy -eq $false
        PublicAccessBlocked    = (
            $PublicAccessChange.change.after.block_public_acls -eq $true -and
            $PublicAccessChange.change.after.block_public_policy -eq $true -and
            $PublicAccessChange.change.after.ignore_public_acls -eq $true -and
            $PublicAccessChange.change.after.restrict_public_buckets -eq $true
        )
        VersioningEnabled      = [string]$VersioningChange.change.after.versioning_configuration[0].status -eq "Enabled"
        EncryptionEnabled      = $EncryptionAlgorithm -eq "AES256"
    }

    $FailedSecurityChecks = @(
        $SecurityChecks.GetEnumerator() | Where-Object { $_.Value -ne $true }
    )
    if ($FailedSecurityChecks.Count -gt 0) {
        $FailedSecurityChecks | Format-Table Key, Value -AutoSize
        throw "FOUNDATION_SECURITY_CHECK_FAILED"
    }

    Write-Host "`n[foundation managed resource changes]"
    $Changes |
        Select-Object Address, Type, Actions |
        Sort-Object Address |
        Format-Table -AutoSize

    [PSCustomObject]@{
        FoundationPlanStatus    = "apply-review-ready"
        RepositoryHead          = $CurrentHead.Substring(0, 12)
        TerraformVersion        = "1.15.8"
        AwsProviderVersion      = "5.100.0"
        TlsProviderVersion      = "4.3.0"
        CreateCount             = @($Changes | Where-Object { $_.Actions -eq "create" }).Count
        ExpectedCreateCount     = $ExpectedAddresses.Count
        OidcProviderMode        = $OidcProviderMode
        ExpectedAccountIdValid  = $SecurityChecks.ExpectedAccountIdValid
        AwsRegionExact          = $SecurityChecks.AwsRegionExact
        StatePrefixExact        = $SecurityChecks.StatePrefixExact
        StateBucketNameExact    = $SecurityChecks.StateBucketNameExact
        OidcSubjectExact        = $SecurityChecks.OidcSubjectExact
        OidcAudienceExact       = $SecurityChecks.OidcAudienceExact
        OidcProviderExact       = $SecurityChecks.OidcProviderExact
        ReadOnlyPolicyExact     = $SecurityChecks.ReadOnlyPolicyExact
        ForceDestroyDisabled    = $SecurityChecks.ForceDestroyDisabled
        PublicAccessBlocked     = $SecurityChecks.PublicAccessBlocked
        VersioningEnabled       = $SecurityChecks.VersioningEnabled
        EncryptionEnabled       = $SecurityChecks.EncryptionEnabled
        DeleteCount             = $DangerousChanges.Count
        TerraformApplyExecuted  = $false
        AwsResourceMutation     = "none"
        PrivateTfvarsUploaded   = $false
        RawPlanUploaded         = $false
    } | Format-List

    $FinalWorkingTreeChanges = @(& git -C $RepoRoot status --porcelain)
    Assert-LastExitCode "FINAL_GIT_STATUS_FAILED"
    if ($FinalWorkingTreeChanges.Count -gt 0) {
        $FinalWorkingTreeChanges | ForEach-Object { Write-Host $_ }
        throw "WORKING_TREE_CHANGED_DURING_PLAN"
    }
}
finally {
    Pop-Location
    $env:TF_IN_AUTOMATION = $PreviousAutomationValue
}
