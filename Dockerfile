FROM crystallang/crystal:0.36.0
EXPOSE 3000
CMD ["/app/bin/scalr"]
RUN apt update && apt install -y libmagickwand-dev
WORKDIR /app
COPY shard.yml shard.lock /app
RUN shards install --production
COPY athena.yml /app/athena.yml
COPY src /app/src
RUN shards build --release --production
RUN apt purge -y libmagickwand-6.q16-dev
