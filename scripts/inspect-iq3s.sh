#!/bin/bash
# build, dump RADV shaders for 1 token on the MI25, report iq3_s matvec registers + load placement
L=~/Documents/Personal/Projects/llama.cpp-mi25/latest; S=$(dirname "$0"); tag=$1
cmake --build $L/build-vulkan --target llama-bench test-backend-ops -j16 2>&1 | grep -E 'error|ERROR' && exit 1
cd $S && MESA_SHADER_CACHE_DISABLE=true RADV_DEBUG=shaders,nocache timeout 300 $L/build-vulkan/bin/llama-bench -m /var/lib/llama-cpp/qwen3.8:27B-3bit-GSQ.gguf -dev Vulkan1 -p 0 -n 1 -r 1 --no-warmup > /dev/null 2> dump_$tag.txt
awk '/^shader: MESA_SHADER_COMPUTE/{n++} {print n"\t"$0}' dump_$tag.txt > num_$tag.txt
N=$(grep -P '\tshared_size: 2048' num_$tag.txt | cut -f1 | while read k; do grep -qP "^$k\t.*load_const \(0x0000006e = 110\)" num_$tag.txt && echo $k; done | head -1)
grep -P "^$N\t" num_$tag.txt | cut -f2- | sed -n '/^disasm:/,$p' | grep -vE '^\[[0-9]+\] [0-9a-f]{8}' > code_$tag.txt
rm num_$tag.txt dump_$tag.txt
echo "shader #$N  VGPRs: $(grep -oE '\bv\[[0-9]+:[0-9]+\]|\bv[0-9]+\b' code_$tag.txt | sed -E 's/v\[([0-9]+):([0-9]+)\]/\1 \2/;s/^v//' | awk 'NF==2{for(i=$1;i<=$2;i++)print i; next}{print}' | sort -un | wc -l)"
s=$(grep -nE '^BB10:' code_$tag.txt | cut -d: -f1); e=$(grep -nE '^BB5:' code_$tag.txt | cut -d: -f1)
echo "main loop, weight loads per 100-line bucket:"; awk -v s=$s -v e=$e 'NR>=s && NR<=e { b=int((NR-s)/100); if($0~/buffer_load.*s\[24:27\]/)L[b]++; mb=b} END{for(i=0;i<=mb;i++) printf "%d ", L[i]; print ""}' code_$tag.txt
