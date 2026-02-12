# ---------------------------------------------------------------------------
# Stage 1: Build the Hugo site
# ---------------------------------------------------------------------------
FROM hugomods/hugo:exts-0.152.2 AS build

WORKDIR /src

# Copy the full project (theme submodule must be checked out)
COPY docs/ ./docs/

WORKDIR /src/docs

# Build the static site – minified, no drafts, no future-dated content
RUN hugo --minify

# ---------------------------------------------------------------------------
# Stage 2: Serve with a hardened, minimal Nginx image
# ---------------------------------------------------------------------------
FROM nginx:1.27-alpine AS runtime

# Remove the default Nginx site
RUN rm -rf /usr/share/nginx/html/*

# Copy the built static files from the build stage
COPY --from=build /src/docs/public /usr/share/nginx/html

# Copy custom Nginx configuration
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf

# Run Nginx as non-root for better security
RUN addgroup -g 1001 -S appgroup && \
    adduser  -u 1001 -S appuser -G appgroup && \
    chown -R appuser:appgroup /usr/share/nginx/html && \
    chown -R appuser:appgroup /var/cache/nginx && \
    chown -R appuser:appgroup /var/log/nginx && \
    touch /var/run/nginx.pid && \
    chown appuser:appgroup /var/run/nginx.pid

USER 1001

EXPOSE 8080

# Healthcheck for orchestrators (Docker Compose, Kubernetes, etc.)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -qO- http://localhost:8080/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
