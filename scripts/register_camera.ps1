# Compatibility entry point. Machine-wide registration is required because the
# Windows Frame Server service activates the Media Foundation source.
& (Join-Path $PSScriptRoot 'install_virtual_camera.ps1') @args
exit $LASTEXITCODE
