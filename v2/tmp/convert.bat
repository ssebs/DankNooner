@echo off
rem Converts a Movie Maker AVI to MP4 (H.264 + AAC). Usage: convert.bat [input.avi]
setlocal
set "IN=%~1"
if "%IN%"=="" set "IN=%~dp0DankNoonerRecording.avi"
set "OUT=%~dpn1.mp4"
if "%~1"=="" set "OUT=%~dp0DankNoonerRecording.mp4"

ffmpeg -y -i "%IN%" -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -c:a aac -b:a 192k -movflags +faststart "%OUT%"
echo Wrote %OUT%
endlocal
