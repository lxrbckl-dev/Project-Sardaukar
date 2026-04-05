FROM node:20-alpine

RUN apk add --no-cache curl

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --production

COPY server.js ./

RUN adduser -D -h /home/app app
RUN mkdir -p /data/queue/incoming /data/queue/processing /data/queue/done /data/queue/failed
RUN chown -R app:app /data

USER app

EXPOSE 3800

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD curl -f http://localhost:3800/health || exit 1

CMD ["node", "server.js"]
