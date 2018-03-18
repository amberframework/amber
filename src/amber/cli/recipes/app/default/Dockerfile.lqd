FROM amberframework/amber:v{{ amber_version }}

WORKDIR /app

COPY shard.* /app/
RUN crystal deps

COPY . /app

RUN rm -rf /app/node_modules

CMD amber watch
