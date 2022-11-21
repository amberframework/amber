FROM crystallang/crystal:latest

# Install Dependencies
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qq && apt-get install -y libpq-dev libsqlite3-dev libmysqlclient-dev libreadline-dev curl vim

WORKDIR /opt/amber

# Build Amber
ENV PATH /opt/amber/bin:$PATH
COPY . /opt/amber
RUN shards build amber

CMD ["crystal", "spec"]
