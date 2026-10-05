# Generates cas/.env and alpos/klaw/.env from local-profile values already committed in the repos.
# Third-party credentials (OAuth, reCAPTCHA, AWS, SMS) are not available locally and get placeholders.
param(
  [string]$Root = (Resolve-Path "$PSScriptRoot\..\..").Path,
  [switch]$Force
)

function Read-Props([string]$path) {
  $map = @{}
  foreach ($line in Get-Content $path -Encoding UTF8) {
    if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
    $k, $v = $line -split '=', 2
    $map[$k.Trim()] = $v.Trim()
  }
  return $map
}

function New-Secret([int]$bytes) {
  $buf = New-Object byte[] $bytes
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($buf)
  return [Convert]::ToBase64String($buf).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Add-All($target, $source) {
  foreach ($e in $source.GetEnumerator()) { $target[$e.Key] = $e.Value }
}

function Write-EnvFile([string]$path, $values) {
  if ((Test-Path $path) -and -not $Force) { Write-Host "skip (exists): $path"; return }
  $lines = $values.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
  [IO.File]::WriteAllLines($path, [string[]]$lines, (New-Object Text.UTF8Encoding $false))
  Write-Host "written: $path ($($values.Count) vars)"
}

$oms  = Read-Props "$Root\alpos\oms\src\main\resources\application-local.properties"
$sys  = Read-Props "$Root\alpos\sys\src\main\resources\application.properties"
$arms = Read-Props (Get-ChildItem "$Root\alpos\arms\src\main\resources" -Recurse -Filter 'common-local.properties' | Select-Object -First 1).FullName

$db = [ordered]@{
  MAIN_DB_URL      = $oms['spring.datasource.main.jdbc-url']
  MAIN_DB_USERNAME = $oms['spring.datasource.main.username']
  MAIN_DB_PASSWORD = $oms['spring.datasource.main.password']
  LOG_DB_URL       = $oms['spring.datasource.log.jdbc-url']
  LOG_DB_USERNAME  = $oms['spring.datasource.log.username']
  LOG_DB_PASSWORD  = $oms['spring.datasource.log.password']
}
$ssl = [ordered]@{
  APP_SSL_KEY_STORE          = 'classpath:cert/mycas.jks'
  APP_SSL_KEY_STORE_TYPE     = 'JKS'
  APP_SSL_KEY_ALIAS          = 'mycas'
  APP_SSL_KEY_STORE_PASSWORD = $sys['server.ssl.key-store-password']
  APP_SSL_KEY_PASSWORD       = $sys['server.ssl.key-password']
}
$placeholder = 'local-unset'

$cas = [ordered]@{
  APP_ENV_CODE            = 'local'
  APP_LOG_DIR             = 'logs'
  APP_SERVER_PORT         = '9443'
  APP_SERVER_HTTP_ENABLED = 'false'
  CAS_SERVER_NAME         = 'https://localhost:8443'
}
Add-All $cas $db
Add-All $cas $ssl
Add-All $cas ([ordered]@{
  APP_REDIS_HOST                 = 'localhost'
  APP_REDIS_PORT                 = '6379'
  APP_REDIS_PROTOCOL_VERSION     = 'RESP2'
  APP_REDIS_DATABASE             = '1'
  APP_REDIS_SIGNING_KEY          = (New-Secret 64)
  APP_REDIS_ENCRYPTION_KEY       = (New-Secret 32)
  APP_TOKEN_SIGNING_KEY          = $arms['cas.authn.token.crypto.signing.key']
  APP_TOKEN_ENCRYPTION_KEY       = $arms['cas.authn.token.crypto.encryption.key']
  APP_QR_TOKEN_HMAC_SECRET       = (New-Secret 32)
  APP_LOGIN_SUCCESS_REDIRECT_URL = 'https://localhost:8443/sys'
  APP_SSO_REGISTER_URL           = 'http://localhost:3000/signup'
  APP_SSO_ACCOUNT_INFO_URL       = 'http://localhost:3000/SSO001'
  IS_LOCAL_SEND_OTP              = 'N'
  APP_OAUTH_GOOGLE_ID            = $placeholder
  APP_OAUTH_GOOGLE_SECRET        = $placeholder
  APP_OAUTH_MICROSOFT_ID         = $placeholder
  APP_OAUTH_MICROSOFT_SECRET     = $placeholder
  APP_RECAPTCHA_SECRET           = $placeholder
  APP_RECAPTCHA_SITE_KEY         = $placeholder
  APP_APPLE_KEY_ID               = $placeholder
  APP_APPLE_TEAM_ID              = $placeholder
  APP_APPLE_SERVICE_ID           = 'com.alp.webauth'
  APP_APPLE_PRIVATE_KEY_PATH     = $placeholder
  AWS_SES_ACCESS_KEY             = $placeholder
  AWS_SES_SECRET_KEY             = $placeholder
  AWS_SNS_ACCESS_KEY             = $placeholder
  AWS_SNS_SECRET_KEY             = $placeholder
  MITAKE_SMS_USERNAME            = $placeholder
  MITAKE_SMS_PASSWORD            = $placeholder
})

$klaw = [ordered]@{
  APP_ENV_CODE         = 'local'
  APP_SERVER_PORT      = '9444'
  APP_SERVER_HTTP_PORT = '0'
  APP_RECAPTCHA_SECRET = $placeholder
}
Add-All $klaw $db
Add-All $klaw $ssl

$missing = @($db.GetEnumerator()) + @($ssl.GetEnumerator()) | Where-Object { -not $_.Value } | ForEach-Object Key
if ($missing) { throw "Could not read from repo config: $($missing -join ', ')" }

Write-EnvFile "$Root\cas\.env" $cas
Write-EnvFile "$Root\alpos\klaw\.env" $klaw
