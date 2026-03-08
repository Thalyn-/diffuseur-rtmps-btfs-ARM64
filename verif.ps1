$files = @(
    "scripts\diffuser.sh",
    "scripts\verifier-systeme.sh",
    "docs\GUIDE-RAPIDE-RTMP.md",
    "docs\NOUVELLES-OUTILS-DIAGNOSTIC.md",
    "docs\RESOLUTION-RTMP.md",
    "COMMENCER-ICI.md",
    "PROBLEME-RESOLUTION.txt"
)

foreach ($path in $files) {
    if (Test-Path $path) {
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $text  = [System.Text.Encoding]::UTF8.GetString($bytes)
        $crlf  = ([regex]::Matches($text, "\r\n")).Count
        if ($crlf -gt 0) {
            $fixed = $text -replace "`r`n", "`n"
            $out   = [System.Text.Encoding]::UTF8.GetBytes($fixed)
            [System.IO.File]::WriteAllBytes($path, $out)
            Write-Host "Converti (CRLF->LF) : $path ($crlf occurrences)" -ForegroundColor Green
        } else {
            Write-Host "Deja propre (LF)     : $path" -ForegroundColor Cyan
        }
    } else {
        Write-Host "Introuvable          : $path" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Verification finale :" -ForegroundColor White
foreach ($path in $files) {
    if (Test-Path $path) {
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $text  = [System.Text.Encoding]::UTF8.GetString($bytes)
        $crlf  = ([regex]::Matches($text, "\r\n")).Count
        $lines = ($text -split "`n").Count
        if ($crlf -eq 0) {
            Write-Host "  OK  $path ($lines lignes)" -ForegroundColor Green
        } else {
            Write-Host "  ERR $path -- $crlf CRLF restants !" -ForegroundColor Red
        }
    }
}
