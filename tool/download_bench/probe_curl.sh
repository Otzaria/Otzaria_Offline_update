#!/bin/sh
# usage: probe_curl.sh URL RANGE  -> prints sanitized per-hop headers
C="${CURL:-curl}"
URL="$1"; R="$2"
"$C" -s -L -o /dev/null --max-filesize 4096 -r "$R" -D - "$URL" -w 'final_http=%{http_code} size_download=%{size_download} remote_ip=%{remote_ip}\n' 2>&1 \
 | tr -d '\r' | grep -iE '^(HTTP/|location:|content-range:|accept-ranges:|content-length:|server:|via:|x-netfree|final_http)' \
 | sed -E 's#(location: https?://[^/]+)[^ ]*#\1/<path-redacted>#I'
echo "exit=$?"
