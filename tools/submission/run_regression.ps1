param(
 [string]$SimBin='F:\anlu\modelsim_ase\win32aloem',
 [string]$OutputRoot=(Join-Path $PSScriptRoot 'test_results')
)
$ErrorActionPreference='Stop'
foreach($exe in @('vlib.exe','vlog.exe','vsim.exe')){if(!(Test-Path -LiteralPath (Join-Path $SimBin $exe))){throw "Missing ModelSim executable: $SimBin\$exe"}}
$root=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$benches=Join-Path $root 'tools\timing_20261031'
$rtl=Join-Path $root 'src\user_source\hdl_source'
$out=Join-Path ([IO.Path]::GetFullPath($OutputRoot)) (Get-Date -Format 'yyyyMMdd_HHmmss_fff')
New-Item -ItemType Directory -Path $out -ErrorAction Stop | Out-Null
$results=New-Object System.Collections.Generic.List[object]
function Invoke-Checked([string]$Exe,[string[]]$Arguments,[string]$Log,[bool]$RequirePass=$false){
 & $Exe @Arguments *> $Log
 $exit=$LASTEXITCODE
 $text=Get-Content -LiteralPath $Log -Raw
 if($exit -ne 0 -or $text -match '\*\*\s+(Fatal|Error)(\s*:|\s*\()' -or $text -match 'Errors:\s*[1-9]' -or ($RequirePass -and $text -notmatch '(?m)^#?\s*PASS')){
  throw "Regression failed: $Log"
 }
}
function Run-Case([string]$Lib,[string]$Test,[string]$Name,[string]$Plus=''){
 $args=@('-c','-suppress','3015','-lib',$Lib,$Test)
 if($Plus){$args+=$Plus}
 $args+=@('-do','onerror {quit -code 1}; run -all; quit -code 0')
 $log=Join-Path $out "$Name.log"
 Invoke-Checked (Join-Path $SimBin 'vsim.exe') $args $log $true
 $results.Add([pscustomobject]@{name=$Name;result='PASS';log="$Name.log";sha256=(Get-FileHash -LiteralPath $log -Algorithm SHA256).Hash})
 Write-Output "PASS $Name"
}
Push-Location $out
try{
 Invoke-Checked (Join-Path $SimBin 'vlib.exe') @('bmp_work') (Join-Path $out 'vlib_bmp.log')
 $sources=@('SD\bmp_read_fat32.v','SD\sd_card_single_bmp.v','subtitle_sync.v') | ForEach-Object {Join-Path $rtl $_}
 $tests=@('tb_bmp_directory.v','tb_bmp_scaler.v','tb_bmp_error_status_20261028.v','tb_subtitle_resume.v','tb_subtitle_bottom_layout.v') | ForEach-Object {Join-Path $benches $_}
 Invoke-Checked (Join-Path $SimBin 'vlog.exe') (@('-work','bmp_work')+$sources+$tests) (Join-Path $out 'compile_bmp.log')
 foreach($test in @('tb_bmp_directory','tb_bmp_scaler','tb_bmp_error_status_20261028','tb_subtitle_resume','tb_subtitle_bottom_layout')){Run-Case 'bmp_work' $test $test}
 Invoke-Checked (Join-Path $SimBin 'vlib.exe') @('media_work') (Join-Path $out 'vlib_media.log')
 $sources=@('top_tf_hdmi_audio.v','SD\wav_read_fat32.v','SD\video_read_fat32.v','subtitle_sync.v','video_osd_effects.v','I2S_receiver.v') | ForEach-Object {Join-Path $rtl $_}
 $tests=@('media_peripheral_stubs.v','tb_four_state_keys.v','tb_wav_resume.v','tb_audio_bookmarks.v','tb_media_presentation.v','tb_audio_pause.v','tb_runtime_volume.v','tb_video_read_fat32.v','tb_media_ack_cdc.v') | ForEach-Object {Join-Path $benches $_}
 Invoke-Checked (Join-Path $SimBin 'vlog.exe') (@('-work','media_work')+$sources+$tests) (Join-Path $out 'compile_media.log')
 foreach($test in @('tb_four_state_keys','tb_wav_resume','tb_audio_bookmarks','tb_media_presentation','tb_audio_pause','tb_runtime_volume','tb_media_ack_cdc')){Run-Case 'media_work' $test $test}
 foreach($case in 0..12){Run-Case 'media_work' 'tb_video_read_fat32' "video_case_$case" "+CASE=$case"}
 if($results.Count -ne 25){throw 'Unexpected case count'}
 $results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $out 'results.json') -Encoding UTF8
 Write-Output "PASS all 25 cases. Logs: $out"
}finally{Pop-Location}
