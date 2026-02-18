FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --production
COPY src/ ./src/
COPY update/ ./update/
EXPOSE 8090
USER node
CMD ["node", "src/index.js"]
