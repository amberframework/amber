FROM crystallang/crystal:0.36.1

# Install Dependencies
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qq && apt-get install -y --no-install-recommends libpq-dev libsqlite3-dev libmysqlclient-dev libreadline-dev git curl vim netcat

# Install Node
RUN curl -sL https://deb.nodesource.com/setup_14.x | bash -
RUN apt-get install -y nodejs

WORKDIR /opt/amber

# Build Amber
ENV PATH /opt/amber/bin:$PATH
COPY . /opt/amber
RUN shards build amber

CMD ["crystal", "spec"]
