FROM node:20-alpine

RUN apk add --no-cache curl bash unzip

# Install Bun (runtime dependency for ctrl-daemon)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

# Install ctrl-daemon
RUN npm install -g @bulletproof-sh/ctrl-daemon@latest

EXPOSE 3802

CMD ["ctrl-daemon", "--port", "3802", "--host", "0.0.0.0", "--no-tui", "--no-open", "--hooks", "--share"]
