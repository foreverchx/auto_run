# Probes each service through the Caddy proxy on https://localhost:8443.
# mycas is self-signed and usually not in the Windows trust store, so certificate errors are ignored here.
param([string[]]$Paths = @('/cas/login', '/klaw/actuator/health', '/sys/actuator/health', '/oms/actuator/health'))

Add-Type -TypeDefinition @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAll : ICertificatePolicy {
  public bool CheckValidationResult(ServicePoint sp, X509Certificate cert, WebRequest req, int problem) { return true; }
}
"@ -ErrorAction SilentlyContinue
[Net.ServicePointManager]::CertificatePolicy = New-Object TrustAll
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

foreach ($p in $Paths) {
  $url = "https://localhost:8443$p"
  $sw = [Diagnostics.Stopwatch]::StartNew()
  try {
    $req = [Net.HttpWebRequest]::Create($url)
    $req.Timeout = 30000
    $req.AllowAutoRedirect = $false
    $resp = $req.GetResponse()
    $code = [int]$resp.StatusCode
    $resp.Close()
  } catch [Net.WebException] {
    $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { $_.Exception.Status }
  }
  "{0,-28} {1,5}  {2,6:N0} ms" -f $p, $code, $sw.ElapsedMilliseconds
}
