#!/bin/sh
set -eu

. ./build

mode="${mode:-full}"
bench=public/bench.txt
bench_incr=public/bench-incremental.txt
bench_warm=public/bench-warmup.txt
measurement_version=2
bundler="turbopack"

run_build() {
  npm run build-only
}

reset_marker_baseline() {
  cat > app/benchmark-marker.tsx <<'MARKER'
// This file is modified during incremental builds to trigger recompilation
// It gets reset to this baseline state before each cold build
// Marker: baseline
export function BenchmarkMarker() {
  return <span data-benchmark="baseline" style={{ display: 'none' }} />
}
MARKER
}

set_incremental_marker() {
  cat > app/benchmark-marker.tsx <<MARKER
// This file is modified during incremental builds to trigger recompilation
// Marker: ${build_id}-incr-$(date +%s)
export function BenchmarkMarker() {
  return <span data-benchmark="${build_id}-incr" style={{ display: 'none' }} />
}
MARKER
}

write_common_metadata() {
  target="$1"
  {
    echo "build_id=$build_id"
    echo "push_ts=$push_ts"
    echo "mode=$mode"
    echo "measurement_version=$measurement_version"
  } > "$target"
}

next_version() {
  node -p "require('next/package.json').version"
}

echo "starting build $build_id (mode=$mode)"

case "$mode" in
  full)
    reset_marker_baseline
    rm -rf .next

    write_common_metadata "$bench"
    echo "start_ts=$(date +%s)" >> "$bench"
    run_build

    cache_exists_after="false"
    cache_size_after="0"
    if [ -d ".next/cache" ]; then
      cache_exists_after="true"
      cache_size_after=$(du -sh .next/cache 2>/dev/null | cut -f1 || echo "unknown")
    fi

    echo "end_ts=$(date +%s)" >> "$bench"
    echo "next_version=$(next_version)" >> "$bench"
    echo "bundler=$bundler" >> "$bench"
    echo "cache_exists_after=$cache_exists_after" >> "$bench"
    echo "cache_size_after=$cache_size_after" >> "$bench"
    echo "vercel_force_no_build_cache=${VERCEL_FORCE_NO_BUILD_CACHE:-0}" >> "$bench"

    echo "=== Full build results ==="
    cat "$bench"
    ;;

  warm)
    reset_marker_baseline

    write_common_metadata "$bench_warm"
    echo "start_ts=$(date +%s)" >> "$bench_warm"
    run_build

    cache_exists_after="false"
    cache_size_after="0"
    if [ -d ".next/cache" ]; then
      cache_exists_after="true"
      cache_size_after=$(du -sh .next/cache 2>/dev/null | cut -f1 || echo "unknown")
    fi

    echo "end_ts=$(date +%s)" >> "$bench_warm"
    echo "next_version=$(next_version)" >> "$bench_warm"
    echo "bundler=$bundler" >> "$bench_warm"
    echo "warmup_complete=true" >> "$bench_warm"
    echo "cache_exists_after=$cache_exists_after" >> "$bench_warm"
    echo "cache_size_after=$cache_size_after" >> "$bench_warm"

    echo "=== Warmup build results ==="
    cat "$bench_warm"
    ;;

  incremental)
    cache_exists="false"
    cache_size="0"
    if [ -d ".next/cache" ]; then
      cache_exists="true"
      cache_size=$(du -sh .next/cache 2>/dev/null | cut -f1 || echo "unknown")
    fi

    set_incremental_marker

    write_common_metadata "$bench_incr"
    echo "cache_exists=$cache_exists" >> "$bench_incr"
    echo "cache_size=$cache_size" >> "$bench_incr"
    echo "start_ts=$(date +%s)" >> "$bench_incr"
    run_build

    echo "end_ts=$(date +%s)" >> "$bench_incr"
    echo "next_version=$(next_version)" >> "$bench_incr"
    echo "bundler=$bundler" >> "$bench_incr"

    echo "=== Incremental build results ==="
    cat "$bench_incr"
    ;;

  *)
    echo "Unknown mode: $mode"
    echo "Expected one of: full, warm, incremental"
    exit 1
    ;;
esac
