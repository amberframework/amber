FROM drujensen/crystal:0.22.0

ENV KGEN_VERSION 0.3.1

RUN cd /tmp && curl -L https://github.com/TechMagister/kemalyst-generator/archive/v$KGEN_VERSION.tar.gz | tar xz && cd kemalyst-generator-$KGEN_VERSION && crystal deps && make && cp bin/kgen /usr/local/bin/.

WORKDIR /app/user

ADD . /app/user

RUN crystal deps

CMD ["crystal", "spec"]
