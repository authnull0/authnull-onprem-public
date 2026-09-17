#!/bin/bash
# =============================================================================
# Authnull On-Prem Deployment Script
# Usage: ./deploy.sh
# Requires: Docker, Docker Compose, .env file configured
# =============================================================================

set -e

echo "=== Authnull On-Prem Deployment ==="

# Check .env exists
if [ ! -f .env ]; then
  echo "ERROR: .env not found. Copy .env.prod to .env and fill in your values."
  exit 1
fi

# Check required vars
check_var() {
  val=$(grep "^$1=" .env | cut -d= -f2-)
  if [ -z "$val" ] || [ "$val" = "CHANGE_ME"* ] || [[ "$val" == *"CHANGE_ME"* ]]; then
    echo "ERROR: $1 is not set in .env"
    exit 1
  fi
}

check_var "DOMAIN"
check_var "DB_PASSWORD"
check_var "REDIS_PASSWORD"
check_var "ENCRYPTION_KEY"
check_var "SMTP_HOST"

echo "✓ .env looks good"

# Pull latest images
echo "Pulling latest images..."
docker compose pull --ignore-pull-failures

# Start stack
echo "Starting services..."
docker compose up -d

# Wait for authnull-service to be healthy
echo "Waiting for authnull-service to be healthy..."
for i in $(seq 1 30); do
  STATUS=$(docker compose ps authnull-service --format json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('Health',''))" 2>/dev/null || echo "")
  if [ "$STATUS" = "healthy" ]; then
    echo "✓ authnull-service is healthy"
    break
  fi
  echo "  waiting... ($i/30)"
  sleep 5
done

# Show status
echo ""
echo "=== Service Status ==="
docker compose ps

echo ""
echo "=== Deployment Complete ==="
echo "Admin UI:  https://$(grep '^DOMAIN=' .env | cut -d= -f2)"
echo "SSC:       https://$(grep '^DOMAIN=' .env | cut -d= -f2)/ssc/signin"
echo "Backend:   https://$(grep '^DOMAIN=' .env | cut -d= -f2)/api/v1"
echo ""
echo "Next steps:"
echo "  1. Configure nginx: cp nginx/authnull.conf /etc/nginx/sites-available/"
echo "     Replace 'yourdomain.com' with your actual domain"
echo "     ln -s /etc/nginx/sites-available/authnull.conf /etc/nginx/sites-enabled/"
echo "  2. Get SSL cert: certbot --nginx -d \$(grep '^DOMAIN=' .env | cut -d= -f2)"
echo "  3. Reload nginx: nginx -s reload"
