FROM crystallang/crystal:0.36.0-alpine
EXPOSE 3000
CMD ["/app/bin/scalr"]
RUN apk add --update imagemagick imagemagick-dev
WORKDIR /app
COPY shard.yml shard.lock /app/
RUN shards install --production
COPY athena.yml /app/athena.yml
COPY src /app/src/
RUN shards build --production --release
RUN apk del imagemagick-dev
