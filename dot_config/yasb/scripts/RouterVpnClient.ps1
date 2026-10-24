# Native HTTPS transport for Windows PowerShell 5.1, with a per-request TLS pin.
Add-Type -AssemblyName System.Security
if (-not ('RouterVpnNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Globalization;
using System.IO;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
public sealed class RouterVpnReply { public int Code; public string Body; }
public static class RouterVpnNative {
    public static string Normalize(string raw) {
        if (raw == null || raw.Length > 4096 || Regex.IsMatch(raw, @"[\x00-\x1f\x7f\\]"))
            throw new ArgumentException("Введите один домен или HTTP(S)-ссылку.");
        raw = raw.Trim();
        if (Regex.IsMatch(raw, @"\s")) throw new ArgumentException("В ссылке не должно быть пробелов.");
        string value = Regex.IsMatch(raw, @"^[a-zA-Z][a-zA-Z0-9+.-]*://") ? raw : "https://"+raw.TrimStart('/');
        Uri uri;
        if (!Uri.TryCreate(value, UriKind.Absolute, out uri) ||
            (uri.Scheme != "http" && uri.Scheme != "https") || uri.UserInfo.Length > 0 ||
            Regex.IsMatch(value.Split(new string[]{"://"}, StringSplitOptions.None)[1].Split('/','?','#')[0], @"[@%]"))
            throw new ArgumentException("Нужен домен или HTTP(S)-ссылка без логина и пароля.");
        string host = new IdnMapping().GetAscii(uri.DnsSafeHost.TrimEnd('.')).ToLowerInvariant();
        IPAddress address;
        if (host.Length > 253 || IPAddress.TryParse(host, out address) ||
            !Regex.IsMatch(host, @"^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$" ) ||
            Regex.IsMatch(host, @"\.[0-9]+$"))
            throw new ArgumentException("Не удалось выделить корректный домен.");
        return host;
    }
    public static Task<RouterVpnReply> Request(string endpoint, string pin, string token, string method, string path, string json) {
        return Task.Run(() => Send(endpoint, pin, token, method, path, json));
    }
    private static RouterVpnReply Send(string endpoint, string pin, string token, string method, string path, string json) {
        if (endpoint != "https://192.168.1.132:8443" || !Regex.IsMatch(pin, @"^[a-fA-F0-9]{64}$") ||
            !Regex.IsMatch(token, @"^[a-zA-Z0-9_-]{64}$") ||
            !(method == "POST" && (path == "/api/client/domains" || path == "/api/client/domain-check") || method == "GET" && Regex.IsMatch(path, @"^/api/client/jobs/[a-f0-9]{32}$")))
            throw new InvalidOperationException("Некорректная привязка YASB или адрес запроса.");
        ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
        var req = (HttpWebRequest)WebRequest.Create(endpoint + path);
        req.Proxy = null; req.Method = method; req.AllowAutoRedirect = false;
        req.KeepAlive = false; req.Timeout = req.ReadWriteTimeout = 60000;
        req.Headers["Authorization"] = "Bearer " + token;
        req.ServerCertificateValidationCallback = (sender, certificate, chain, errors) => {
            if (certificate == null) return false;
            using (var sha = SHA256.Create()) {
                string actual = BitConverter.ToString(sha.ComputeHash(certificate.GetRawCertData())).Replace("-", "");
                return String.Equals(actual, pin, StringComparison.OrdinalIgnoreCase);
            }
        };
        if (method == "POST" && json != null) {
            byte[] body = Encoding.UTF8.GetBytes(json);
            req.ContentType = "application/json"; req.ContentLength = body.Length;
            using (Stream stream = req.GetRequestStream()) stream.Write(body, 0, body.Length);
        }
        HttpWebResponse response;
        try { response = (HttpWebResponse)req.GetResponse(); }
        catch (WebException error) {
            response = error.Response as HttpWebResponse;
            if (response == null) throw new IOException("Нет защищённого соединения с Pi-hole. Проверьте LAN/VPN и привязку сертификата.");
        }
        using (response)
        using (var reader = new StreamReader(response.GetResponseStream(), Encoding.UTF8)) {
            return new RouterVpnReply{Code=(int)response.StatusCode, Body=reader.ReadToEnd()};
        }
    }
}
'@
}
function Read-RouterVpnCredential {
    $path = Join-Path $env:APPDATA 'router-vpn-yasb\client.dpapi'
    if (-not (Test-Path -LiteralPath $path)) { throw 'YASB ещё не привязан к панели. Нужна установка отдельного клиентского ключа.' }
    $bytes = [Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($path), $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    try { return ([Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json) }
    finally { [Array]::Clear($bytes, 0, $bytes.Length) }
}
function Start-RouterVpnRequest {
    param($Credential, [string]$Method, [string]$Path, [string]$Body)
    return [RouterVpnNative]::Request($Credential.endpoint, $Credential.certificate_sha256, $Credential.token, $Method, $Path, $Body)
}
function Read-RouterVpnReply {
    param($Task)
    if ($Task.IsFaulted) { throw $Task.Exception.GetBaseException().Message }
    $reply = $Task.Result; $result = $reply.Body | ConvertFrom-Json
    if ($reply.Code -ne 200) { if ($result.error) { throw $result.error }; throw 'Панель отклонила запрос.' }
    return $result
}
