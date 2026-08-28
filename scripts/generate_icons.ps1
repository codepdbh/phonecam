Add-Type -AssemblyName System.Drawing

$srcPath = "c:\Users\Sistemas\Documents\webcam\icono.png"
if (-not (Test-Path $srcPath)) {
    Write-Error "icono.png not found at $srcPath"
    exit 1
}

$srcImg = [System.Drawing.Image]::FromFile($srcPath)

# 1. Android Mipmap icons (ic_launcher, ic_launcher_round, ic_launcher_foreground)
$androidRes = "c:\Users\Sistemas\Documents\webcam\apps\mobile\android\app\src\main\res"
$sizes = @(
    @{ Folder = "mipmap-mdpi"; Size = 48; FgSize = 108 },
    @{ Folder = "mipmap-hdpi"; Size = 72; FgSize = 162 },
    @{ Folder = "mipmap-xhdpi"; Size = 96; FgSize = 216 },
    @{ Folder = "mipmap-xxhdpi"; Size = 144; FgSize = 324 },
    @{ Folder = "mipmap-xxxhdpi"; Size = 192; FgSize = 432 }
)

foreach ($item in $sizes) {
    $folder = $item.Folder
    $size = $item.Size
    $fgSize = $item.FgSize
    $destDir = Join-Path $androidRes $folder
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
    
    # 1.1 ic_launcher.png
    $bmp = New-Object System.Drawing.Bitmap $size, $size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.DrawImage($srcImg, 0, 0, $size, $size)
    $g.Dispose()
    $bmp.Save((Join-Path $destDir "ic_launcher.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Save((Join-Path $destDir "ic_launcher_round.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()

    # 1.2 ic_launcher_foreground.png (for adaptive icons)
    $fgBmp = New-Object System.Drawing.Bitmap $fgSize, $fgSize
    $fgG = [System.Drawing.Graphics]::FromImage($fgBmp)
    $fgG.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $fgG.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $fgG.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    # Draw centered with padding
    $pad = [int]($fgSize * 0.15)
    $drawSize = $fgSize - ($pad * 2)
    $fgG.DrawImage($srcImg, $pad, $pad, $drawSize, $drawSize)
    $fgG.Dispose()
    $fgBmp.Save((Join-Path $destDir "ic_launcher_foreground.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $fgBmp.Dispose()

    Write-Host "[OK] Generated Android icon: $folder ($size x $size)" -ForegroundColor Green
}

# Remove any problematic mipmap-anydpi-v26 xml that causes legacy fallback
$anyDpiDir = Join-Path $androidRes "mipmap-anydpi-v26"
if (Test-Path $anyDpiDir) {
    Remove-Item -Recurse -Force $anyDpiDir
}

# 2. Windows Runner Icon (ICO generator supporting 256, 128, 64, 48, 32, 16)
$icoCode = @'
using System;
using System.IO;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Collections.Generic;

public class IcoGenerator {
    public static void CreateIco(string srcImagePath, string dstIcoPath) {
        using (var src = Image.FromFile(srcImagePath)) {
            int[] sizes = new int[] { 256, 128, 64, 48, 32, 16 };
            var pngBytesList = new List<byte[]>();

            foreach (int s in sizes) {
                using (var bmp = new Bitmap(s, s)) {
                    using (var g = Graphics.FromImage(bmp)) {
                        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                        g.SmoothingMode = SmoothingMode.HighQuality;
                        g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                        g.DrawImage(src, 0, 0, s, s);
                    }
                    using (var ms = new MemoryStream()) {
                        bmp.Save(ms, ImageFormat.Png);
                        pngBytesList.Add(ms.ToArray());
                    }
                }
            }

            using (var fs = new FileStream(dstIcoPath, FileMode.Create)) {
                using (var bw = new BinaryWriter(fs)) {
                    bw.Write((ushort)0); // Reserved
                    bw.Write((ushort)1); // Type = 1 (ICO)
                    bw.Write((ushort)sizes.Length); // Count

                    int offset = 6 + (16 * sizes.Length);

                    for (int i = 0; i < sizes.Length; i++) {
                        int s = sizes[i];
                        byte[] bytes = pngBytesList[i];
                        byte w = (s >= 256) ? (byte)0 : (byte)s;
                        byte h = (s >= 256) ? (byte)0 : (byte)s;

                        bw.Write(w);
                        bw.Write(h);
                        bw.Write((byte)0); // Color count
                        bw.Write((byte)0); // Reserved
                        bw.Write((ushort)1); // Planes
                        bw.Write((ushort)32); // BPP
                        bw.Write((uint)bytes.Length);
                        bw.Write((uint)offset);

                        offset += bytes.Length;
                    }

                    for (int i = 0; i < sizes.Length; i++) {
                        bw.Write(pngBytesList[i]);
                    }
                }
            }
        }
    }
}
'@

Add-Type -TypeDefinition $icoCode -ReferencedAssemblies System.Drawing

$icoDest = "c:\Users\Sistemas\Documents\webcam\apps\windows\windows\runner\resources\app_icon.ico"
[IcoGenerator]::CreateIco($srcPath, $icoDest)
Write-Host "[OK] Generated Windows ICO with multiple sizes: $icoDest" -ForegroundColor Green

# 3. Copy icono.png into apps/windows/assets/ and apps/mobile/assets/
$winAssets = "c:\Users\Sistemas\Documents\webcam\apps\windows\assets"
if (-not (Test-Path $winAssets)) { New-Item -ItemType Directory -Path $winAssets -Force | Out-Null }
Copy-Item $srcPath (Join-Path $winAssets "icono.png") -Force

$mobAssets = "c:\Users\Sistemas\Documents\webcam\apps\mobile\assets"
if (-not (Test-Path $mobAssets)) { New-Item -ItemType Directory -Path $mobAssets -Force | Out-Null }
Copy-Item $srcPath (Join-Path $mobAssets "icono.png") -Force

$srcImg.Dispose()
Write-Host "All icons generated and updated successfully!" -ForegroundColor Cyan
