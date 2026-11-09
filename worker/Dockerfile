FROM node:24-bookworm-slim

WORKDIR /app

ENV NODE_ENV=production
ENV FACE_MODEL_DIR=/app/node_modules/@vladmandic/face-api/model

COPY package.json package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund

COPY worker ./worker
COPY src/lib/media/constants.js ./src/lib/media/constants.js
COPY src/lib/media/r2Config.js ./src/lib/media/r2Config.js

USER node

CMD ["node", "worker/index.js"]
