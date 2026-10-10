@echo off
rem Converts a Movie Maker AVI to MP4 (H.265 10-bit NVENC + AAC). Usage: convert.bat [input.avi]
setlocal
set "IN=%~1"
if "%IN%"=="" set "IN=%~dp0DankNoonerRecording.avi"
set "OUT=%~dpn1.mp4"
if "%~1"=="" set "OUT=%~dp0DankNoonerRecording.mp4"

ffmpeg -y -i "%IN%" -vf "scale=in_range=pc:out_range=tv:in_color_matrix=bt601:out_color_matrix=bt709:flags=lanczos+accurate_rnd+full_chroma_int+full_chroma_inp,format=p010le,setparams=range=tv:colorspace=bt709:color_primaries=bt709:color_trc=bt709" -c:v hevc_nvenc -preset p7 -tune hq -rc vbr -cq 12 -b:v 0 -spatial-aq 1 -tag:v hvc1 -c:a aac -b:a 320k -movflags +faststart "%OUT%"
echo Wrote %OUT%
endlocal
