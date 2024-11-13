# This script should ideally be set on cron to run every 15 days or so
# assuming letsencrypt 3 months certificate period, with `certbot renewal` already evaluate time remaining.
# The result should also be logged on the host.
# 0 0 15 * * cd /home/moodle && bash certbot_renewal.sh >> /var/log/moodle-cron-ssl.log 2>&1

# Print current date for monitoring
date

# List currently active certificates
docker compose -f docker-compose.production.yaml run --rm certbot certificates

# Attempting SSL certificate renewal
docker compose -f docker-compose.production.yaml run --rm certbot renew

# Reloading nginx for the new certificates without downtime
docker exec nginx service nginx reload

echo -e '\n\n\n'
