#!/usr/bin/env bash
# Quick tunnel (trycloudflare) cho CLIENT của stack local-5080 (nginx :8090).
# Dùng khi cần đưa UI ra ngoài để kiểm tra nhanh mà không cần đụng DNS/dashboard.
#   bash scripts/tunnel-client-quick.sh          # bật (in URL)
#   bash scripts/tunnel-client-quick.sh --status # xem URL đang chạy
#   bash scripts/tunnel-client-quick.sh --stop   # tắt
# Lưu ý: URL đổi mỗi lần bật; tiến trình chết khi WSL restart (không phải systemd service).
# Muốn tên miền cố định: thêm public hostname -> http://localhost:8090 cho tunnel có sẵn
# (cloudflared token ở /etc/cloudflared/token, ingress quản lý trên dashboard Cloudflare).
set -euo pipefail

LOG=/tmp/cf-quick-dock.log
PORT="${PORT:-8090}"

case "${1:-start}" in
  --stop)
    pkill -f "tunnel --no-autoupdate --url http://localhost:${PORT}" && echo "đã tắt" || echo "không có tiến trình nào"
    exit 0
    ;;
  --status)
    pgrep -a cloudflared | grep -F "url:http://localhost:${PORT}" >/dev/null 2>&1 || pgrep -af "cloudflared tunnel" | head -3
    grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOG" 2>/dev/null | tail -1 || echo "(chưa có URL trong $LOG)"
    exit 0
    ;;
esac

pgrep -f "tunnel --no-autoupdate --url http://localhost:${PORT}" >/dev/null && {
  echo "tunnel đã chạy:"; grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOG" | tail -1; exit 0; }

nohup cloudflared tunnel --no-autoupdate --url "http://localhost:${PORT}" > "$LOG" 2>&1 &
for _ in $(seq 1 30); do
  URL=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOG" | head -1 || true)
  [ -n "$URL" ] && break
  sleep 2
done
echo "URL: ${URL:-chưa lấy được, xem $LOG}"
echo "đăng nhập bằng tài khoản local (khuyến nghị đổi mật khẩu trước khi chia sẻ link)."
