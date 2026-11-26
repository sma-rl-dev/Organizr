#!/bin/sh
# One container, two processes: php-fpm daemonizes, nginx stays in the foreground
# as PID 1 so `docker stop` is the only shutdown path needed.
set -eu
php-fpm -D
exec nginx -g 'daemon off;'
