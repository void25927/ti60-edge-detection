# Convert the actual RTL simulation's binary PPM into a PNG for visual QA.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.IO;
public static class VisionPpm {
    public static byte[] Pixels(string source) {
        byte[] raw=File.ReadAllBytes(source);
        int p=0,lines=0;
        while(lines<3 && p<raw.Length) if(raw[p++]==10)lines++;
        int width=1920,height=1080;
        if(raw.Length-p!=width*height*3)throw new Exception("Invalid PPM size");
            byte[] pixels=new byte[width*height*3];
            for(int y=0;y<height;y++) for(int x=0;x<width;x++) {
                int a=p+3*(y*width+x), b=3*(y*width+x);
                pixels[b]=raw[a+2];pixels[b+1]=raw[a+1];pixels[b+2]=raw[a];
            }
            return pixels;
    }
}
'@
$projectRoot=Split-Path -Parent $PSScriptRoot
$source=Join-Path $PSScriptRoot 'modelsim_modern_ui\modern_ui.ppm'
$target=Join-Path $PSScriptRoot 'modelsim_modern_ui\modern_ui.png'
$image=[System.Drawing.Bitmap]::new(1920,1080,[System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$data=$image.LockBits([System.Drawing.Rectangle]::new(0,0,1920,1080),[System.Drawing.Imaging.ImageLockMode]::WriteOnly,[System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$pixels=[VisionPpm]::Pixels($source)
[System.Runtime.InteropServices.Marshal]::Copy($pixels,0,$data.Scan0,$pixels.Length)
$image.UnlockBits($data)
$image.Save($target,[System.Drawing.Imaging.ImageFormat]::Png)
$image.Dispose()
Write-Host $target
