FROM crystallang/crystal:0.35.0

# Install Dependencies
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qq && apt-get install -y --no-install-recommends libpq-dev libsqlite3-dev libmysqlclient-dev libreadline-dev git curl vim netcat

# Install Node
RUN curl -sL https://deb.nodesource.com/setup_6.x | bash -
RUN apt-get install -y nodejs

WORKDIR /opt/launch

# Build Launch
ENV PATH /opt/launch/bin:$PATH
COPY . /opt/launch
RUN shards build launch

CMD ["crystal", "spec"]
