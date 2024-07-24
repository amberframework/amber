FROM 84codes/crystal:latest-ubuntu-jammy

# Install Dependencies
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qq && apt-get install -y libpq-dev libsqlite3-dev libmysqlclient-dev libreadline-dev curl vim

WORKDIR /opt/amber

# Build Amber
ENV PATH /opt/amber/bin:$PATH

COPY shard.yml /opt/amber
COPY shard.lock /opt/amber
RUN shards install

COPY src /opt/amber/src
COPY spec /opt/amber/spec
COPY bin /opt/amber/bin
RUN shards build amber

ENTRYPOINT []
