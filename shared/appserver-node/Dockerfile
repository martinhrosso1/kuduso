# Multi-stage build for AppServer (Node.js/TypeScript)
FROM node:18-alpine AS builder

WORKDIR /app

# Copy package files from shared/appserver-node
COPY shared/appserver-node/package*.json ./

# Install ALL dependencies (including devDependencies for building)
RUN npm ci

# Copy source code from shared/appserver-node
COPY shared/appserver-node/ ./

# Build TypeScript
RUN npm run build

# Production image
FROM node:18-alpine

WORKDIR /app

# Copy package files and install production dependencies only
COPY shared/appserver-node/package*.json ./
RUN npm ci --only=production && npm cache clean --force

# Copy built application from builder
COPY --from=builder /app/dist ./dist

# Copy contracts directory (needed for schema validation)
COPY contracts ./contracts

# Ensure rhino3dm WASM files are accessible
# The rhino3dm module in node_modules should already have the WASM files
# from the npm ci step above, but we verify they exist
RUN test -f node_modules/rhino3dm/rhino3dm.wasm || (echo "ERROR: rhino3dm WASM not found" && exit 1)

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:8080/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"

# Run the application
CMD ["node", "dist/index.js"]
