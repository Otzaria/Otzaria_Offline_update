#!/bin/bash
# usage: curl_bench.sh <mode:single|seg4> <url> <size> <sha256> <outdir(fresh)>
# Times network separately from join and sha256 (MiB/s). Prints no URLs/query strings.
C="${CURL:-curl}"
MODE=$1; URL=$2; SIZE=$3; SHA=$4; OUT=$5
rm -rf "$OUT"; mkdir -p "$OUT"
now() { date +%s.%N; }
t0=$(now)
if [ "$MODE" = single ]; then
  "$C" -s -L -o "$OUT/f" -w 'http=%{http_code} bytes=%{size_download} avg_Bps=%{speed_download}\n' "$URL"
  t1=$(now); tj=$t1
else
  N=${N:-4}; per=$((SIZE / N)); pids=()
  for k in $(seq 0 $((N-1))); do
    s=$((k*per)); e=$(( k==N-1 ? SIZE-1 : (k+1)*per-1 ))
    "$C" -s -L -r "$s-$e" -o "$OUT/seg$k" -w "seg$k http=%{http_code} bytes=%{size_download} avg_Bps=%{speed_download}\n" "$URL" &
    pids+=($!)
  done
  wait "${pids[@]}"
  t1=$(now)
  cat $(for k in $(seq 0 $((N-1))); do echo "$OUT/seg$k"; done) > "$OUT/f"
  rm -f "$OUT"/seg*
  tj=$(now)
fi
got=$(sha256sum "$OUT/f" | cut -d' ' -f1)
t2=$(now)
sz=$(stat -c %s "$OUT/f")
awk -v m=$MODE -v a=$t0 -v b=$t1 -v j=$tj -v c=$t2 -v sz=$sz -v want=$SIZE -v ok=$([ "$got" = "$SHA" ] && echo yes || echo NO) \
 'BEGIN{printf "SUMMARY curl-%s size=%d(want %d) net=%.2fs join=%.2fs hash=%.2fs total=%.2fs net_MiBps=%.2f sha_ok=%s\n", m, sz, want, b-a, j-b, c-j, c-a, sz/1048576/(b-a), ok}'
rm -rf "$OUT"
