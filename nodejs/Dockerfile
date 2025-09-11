# syntax=docker/dockerfile:1
FROM dockerdevrel/dhi-node:24-debian13-dev AS build-stage

ENV NODE_ENV=production
WORKDIR /usr/src/app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

FROM dockerdevrel/dhi-node:24-debian13 AS runtime-stage

ENV NODE_ENV=production
WORKDIR /usr/src/app
COPY --from=build-stage /usr/src/app/node_modules ./node_modules
COPY src ./src
EXPOSE 3000
CMD ["node", "src/index.js"]
