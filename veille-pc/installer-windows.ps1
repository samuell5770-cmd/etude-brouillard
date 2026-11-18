# Installation automatique de la telecommande veille / reveil (Windows 10/11).
# A lancer dans PowerShell ouvert EN ADMINISTRATEUR :
#   irm https://raw.githubusercontent.com/samuell5770-cmd/etude-brouillard/ccr-2ade3536-f4unvy/veille-pc/installer-windows.ps1 | iex

$ErrorActionPreference = 'Stop'
$Base    = 'https://raw.githubusercontent.com/samuell5770-cmd/etude-brouillard/ccr-2ade3536-f4unvy/veille-pc'
$Dossier = 'C:\veille-pc'
$Port    = 8765

function Etape($t) { Write-Host "`n==> $t" -ForegroundColor Cyan }
function Ok($t)    { Write-Host "    OK  $t" -ForegroundColor Green }
function Alerte($t){ Write-Host "    !!  $t" -ForegroundColor Yellow }

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Write-Host "Ouvre PowerShell EN ADMINISTRATEUR (clic droit sur Demarrer > Terminal (admin)) puis recolle la commande." -ForegroundColor Red
    return
}

# ------------------------------------------------------------------ 1. Python
Etape "Python"
function Trouver-Pythonw {
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
    $c = Get-Command pythonw.exe -All -ErrorAction SilentlyContinue | Where-Object { $_.Source -notmatch 'WindowsApps' } | Select-Object -First 1
    if ($c) { return $c.Source }
    $c = Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python3*\pythonw.exe", "$env:ProgramFiles\Python3*\pythonw.exe" -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
    if ($c) { return $c.FullName }
    return $null
}
$pythonw = Trouver-Pythonw
if (-not $pythonw) {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "    Installation de Python via winget..."
        winget install -e --id Python.Python.3.12 --silent --accept-package-agreements --accept-source-agreements | Out-Null
    }
    $pythonw = Trouver-Pythonw
    if (-not $pythonw) {
        Write-Host "    Telechargement de Python depuis python.org..."
        $exe = "$env:TEMP\python-installer.exe"
        Invoke-WebRequest 'https://www.python.org/ftp/python/3.12.8/python-3.12.8-amd64.exe' -OutFile $exe
        Start-Process $exe -ArgumentList '/quiet','InstallAllUsers=1','PrependPath=1','Include_test=0' -Wait
        $pythonw = Trouver-Pythonw
    }
}
if (-not $pythonw) { throw "Python n'a pas pu etre installe. Installe-le depuis python.org puis relance." }
Ok $pythonw

# ------------------------------------------------------------------ 2. Fichiers
Etape "Telechargement des fichiers dans $Dossier"
New-Item -ItemType Directory -Force -Path $Dossier | Out-Null
foreach ($f in 'serveur_veille.py','reveiller.py','README.md') {
    Invoke-WebRequest "$Base/$f" -OutFile (Join-Path $Dossier $f) -UseBasicParsing
}
Ok "fichiers telecharges"

# ------------------------------------------------------------------ 3. Carte reseau
Etape "Carte reseau et Wake-on-LAN"
$route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1
$carte = if ($route) { Get-NetAdapter -InterfaceIndex $route.InterfaceIndex } else { Get-NetAdapter -Physical | Where-Object Status -eq 'Up' | Select-Object -First 1 }
$mac   = ($carte.MacAddress -replace '-',':')
$ipObj = Get-NetIPAddress -InterfaceIndex $carte.ifIndex -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '169.254*' } | Select-Object -First 1
$ip    = $ipObj.IPAddress
# adresse de diffusion
$ipB   = [Net.IPAddress]::Parse($ip).GetAddressBytes()
$masque = [uint32]([math]::Pow(2,32) - [math]::Pow(2, 32 - $ipObj.PrefixLength))
$mB    = [BitConverter]::GetBytes($masque); [Array]::Reverse($mB)
$broadcast = (0..3 | ForEach-Object { $ipB[$_] -bor (255 -bxor $mB[$_]) }) -join '.'
Ok "carte : $($carte.Name) ($($carte.InterfaceDescription))"
Ok "IP : $ip   MAC : $mac   diffusion : $broadcast"
$wifi = $carte.PhysicalMediaType -match '802\.11' -or $carte.InterfaceDescription -match 'Wi-?Fi|Wireless'
if ($wifi) { Alerte "Le PC est en Wi-Fi : le reveil Wake-on-LAN risque de ne pas marcher. Branche un cable Ethernet si possible." }

foreach ($a in Get-NetAdapter -Physical | Where-Object Status -eq 'Up') {
    try { Set-NetAdapterPowerManagement -Name $a.Name -WakeOnMagicPacket Enabled -ErrorAction Stop; Ok "$($a.Name) : reveil par paquet magique active" } catch { Alerte "$($a.Name) : reglage 'WakeOnMagicPacket' non supporte" }
    try { Set-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword '*WakeOnMagicPacket' -RegistryValue 1 -NoRestart -ErrorAction Stop } catch { }
    try { powercfg /deviceenablewake "$($a.InterfaceDescription)" 2>$null | Out-Null } catch { }
}

