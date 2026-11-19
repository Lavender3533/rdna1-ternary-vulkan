@echo off
rem Generation benchmark with the same memory settings as chat.cmd.
set LLAMA_BIN=C:\path\to\llama.cpp\build\bin\Release
set MODEL=C:\path\to\Ternary-Bonsai-2-27B-PTQ1_0.gguf

set GGML_VK_SUBALLOCATION_BLOCK_SIZE=4194304
set GGML_VK_DISABLE_HOST_VISIBLE_VIDMEM=1
set GGML_VK_ENABLE_MEMORY_PRIORITY=1

"%LLAMA_BIN%\llama-bench.exe" -m "%MODEL%" -ngl 99 -fa 1 -ub 256 -p 0 -n 128 -r 3 -ctk q8_0 -ctv q8_0
