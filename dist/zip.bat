@echo off
REM used ChatGPT for this script, source is zip.sh
setlocal enabledelayedexpansion

REM Find all directories starting with "dank-nooner"
for /d %%D in (dank-nooner*) do (
    echo Found directory: %%D

    REM Navigate into the directory
    pushd %%D

    REM Create zip file in the parent directory
    powershell -command "Compress-Archive -Force -Path * -DestinationPath '..\%%D.zip'"

    REM Return to the original directory
    popd
)

endlocal
