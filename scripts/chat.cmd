@echo off
rem Chat with Ternary-Bonsai-2-27B on an 8 GB RDNA1 card (RX 5700 / 5700 XT) under Windows.
rem Edit the two paths below.
set LLAMA_BIN=C:\path\to\llama.cpp\build\bin\Release
set MODEL=C:\path\to\Ternary-Bonsai-2-27B-PTQ1_0.gguf

rem Small allocation blocks keep Windows from demoting weights to system memory.
set GGML_VK_SUBALLOCATION_BLOCK_SIZE=4194304
set GGML_VK_DISABLE_HOST_VISIBLE_VIDMEM=1
set GGML_VK_ENABLE_MEMORY_PRIORITY=1

"%LLAMA_BIN%\llama-cli.exe" -m "%MODEL%" -ngl 99 -fa on -ub 256 -c 8192 -ctk q8_0 -ctv q8_0 --temp 0.6 --top-p 0.95 --top-k 20 %*
