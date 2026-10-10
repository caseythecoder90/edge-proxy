<#
    export-citrix-ca.ps1

    Run this in WINDOWS, before you wipe it.

    Connects to your Citrix StoreFront URL, reads the TLS certificate chain the
    server actually presents, and writes every certificate in that chain to a
    separate PEM file. You then copy the non-leaf ones onto Fedora, into
    Citrix's own trust store, which is what prevents "SSL error 61".

    Why pull it from the server instead of browsing the Windows certificate
    store: the store holds ~50 root CAs and you'd be guessing which is yours.
    The chain the server presents is, by definition, the right one.

    Usage:
      powershell -ExecutionPolicy Bypass -File .\export-citrix-ca.ps1 `
          -StoreFrontUrl https://vdi.company.com

      powershell -ExecutionPolicy Bypass -File .\export-citrix-ca.ps1 `
          -StoreFrontUrl vdi.company.com -OutDir E:\thinkpad-backup\certs

    IMPORTANT: run it from the same network you'll use the VDI from. If your
    employer does TLS inspection, the chain differs between the office network
    and your home connection, and you want the one you'll actually meet.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $StoreFrontUrl,

    [string] $OutDir = "$env:USERPROFILE\Desktop\citrix-certs",

    [int] $Port = 443
)

$ErrorActionPreference = 'Stop'

# Accept a full URL, a bare hostname, or host:port
$targetHost = $StoreFrontUrl -replace '^[A-Za-z][A-Za-z0-9+.-]*://', '' -replace '/.*$', ''
if ($targetHost -match '^(.+):(\d+)$') {
    $targetHost = $Matches[1]
    $Port       = [int] $Matches[2]
}

Write-Host ""
Write-Host "Target : $targetHost`:$Port"
Write-Host "Output : $OutDir"
Write-Host ""

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$tcp  = $null
$ssl  = $null
$leaf = $null

try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcp.Connect($targetHost, $Port)

    # Accept any certificate: we are inspecting the chain, not trusting it.
    $acceptAll = [System.Net.Security.RemoteCertificateValidationCallback] {
        param($sender, $certificate, $chain, $sslPolicyErrors) $true
    }

    $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false, $acceptAll)
    $ssl.AuthenticateAsClient($targetHost)

    $leaf = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(
        $ssl.RemoteCertificate)
}
catch {
    Write-Host "FAILED: could not complete a TLS handshake with $targetHost`:$Port" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)"
    Write-Host ""
    Write-Host "Check the hostname, and check you're on a network that can reach it"
    Write-Host "(you may need to be on the corporate VPN first)."
    exit 1
}
finally {
    if ($ssl) { $ssl.Dispose() }
    if ($tcp) { $tcp.Close() }
}

# Build the full chain locally so we also capture the root, which servers
# frequently do not send.
$chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
$chain.ChainPolicy.RevocationMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
$chain.ChainPolicy.VerificationFlags = [System.Security.Cryptography.X509Certificates.X509VerificationFlags]::AllFlags
$null = $chain.Build($leaf)

if ($chain.ChainElements.Count -eq 0) {
    Write-Host "FAILED: no chain could be built from the server certificate." -ForegroundColor Red
    exit 1
}

$written = @()
$depth   = 0

foreach ($element in $chain.ChainElements) {
    $cert       = $element.Certificate
    $selfSigned = ($cert.Subject -eq $cert.Issuer)

    if ($depth -eq 0)      { $role = 'LEAF (server cert - do NOT copy this one)' }
    elseif ($selfSigned)   { $role = 'ROOT CA  <-- copy this one' }
    else                   { $role = 'INTERMEDIATE CA  <-- copy this one too' }

    # Common name, cleaned up for use in a filename
    $cn = 'cert'
    if ($cert.Subject -match 'CN=([^,]+)') { $cn = $Matches[1].Trim() }
    $cn = ($cn -replace '[^A-Za-z0-9]+', '-').Trim('-')
    if ($cn.Length -gt 48) { $cn = $cn.Substring(0, 48) }
    if (-not $cn)          { $cn = 'cert' }

    $fileName = '{0:D2}-{1}.pem' -f $depth, $cn
    $filePath = Join-Path $OutDir $fileName

    $b64 = [Convert]::ToBase64String(
        $cert.RawData,
        [System.Base64FormattingOptions]::InsertLineBreaks)

    $pem = "-----BEGIN CERTIFICATE-----`n" + $b64 + "`n-----END CERTIFICATE-----`n"

    # ASCII, LF endings, no BOM - OpenSSL and ctx_rehash want a clean PEM
    [System.IO.File]::WriteAllText($filePath, ($pem -replace "`r`n", "`n"),
        (New-Object System.Text.ASCIIEncoding))

    Write-Host ("[{0}] {1}" -f $depth, $role) -ForegroundColor Cyan
    Write-Host ("      subject    : {0}" -f $cert.Subject)
    Write-Host ("      issuer     : {0}" -f $cert.Issuer)
    Write-Host ("      expires    : {0:yyyy-MM-dd}" -f $cert.NotAfter)
    Write-Host ("      thumbprint : {0}" -f $cert.Thumbprint)
    Write-Host ("      written    : {0}" -f $fileName)
    Write-Host ""

    if ($depth -gt 0) { $written += $fileName }
    $depth++
}

# Any chain problems are informational here - they often explain the behaviour
# you'll see on Linux.
if ($chain.ChainStatus.Count -gt 0) {
    Write-Host "Chain status notes:" -ForegroundColor Yellow
    foreach ($s in $chain.ChainStatus) {
        Write-Host ("  {0}: {1}" -f $s.Status, $s.StatusInformation.Trim())
    }
    Write-Host ""
}

Write-Host "Done. Copy these onto Fedora:" -ForegroundColor Green
foreach ($f in $written) { Write-Host "  $f" }
Write-Host ""
Write-Host "On Fedora, as separate files (NOT concatenated into one bundle -"
Write-Host "ctx_rehash only indexes the first certificate in a file):"
Write-Host ""
Write-Host "  sudo cp *.pem /opt/Citrix/ICAClient/keystore/cacerts/"
Write-Host "  sudo /opt/Citrix/ICAClient/util/ctx_rehash"
Write-Host ""
Write-Host "Then keep a second copy somewhere that is not this laptop."
Write-Host ""
