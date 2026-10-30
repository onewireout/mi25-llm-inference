| model                          |       size |     params | backend    | ngl | type_k | type_v |  fa | dev          |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -----: | -----: | --: | ------------ | --------------: | -------------------: |
| gemma4 26B.A4B IQ4_XS - 4.25 bpw |  12.65 GiB |    25.23 B | Vulkan     |  99 |   q8_0 |   q4_0 |   1 | Vulkan0      |           pp512 |        678.30 ± 5.40 |
| gemma4 26B.A4B IQ4_XS - 4.25 bpw |  12.65 GiB |    25.23 B | Vulkan     |  99 |   q8_0 |   q4_0 |   1 | Vulkan0      |           tg128 |         56.75 ± 0.06 |

build: 184f65360 (11829)
