FROM node:20-alpine
WORKDIR /app

COPY package*.json ./
RUN npm ci --production

COPY src/ ./src/

# Vytvořit adresáře a nastavit vlastnictví PŘED přepnutím na node
RUN mkdir -p /app/logs /app/data /app/update \
    && chown -R node:node /app

EXPOSE 8090
USER node
CMD ["node", "src/index.js"]
