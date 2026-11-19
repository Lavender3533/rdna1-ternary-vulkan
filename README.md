# rdna1-ternary-vulkan

Running a 27B ternary model (Ternary-Bonsai-2-27B, 1.75 bpw) at **15 tok/s on an 8 GB AMD RX 5700 XT** under Windows, with llama.cpp's Vulkan backend.

在 8GB 显存的 AMD RX 5700 XT（Windows、Vulkan）上，用 llama.cpp 以 **15 tok/s** 运行 27B 三值模型 Ternary-Bonsai-2-27B。中文说明见下半部分。

## Results

All numbers are measured on one machine: RX 5700 XT 8 GB (RDNA1, gfx1010, AMD proprietary driver, no integer dot product, no matrix cores), i5-12400F, 32 GB DDR4-3200, Windows 11.

| Setup | Generation |
| --- | --- |
| Qwen3.8-27B Q4_K_M, partial offload (`-ngl 24`) | 1.3 tok/s |
| Ternary-Bonsai-2-27B PTQ1_0, stock PrismML llama.cpp, default allocation blocks | 5.1–6.2 tok/s |
| patched kernel (16 rows), default 1 GiB allocation blocks | 4.9 tok/s |
| patched kernel at 2 rows per workgroup + 4 MiB allocation blocks | 11.7 tok/s |
| patched kernel (16 rows) + 4 MiB allocation blocks | **15.1–15.4 tok/s** |

With default allocation blocks about 2 GB of weights sat in system memory, so the kernel change only shows once the weights stay in VRAM (see the Windows section). The stock kernel with 4 MiB blocks was not measured.

Quality check: greedy output identical to the stock kernel on an English prompt; `test-backend-ops -o MUL_MAT -p type_a=ptq1_0` passes 168/168. 8K context with q8_0 KV cache keeps the same speed.

### Kernel micro-benchmark (`test-backend-ops perf`, PTQ1_0 × f32, weights resident in VRAM)

The stock kernel was measured with its original 2 rows per workgroup.

| m × k | tokens (n) | stock | this repo | speedup |
| --- | --- | --- | --- | --- |
| 17408 × 5120 | 1 | 266 µs | 168 µs | 1.59× |
| 5120 × 17408 | 1 | 265 µs | 184 µs | 1.44× |
| 4096 × 14336 | 1 | 169 µs | 132 µs | 1.28× |
| 17408 × 5120 | 4 | 981 µs | 471 µs | 2.08× |
| 17408 × 5120 | 8 | 2117 µs | 901 µs | 2.35× |
| 4096 × 14336 | 8 | 1527 µs | 614 µs | 2.49× |

The gain is largest when several tokens are processed at once (prompt chunks up to 8 tokens and speculative verification), because the trits are decoded once for all of them.

## What the patch changes

