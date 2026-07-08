FROM node:20.18.0-alpine AS base

# Install dependencies only when needed
FROM base AS deps

RUN apk add --no-cache libc6-compat
# Set the working directory
WORKDIR /app

# Pull the bun binary from the official multi-arch image — installing deps with
# bun is much faster than `npm ci`, and this avoids a separate bun-install step.
COPY --from=oven/bun:1.2-alpine /usr/local/bin/bun /usr/local/bin/bun

# Install dependencies (bun reads the existing package-lock.json for pinned
# versions; Prisma's client is generated explicitly in the builder stage, so
# bun skipping postinstall scripts is fine).
COPY package.json package-lock.json* ./
RUN bun install

# Rebuild the source code only when needed
FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

ENV DATABASE_URL=file:/data/dev.db

# Generate Prisma client
RUN npx prisma generate

RUN npm run build

# Production image, copy all the files and run next
FROM base AS runner
WORKDIR /app

# Set environment variables
ENV NEXT_TELEMETRY_DISABLED=1

RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 -h /home/nextjs nextjs

# Set the correct permission for prerender cache
RUN mkdir .next
RUN chown nextjs:nodejs .next

# Set up /data directory with the right permissions
RUN mkdir -p /data/files/resumes && chown -R nextjs:nodejs /data/files/resumes

COPY --from=builder /app/public ./public
COPY --from=builder /app/prisma ./prisma
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

COPY docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh

EXPOSE 3737

ENV PORT=3737

ENTRYPOINT ["/app/docker-entrypoint.sh"]
