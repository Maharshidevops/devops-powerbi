# =============================================================
# Q11  React Frontend Dockerfile
# Multi-stage build | Final image target: < 150 MB | Non-root
#
# (a) ENTRYPOINT vs CMD:
#     ENTRYPOINT defines the executable that always runs when the
#     container starts. It cannot be replaced by passing a command
#     at runtime  only overridden with `docker run --entrypoint`.
#     CMD provides default arguments to ENTRYPOINT (or a default
#     command if no ENTRYPOINT is set). CMD IS replaced whenever
#     you pass a command at runtime or in an ECS Task Definition's
#     "command" field.
#
# (b) ECS Task Definition "command" override:
#     ECS maps its "command" field directly to Docker's CMD.
#     So if you set ENTRYPOINT ["nginx"] and override "command"
#     in ECS to ["-g", "daemon off;"], the container runs:
#         nginx -g daemon off;
#     ENTRYPOINT stays fixed; only CMD (the arguments) changes.
#     If you need to replace the binary itself, use the ECS
#     "entryPoint" field  not "command".
#
# How we stay under 150 MB (deliberate exclusions):
#   1. Stage 1 uses node:20-alpine only for building. The entire
#      node:20-alpine layer (~170 MB), node_modules (~200-400 MB),
#      src/, tests/, and all build tooling are LEFT BEHIND  only
#      the compiled /app/dist output is copied forward.
#   2. Stage 2 base is nginx:1.25-alpine (~45 MB), not a full
#      debian/ubuntu nginx image (~180 MB). Alpine saves ~135 MB.
#   3. We run `npm ci --omit=dev` in stage 1 so devDependencies
#      (jest, eslint, storybook etc.) are never installed. Cuts
#      node_modules by 40-60% before the build even starts.
#   4. .dockerignore (see companion file) excludes node_modules,
#      .git, coverage/, and test fixtures before the COPY  Docker
#      build context stays small and layer cache works correctly.
#   5. No curl, wget, git, or package managers in the final image.
#      nginx:alpine ships with nothing extra.
#   Result: base nginx:alpine ~45 MB + compiled React ~5-15 MB
#           = well under 150 MB target.
# =============================================================

# ── Stage 1: Build ──────────────────────────────────────────
FROM node:20-alpine AS builder

WORKDIR /app

# Copy manifests first so npm ci is cached as its own layer.
# Docker only re-runs npm ci when package.json or the lock file
# actually changes  not on every source code edit.
COPY package.json package-lock.json ./

# --omit=dev skips devDependencies (jest, eslint, storybook…)
# --prefer-offline uses the local cache where possible
RUN npm ci --omit=dev --prefer-offline

# Copy source after installing deps so source changes don't
# invalidate the node_modules cache layer above
COPY . .

# Build the production bundle. Output lands in /app/dist.
# VITE_API_URL can be passed as a build-arg if the API base URL
# differs per environment (pass with --build-arg in CI).
ARG VITE_API_URL=""
ENV VITE_API_URL=$VITE_API_URL

RUN npm run build

# ── Stage 2: Serve ──────────────────────────────────────────
# nginx:1.25-alpine is ~45 MB. We copy ONLY /app/dist from the
# builder stage  nothing else from stage 1 comes across.
FROM nginx:1.25-alpine AS final

# Remove the default nginx configuration that ships with the image.
# It listens on port 80 with a default server block we don't want.
RUN rm /etc/nginx/conf.d/default.conf

# Copy our custom nginx config (handles SPA routing + security headers)
COPY nginx.conf /etc/nginx/conf.d/app.conf

# Copy the compiled React bundle from stage 1
COPY --from=builder /app/dist /usr/share/nginx/html

# nginx needs to write its PID file and cache dirs.
# Grant ownership to the built-in nginx user (uid 101 on alpine).
# We do NOT create a new user  nginx:alpine already ships with
# a non-root 'nginx' user at uid 101; we just need correct ownership.
RUN chown -R nginx:nginx /usr/share/nginx/html \
    && chown -R nginx:nginx /var/cache/nginx \
    && chown -R nginx:nginx /var/log/nginx \
    && touch /var/run/nginx.pid \
    && chown nginx:nginx /var/run/nginx.pid

# Drop to non-root. From this point the process runs as uid 101.
USER nginx

# Document the port  doesn't actually publish it; that's done
# at `docker run -p` time or in the ECS task definition.
EXPOSE 80

# ENTRYPOINT locks nginx as the binary that always runs.
# CMD provides the default argument  daemon off keeps nginx in
# the foreground so Docker/ECS sees it as PID 1 and can manage it.
# An ECS "command" override replaces CMD, not ENTRYPOINT.
ENTRYPOINT ["nginx"]
CMD ["-g", "daemon off;"]
