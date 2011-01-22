@echo off
REM counterpart of p9p's "u" and "9" for Inferno
REM usage: cp i inferno/$HOST/$ARCH/bin/i & add to path

set HOST=Nt
set ARCH=386
set INFERNO=b:/r/inferno-os
set PATH=%INFERNO%/%HOST%/%ARCH%/bin;%PATH%

REM set XCFLAGS=
set MSVC=c:\ARCHIV~1\MICROS~4
set INCLUDE=%MSVC%\VC98\Include
set LIB=%MSVC%\VC98\Lib
set PATH=%PATH%;%MSVC%\VC98\Bin;%MSVC%\Common\MsDev98\Bin

%*
