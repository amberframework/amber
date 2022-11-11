FROM crystallang/crystal:latest

# Install Dependencies
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qq && apt-get install -y --no-install-recommends libpq-dev libsqlite3-dev libmysqlclient-dev libreadline-dev git curl vim netcat

WORKDIR /opt/amber

# Build Amber
ENV PATH /opt/amber/bin:$PATH
COPY . /opt/amber
RUN shards build amber --ignore-crystal-version

CMD ["crystal", "spec"]
