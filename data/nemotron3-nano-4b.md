| model                          |       size |     params | backend    | ngl |  fa | dev          |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | ------------ | --------------: | -------------------: |
| nemotron_h ?B Q4_K - Medium    |   2.63 GiB |     3.97 B | Vulkan     |  99 |   1 | Vulkan0      |           pp512 |        783.41 ± 0.99 |
| nemotron_h ?B Q4_K - Medium    |   2.63 GiB |     3.97 B | Vulkan     |  99 |   1 | Vulkan0      |           tg128 |         76.72 ± 0.01 |

build: 184f65360 (11829)
