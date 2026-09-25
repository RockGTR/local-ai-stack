[CmdletBinding()]
param(
    [string]$InterfaceAlias = 'vEthernet (WSL (Hyper-V firewall))',
    [int]$ListenPort = 11501,
    [string]$TargetHost = '127.0.0.1',
    [int]$TargetPort = 11500
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Net;
using System.Net.Sockets;
using System.Threading.Tasks;

public sealed class LocalLlamaBridge
{
    private readonly TcpListener listener;
    private readonly string targetHost;
    private readonly int targetPort;

    public LocalLlamaBridge(string bindAddress, int listenPort, string targetHost, int targetPort)
    {
        listener = new TcpListener(IPAddress.Parse(bindAddress), listenPort);
        this.targetHost = targetHost;
        this.targetPort = targetPort;
    }

    public void Start()
    {
        listener.Start();
        AcceptLoopAsync();
    }

    public void Stop()
    {
        listener.Stop();
    }

    private async void AcceptLoopAsync()
    {
        while (true)
        {
            TcpClient client;
            try { client = await listener.AcceptTcpClientAsync(); }
            catch (ObjectDisposedException) { return; }
            catch (SocketException) { return; }
            ForwardAsync(client);
        }
    }

    private async void ForwardAsync(TcpClient client)
    {
        using (client)
        using (var upstream = new TcpClient())
        {
            try
            {
                await upstream.ConnectAsync(targetHost, targetPort);
                var clientStream = client.GetStream();
                var upstreamStream = upstream.GetStream();
                var request = clientStream.CopyToAsync(upstreamStream);
                var response = upstreamStream.CopyToAsync(clientStream);
                await Task.WhenAny(request, response);
            }
            catch (SocketException) { }
            catch (System.IO.IOException) { }
        }
    }
}
'@

while ($true) {
    $address = Get-NetIPAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty IPAddress
    if (-not $address) {
        Start-Sleep -Seconds 5
        continue
    }

    $existing = Get-NetTCPConnection -LocalAddress $address -LocalPort $ListenPort -State Listen -ErrorAction SilentlyContinue
    if ($existing) { exit 0 }

    try {
        $bridge = [LocalLlamaBridge]::new($address, $ListenPort, $TargetHost, $TargetPort)
        $bridge.Start()
        while ($true) {
            Start-Sleep -Seconds 5
            $currentAddress = Get-NetIPAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Select-Object -First 1 -ExpandProperty IPAddress
            if ($currentAddress -ne $address) { break }
        }
        $bridge.Stop()
    }
    catch {
        Write-Warning $_
        Start-Sleep -Seconds 5
    }
}
