FROM node:20-alpine

RUN apk add --no-cache curl

WORKDIR /app

COPY server.js index.html ./

RUN adduser -D -h /home/app app
USER app

EXPOSE 3801

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD curl -f http://localhost:3801/health || exit 1

CMD ["node", "server.js"]