`patches/0001-vulkan-faster-PTQ1_0-mat-vec-on-RDNA1.patch`, against [PrismML-Eng/llama.cpp](https://github.com/PrismML-Eng/llama.cpp) commit `6447906` (2026-11-06):

1. **Byte per lane.** A 32-lane team works on one 128-weight block; lane *l* owns packed byte *l*. PTQ1_0 stores trit *t* of byte *j* at element `16*t + j`, so for a fixed trit the lanes read consecutive activations and the loads coalesce. The stock kernel gave each lane half a block, so every lane of a wave hit a different cache line.
2. **Activations in registers, reused across rows.** Each lane loads its five activations once per block and reuses them for every row of the workgroup, so register use no longer grows with the row count (the stock kernel spilled at 8+ rows).
3. **Two rows per multiply.** The bytes of two rows sit in the two 16-bit halves of one register; since 255×3 = 765 the halves never interfere, so one integer multiply peels a trit off both rows. The trits land in bytes 1 and 3 of the product, which AMD converts with `v_cvt_f32_ubyte1/3`.
4. **Decode once for several columns.** For small-batch mat-vec (speculative verification), trits are decoded once per row pair and reused for every column.
5. **Rows per workgroup**: default 16 on RDNA1, unchanged elsewhere. Override with `GGML_VK_PTQ1_ROWS` and `GGML_VK_PTQ1_MIN_ROWS`.

Only measured on RDNA1. Other GPUs keep the stock row count; benchmarks on other cards are welcome.

## The Windows VRAM trick (no patch needed)

On Windows, when other programs hold VRAM (desktop compositor, browser, wallpaper apps), the driver silently demotes some of llama.cpp's 1 GiB Vulkan allocations to system memory, and the GPU then reads those weights over PCIe. Sampling the `GPU Process Memory` counters showed 3.8 GB of weights in VRAM and 2.1 GB in shared memory, while the card still had about 1.5 GB free.

Smaller allocation blocks let Windows keep almost everything resident:

| `GGML_VK_SUBALLOCATION_BLOCK_SIZE` | Dedicated | Shared | tok/s |
| --- | --- | --- | --- |
| default (1 GiB) | 3822 MiB | 2115 MiB | 4.94 |
| 256 MiB | 4290 MiB | 1773 MiB | 7.31 |
| 64 MiB | 4867 MiB | 1239 MiB | 9.31 |
| 16 MiB | 5545 MiB | 776 MiB | 11.0–11.9 |
| **4 MiB** | **5781 MiB** | **584 MiB** | **15.15** |

(with `GGML_VK_DISABLE_HOST_VISIBLE_VIDMEM=1 GGML_VK_ENABLE_MEMORY_PRIORITY=1` and the patched kernel.)

Note this is the opposite direction to [llama.cpp#27734](https://github.com/ggml-org/llama.cpp/issues/27734), where a 24 GB card with a 131K context needed *larger* blocks. The best block size depends on whether the problem is fragmentation or residency.

`scripts/vram-residency.ps1` prints dedicated and shared memory of a running process, so you can check your own setup.

## Build and run

```bat
git clone https://github.com/PrismML-Eng/llama.cpp
cd llama.cpp
git checkout 6447906
git am path\to\patches\0001-vulkan-faster-PTQ1_0-mat-vec-on-RDNA1.patch
cmake -S . -B build -G "Visual Studio 17 2022" -A x64 -DGGML_VULKAN=ON -DLLAMA_CURL=OFF
cmake --build build --config Release --target llama-cli llama-bench
```

Download `Ternary-Bonsai-2-27B-PTQ1_0.gguf` (5.95 GB) from [prism-ml/Ternary-Bonsai-2-27B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf), then edit the two paths at the top of `scripts/chat.cmd` and run it.

Build from a path without non-ASCII characters, or apply the depfile fix proposed for upstream llama.cpp; otherwise MSBuild regenerates every shader on each build.

## Known limits

- With git-bash, set `MSYS_NO_PATHCONV=1` before passing `/p:` options to MSBuild.
- On this card PTQ1_0 decode is bound by arithmetic, not bandwidth. Verifying several tokens at once is expensive: in the full model, 6 tokens per pass cost 188 ms versus 69 ms for one, which limits speculative decoding.
- Single-token generation for this model cannot exceed about 75 tok/s on this card (5.94 GB read per token at 448 GB/s).

## License

MIT, same as llama.cpp. Model files keep their own licenses.

---

## 中文说明

### 这是什么

一份针对 RDNA1 显卡（RX 5700 / 5700 XT）的 llama.cpp Vulkan 补丁，加上一个不需要改代码的 Windows 显存技巧。两者加起来，让 27B 三值模型在 8GB 显卡上从约 5 tok/s 提到约 15 tok/s。所有数字都是在同一台机器上实测的。

### 补丁做了什么

PTQ1_0 是 PrismML 的三值格式，每 5 个三值权重压成一个字节。改动如下：

- **一条线程负责一个字节：** 激活值的读取变成连续的，并且在多行之间复用；
- **两行打包：** 把两行的字节放进一个 32 位寄存器的高低半区，一次乘法同时解两行；
- **多列复用：** 多个 token 一起验证时，权重只解码一次。

单 token 的矩阵乘快 1.3–1.6 倍；一次处理 8 个 token 时快 2.3–2.5 倍。正确性测试 168/168 通过。

### Windows 显存技巧

Windows 在显存紧张时，会悄悄把 llama.cpp 申请的 1GB 显存块整块挪到系统内存，GPU 只能走 PCIe 去读。把 `GGML_VK_SUBALLOCATION_BLOCK_SIZE` 设成 4MB，系统就能把几乎所有权重留在显存里，速度翻倍。`scripts/chat.cmd` 里已经设好了这几个环境变量。

### 局限

- 只在 RDNA1 上测过；
- 这张卡上三值解码受算力限制，一次验证多个 token 很贵，投机解码收益有限；
- 单 token 生成的物理上限约 75 tok/s。