# ------------------------------------------------------------------ 4. Veille (pas hibernation)
Etape "Mode veille"
powercfg /hibernate off
Ok "hibernation desactivee (le bouton fera une vraie mise en veille)"

# ------------------------------------------------------------------ 5. Pare-feu + profil reseau
Etape "Pare-feu"
$profil = Get-NetConnectionProfile -InterfaceIndex $carte.ifIndex -ErrorAction SilentlyContinue
if ($profil -and $profil.NetworkCategory -eq 'Public') {
    Set-NetConnectionProfile -InterfaceIndex $carte.ifIndex -NetworkCategory Private
    Alerte "Reseau '$($profil.Name)' passe de Public a Prive (necessaire pour que le telephone joigne le PC)."
}
Get-NetFirewallRule -DisplayName 'Veille PC (telecommande)' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule -DisplayName 'Veille PC (telecommande)' -Direction Inbound -Protocol TCP -LocalPort $Port -Profile Private -Action Allow | Out-Null
Ok "port $Port ouvert sur le reseau prive uniquement"

# ------------------------------------------------------------------ 6. Demarrage automatique
Etape "Demarrage automatique"
$cfgFile = Join-Path $Dossier 'veille-config.json'
$cfg = if (Test-Path $cfgFile) { Get-Content $cfgFile -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
$cfg | Add-Member -NotePropertyName mac  -NotePropertyValue $mac  -Force
$cfg | Add-Member -NotePropertyName port -NotePropertyValue $Port -Force
[IO.File]::WriteAllText($cfgFile, ($cfg | ConvertTo-Json), (New-Object Text.UTF8Encoding $false))

Get-CimInstance Win32_Process -Filter "Name='pythonw.exe' OR Name='python.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'serveur_veille' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
$utilisateur = "$env:USERDOMAIN\$env:USERNAME"
$action   = New-ScheduledTaskAction -Execute $pythonw -Argument "`"$Dossier\serveur_veille.py`"" -WorkingDirectory $Dossier
$trigger  = New-ScheduledTaskTrigger -AtLogOn -User $utilisateur
$reglages = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0 -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
$principal = New-ScheduledTaskPrincipal -UserId $utilisateur -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName 'Veille PC telecommande' -Action $action -Trigger $trigger -Settings $reglages -Principal $principal -Force | Out-Null
Start-ScheduledTask -TaskName 'Veille PC telecommande'
Ok "lance maintenant et a chaque ouverture de session"

# ------------------------------------------------------------------ 7. Verification + lien
Etape "Verification"
$cle = $null
for ($i = 0; $i -lt 20 -and -not $cle; $i++) {
    Start-Sleep -Milliseconds 500
    try { $cle = (Get-Content $cfgFile -Raw | ConvertFrom-Json).cle } catch { }
}
$lien = "http://${ip}:$Port/?k=$cle"
try {
    $r = Invoke-RestMethod "http://127.0.0.1:$Port/etat" -Headers @{ 'X-Cle' = $cle } -TimeoutSec 5
    if ($r.ok) { Ok "le serveur repond" }
} catch { Alerte "le serveur ne repond pas encore : redemarre le PC puis ouvre le lien." }

$recap = @"
TELECOMMANDE VEILLE PC
======================
1) BOUTON VEILLE - ouvre ce lien sur ton telephone (meme Wi-Fi) puis
   'Ajouter a l'ecran d'accueil' :
   $lien

2) BOUTON REVEIL - dans une app 'Wake on LAN' du telephone, cree un appareil :
   Adresse MAC        : $mac
   Adresse diffusion  : $broadcast
   Port               : 9

3) A FAIRE UNE FOIS dans le BIOS (redemarrer, touche Suppr ou F2) :
   activer 'Wake on LAN' / 'Power On by PCI-E' / 'Resume by LAN'.

Lien prive : il contient ta cle. Ne le partage pas.
"@
$fichierRecap = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Telecommande-veille.txt'
Set-Content -Path $fichierRecap -Value $recap -Encoding UTF8
Write-Host "`n$recap" -ForegroundColor White
Write-Host "Ce recapitulatif est aussi sur ton Bureau : Telecommande-veille.txt" -ForegroundColor Green

# Ouvre le lien dans un QR code local pour le scanner avec le telephone (aucune donnee envoyee en ligne)
$qrPage = Join-Path $Dossier 'lien-telephone.html'
$html = @"
<!doctype html><meta charset="utf-8"><title>Lien telephone</title>
<body style="font-family:sans-serif;text-align:center;padding:30px">
<h2>Scanne avec l'appareil photo du telephone</h2><div id="q" style="display:inline-block"></div>
<p style="word-break:break-all">$lien</p>
<script src="https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js"></script>
<script>new QRCode(document.getElementById('q'),{text:'$lien',width:280,height:280});</script></body>
"@
Set-Content -Path $qrPage -Value $html -Encoding UTF8
Start-Process $qrPage
