@echo off
if not exist "Release\NUL" mkdir Release
jwasm.exe -mz -nologo -Fl=Release\ -Sg -Fo=Release\ *.asm
