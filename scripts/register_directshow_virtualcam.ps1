# DirectShow and Media Foundation use distinct CLSIDs and are installed together.
& (Join-Path $PSScriptRoot 'install_virtual_camera.ps1') @args
exit $LASTEXITCODE
